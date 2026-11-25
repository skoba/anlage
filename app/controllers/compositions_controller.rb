class CompositionsController < ApplicationController
  def index
    @compositions = Composition.latest_versions.includes(:template).order(created_at: :desc)
  end

  def show
    @composition = Composition.find(params[:id])
    @editable = @composition.latest_version? && Opt::CompositionEditability.editable?(@composition.template, @composition.rm_composition)
  end

  # 修正の帳票（skoba/anlage#138）。前の版の値を読み戻して入れる。置き換えられた版と、読み戻せない形の記録は 422
  def edit
    @composition = Composition.find(params[:id])
    @template = @composition.template
    return render_not_editable unless editable?(@composition)

    @values = Opt::CompositionReader.call(@template, JSON.generate(@composition.rm_composition))
    @errors = {}
    render "forms/show"
  end

  # 修正の保存。同じ uid で commit し、RM の側に版を 1 つ足す。EHR は元の記録のまま（いまの患者ではない）
  def update
    previous = Composition.find(params[:id])
    @composition = previous
    @template = previous.template
    return render_not_editable unless editable?(previous)

    values = Opt::FormBehaviors.apply(@template, (params[:values] || {}).to_unsafe_h)
    result = Opt::FormValidator.call(@template, values)
    unless result.valid?
      @values = values
      @errors = result.errors
      return render "forms/show", status: :unprocessable_content
    end

    ehr = OpenehrRails::Rm::Composition.latest.find_by(uid: previous.uid)&.ehr
    commit = Opt::RmCompositionCommitter.call(@template, values, ehr: ehr, uid: previous.uid)
    composition = @template.compositions.create!(rm_composition: commit.canonical_hash, uid: commit.uid)
    redirect_to composition_path(composition), notice: "修正しました"
  end

  def create
    @template = Template.active.find_by!(template_id: params[:template_id])
    # skoba/anlage#47 変更 4: 帳票の振る舞い（config/form_behaviors.yml）はサーバが権威
    values = Opt::FormBehaviors.apply(@template, (params[:values] || {}).to_unsafe_h)

    # skoba/anlage#36: 閲覧専用テンプレートへの POST は 500 ではなく説明付きの 422
    if @template.preview_only?
      @values = values
      @errors = {}
      return render "forms/show", status: :unprocessable_content
    end

    result = Opt::FormValidator.call(@template, values)
    unless result.valid?
      @values = values
      @errors = result.errors
      return render "forms/show", status: :unprocessable_content
    end

    commit = Opt::RmCompositionCommitter.call(@template, values, ehr: current_ehr)

    composition = @template.compositions.create!(
      rm_composition: commit.canonical_hash,
      uid: commit.uid
    )
    redirect_to composition_path(composition), notice: "保存しました"
  end

  private

  def editable?(composition)
    composition.uid.present? && composition.latest_version? &&
      Opt::CompositionEditability.editable?(composition.template, composition.rm_composition)
  end

  def render_not_editable
    @editable = false
    render :show, status: :unprocessable_content
  end
end
