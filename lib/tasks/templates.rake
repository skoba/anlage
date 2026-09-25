namespace :templates do
  desc "Rebuild web_template (fields, input_kind, rm_type_alternatives) of every template from its source_xml"
  # pathcards:backfill と対の運用ツール（skoba/anlage#33 裁定 C）。checksum・pathcards・
  # status は変えない。field の導出規則を変えた後、登録済みテンプレートに効かせる手段。
  task rebuild_web_template: :environment do
    Template.find_each do |template|
      template.rebuild_web_template!
      puts "#{template.template_id} v#{template.version}: #{template.fields.size} field(s) rebuilt"
    end
  end
end
