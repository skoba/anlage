class FormsController < ApplicationController
  # Renders a working form for a registered template by interpreting its
  # web_template at request time -- no code generation, no per-template
  # controller/view.
  def show
    @template = Template.active.find_by!(template_id: params[:template_id])
    @values = {}
    @errors = {}
  end
end
