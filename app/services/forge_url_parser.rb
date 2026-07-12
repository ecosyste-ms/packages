class ForgeUrlParser < UrlParser
  HOSTS = %w[codeberg.org gitea.com].freeze
  HOST_PATTERN = HOSTS.map { |host| Regexp.escape(host) }.join('|').freeze

  private

  def full_domain
    "https://#{matched_host}"
  end

  def parseable?
    matched_host.present?
  end

  def includes_domain?
    matched_host.present?
  end

  def extractable_early?
    false
  end

  def remove_domain
    url.gsub!(/(?:#{HOST_PATTERN})(?::|\/)?/i, '')
  end

  def matched_host
    @matched_host ||= url.gsub(/\s/, '').match(
      /(?:\A|\/\/|@|(?:git|ssh|https?|hg|svn|scm):)(?:(?:www|ssh|raw|git|wiki)\.)?(#{HOST_PATTERN})(?=[:\/]|\z)/i
    )&.[](1)&.downcase
  end
end
