module ApplicationHelper
  include Pagy::Frontend
  include SanitizeUrl

  def sanitize_user_url(url)
    return unless url && url.is_a?(String)
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

  def meta_description
    @meta_description || app_description
  end

  def meta_title
    [@meta_title, "Ecosyste.ms: Packages"].compact.join(" | ")
  end

  def app_name
    "Packages"
  end

  def app_description
    "An open API service providing package, version and dependency metadata of many open source software ecosystems and registries."
  end

  def severity_class(severity)
    case severity.downcase
    when 'low'
      'success'
    when 'moderate'
      'warning'
    when 'high'
      'danger'
    when 'critical'
      'dark'
    else
      'info'
    end
  end
end
