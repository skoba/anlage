namespace :pathcards do
  desc "Extract pathcards for templates that do not have them"
  task backfill: :environment do
    Template.where(pathcards: nil).find_each do |template|
      cards = Opt::PathcardExtractor.call(template).cards
      template.update!(pathcards: cards)
    end
  end
end
