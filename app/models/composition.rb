class Composition < ApplicationRecord
  belongs_to :template

  def concept
    rm_composition["name"]&.dig("value") || template.template_id
  end
end
