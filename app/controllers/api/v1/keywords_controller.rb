class Api::V1::KeywordsController < Api::V1::ApplicationController
  def index
    keywords = Package.keywords

    @pagy, @keywords = pagy_array(keywords)
  end

  def show
    @keyword = params[:id]

    @related_keywords = Rails.cache.fetch(["related_keywords", "api", @keyword], expires_in: 1.day) do
      Package.related_keywords(@keyword)
    end
    @pagy, @packages = pagy_countless(Package.keyword(@keyword).includes(:registry, {maintainers: :registry}))
    fresh_when(@packages, public: true)
  end
end