class CompositionsController < ApplicationController
  def index
    @compositions = Composition.includes(:template).order(created_at: :desc)
  end

  def show
    @composition = Composition.find(params[:id])
  end

  def create
    @template = Template.active.find_by!(template_id: params[:template_id])
    values = (params[:values] || {}).to_unsafe_h

    result = Opt::FormValidator.call(@template, values)
    unless result.valid?
      @values = values
      @errors = result.errors
      return render "forms/show", status: :unprocessable_content
    end

    commit = Opt::RmCompositionCommitter.call(@template, values)

    composition = @template.compositions.create!(
      rm_composition: commit.canonical_hash,
      uid: commit.uid
    )
    redirect_to composition_path(composition), notice: "登録しました"
  end
end
