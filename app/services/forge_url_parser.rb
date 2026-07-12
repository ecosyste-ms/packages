class ForgeUrlParser < UrlParser
  HOSTS = %w[codeberg.org gitea.com].freeze

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
    url.gsub!(/(codeberg\.org|gitea\.com)+?(:|\/)?/i, '')
  end

  def matched_host
    @matched_host ||= HOSTS.find do |host|
      url.match?(/(?:\A|[^a-z0-9.-])#{Regexp.escape(host)}(?=[:\/]|\z)/i)
    end
  end
end
