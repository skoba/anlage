module Charts
  # 患者の記録を、患者の画面（U1）の部品に配る（skoba/anlage#219、docs/design/u1-patient-chart-plan.md 1.1〜1.5、R-20261127-13）。
  # 記録は RM の側の最新の版から削除済みを除いたもの（患者の画面の一覧と同じ）。値は記録から（Opt::CompositionReader）、
  # 部品と意味（ラベル・単位・選択肢の表示）はテンプレートから（Charts::Rules）。
  # テンプレートが未登録・読み戻せない・部品の無い記録は others（記録の一覧）に入れる。
  class PatientChart
    Result = Struct.new(:problems, :series, :lab_rows, :orders, :others, keyword_init: true)
    # value は数（グラフの座標）、display は表示の文字（精度を作らない。Opt::QuantityDisplay、skoba/anlage#250）
    Point = Struct.new(:at, :value, :display, :units, :record, keyword_init: true)
    Series = Struct.new(:template_id, :field_name, :label, :units, :points, keyword_init: true)
    LabRow = Struct.new(:template_id, :name, :units, :points, keyword_init: true)
    Problem = Struct.new(:record, :at, :template_id, :diagnosis, :certainty, :onset, keyword_init: true)
    Order = Struct.new(:record, :at, :template_id, keyword_init: true)
    Reading = Struct.new(:record, :template, :at, :values, :displays, keyword_init: true)

    def self.call(ehr)
      new(ehr).call
    end

    def initialize(ehr)
      @ehr = ehr
      @templates = Template.active.order(:id).index_by(&:template_id)
      @components = Hash.new { |hash, template_id| hash[template_id] = Rules.for(@templates.fetch(template_id)) }
    end

    def call
      readings, others = read_records
      Result.new(problems: problems(readings), series: series(readings), lab_rows: lab_rows(readings),
                 orders: orders(readings), others:)
    end

    private

    def read_records
      readings = []
      others = []
      OpenehrRails::Rm::Composition.latest.not_deleted.where(ehr: @ehr).order(:id).each do |record|
        reading = read(record)
        reading && @components[record.template_id].any? ? readings << reading : others << record
      end
      [ readings.sort_by { [ _1.at || Time.at(0), _1.record.id ] }, others ]
    end

    def read(record)
      template = @templates[record.template_id]
      return unless template

      canonical = record.to_canonical_hash
      json = JSON.generate(canonical)
      Reading.new(record:, template:, at: Opt::RecordedTime.of(canonical) || record.context_start_time,
                  values: Opt::CompositionReader.call(template, json),
                  displays: Opt::CompositionReader.call(template, json, display: true))
    rescue Opt::CompositionReader::InvalidComposition
      nil
    end

    def of_kind(reading, kind) = @components[reading.template.template_id].select { _1.kind == kind }

    def problems(readings)
      readings.flat_map do |reading|
        of_kind(reading, :problem_list).filter_map do |component|
          fields = component.fields
          diagnosis = fields["diagnosis"] && reading.displays[fields["diagnosis"]["name"]]
          next if diagnosis.blank?

          certainty = fields["certainty"] && reading.values[fields["certainty"]["name"]]
          Problem.new(record: reading.record, at: reading.at, template_id: component.template_id, diagnosis:,
                      certainty: certainty.presence && (fields["certainty"].dig("code_labels", certainty) || certainty),
                      onset: fields["onset"] && reading.values[fields["onset"]["name"]].presence)
        end
      end
    end

    def series(readings)
      groups = {}
      readings.each do |reading|
        of_kind(reading, :time_series).each do |component|
          field = component.fields.fetch("value")
          value = reading.values[field["name"]]
          next if value.blank?

          units = reading.values["#{field['name']}__units"].presence || field["units"]
          key = [ component.template_id, field["name"], units ]
          groups[key] ||= Series.new(template_id: component.template_id, field_name: field["name"], label: field["label"], units:, points: [])
          groups[key].points << Point.new(at: reading.at, value: value.to_f, display: reading.displays[field["name"]], units:, record: reading.record)
        end
      end
      groups.values.sort_by { |series| [ template_order(series.template_id), field_order(series), series.units.to_s ] }
    end

    # 検査結果の時系列表: 行 = （テンプレート、分析名の値〔完全一致〕、単位）。単位が違えば別の行（1.5 節）
    def lab_rows(readings)
      rows = {}
      readings.each do |reading|
        of_kind(reading, :lab_table).each do |component|
          name = reading.values[component.fields["name"]["name"]]
          value_field = component.fields["value"]
          value = reading.values[value_field["name"]]
          next if name.blank? || value.blank?

          units = reading.values["#{value_field['name']}__units"].presence || value_field["units"]
          key = [ component.template_id, name, units ]
          rows[key] ||= LabRow.new(template_id: component.template_id, name:, units:, points: [])
          rows[key].points << Point.new(at: reading.at, value: value.to_f, display: reading.displays[value_field["name"]], units:,
                                        record: reading.record)
        end
      end
      rows.values.sort_by { |row| [ template_order(row.template_id), row.points.first.at || Time.at(0), row.points.first.record.id ] }
    end

    def orders(readings)
      readings.select { of_kind(_1, :orders).any? }.map { Order.new(record: _1.record, at: _1.at, template_id: _1.template.template_id) }
    end

    def template_order(template_id) = @templates.keys.index(template_id) || @templates.size

    def field_order(series)
      @templates.fetch(series.template_id).fields.index { _1["name"] == series.field_name } || 0
    end
  end
end
