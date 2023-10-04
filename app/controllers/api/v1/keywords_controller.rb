class Api::V1::KeywordsController < Api::V1::ApplicationController
  def index
    keywords = Package.keywords

    @pagy, @keywords = pagy_array(keywords)
  end

  def show
    @keyword = params[:id]

    scope = Package.keyword(@keyword).includes(:registry,{maintainers: :registry})

    @related_keywords = (scope.pluck(:keywords).flatten - [@keyword]).inject(Hash.new(0)) { |h, e| h[e] += 1; h }.sort_by { |_, v| -v }.first(100)
    @pagy, @packages = pagy_countless(scope)
  end
end