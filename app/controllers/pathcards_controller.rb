class PathcardsController < ApplicationController
  def search
    @query = params[:q].to_s
    @pathcards = Opt::PathcardSearch.call(@query)
  end
end
