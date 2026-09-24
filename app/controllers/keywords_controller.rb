class KeywordsController < ApplicationController
  def index
    @pagy, @keywords = pagy_array(Package.keywords)
  end

  def show
    @keyword = params[:id]

    @related_keywords = Rails.cache.fetch(["related_keywords", "html", @keyword], expires_in: 1.day) do
      Package.active.related_keywords(@keyword)
    end

    scope = Package.active.keyword(@keyword).includes(:registry).order(Arel.sql("(rankings->>'average')::text::float").asc)
    @pagy, @packages = pagy_countless(scope)
  end
end