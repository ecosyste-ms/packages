module ApplicationHelper
  include Pagy::Frontend
  include SanitizeUrl

  def sanitize_user_url(url)
    return unless url =~ /\A#{URI::regexp}\z/
    sanitize_url(url, :schemes => ['http', 'https'])
  end
end
