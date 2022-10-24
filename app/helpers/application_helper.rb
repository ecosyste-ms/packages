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

  def format_funding_links(package)
    Array(package.metadata["funding"]).map do |funding|
      sanitize_user_url(funding.is_a?(Hash) ? funding['url'] : funding)
    end
  end
end
