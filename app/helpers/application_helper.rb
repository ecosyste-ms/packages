module ApplicationHelper
  include Pagy::Frontend
  include SanitizeUrl

  def sanitize_user_url(url)
    return unless url =~ /\A#{URI::regexp}\z/
    sanitize_url(url, :schemes => ['http', 'https'])
  end

  def download_period(downloads_period)
    case downloads_period
    when "last-month"
      "last month"
    when "total"
      "total"
    end
  end
end
