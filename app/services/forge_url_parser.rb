class ForgeUrlParser < UrlParser
  Host = Data.define(:hostname, :port, :path_prefix) do
    def authority
      port ? "#{hostname}:#{port}" : hostname
    end

    def base_url
      path = path_prefix.any? ? "/#{path_prefix.join('/')}" : ''
      "https://#{authority}#{path}"
    end
  end

  DEFAULT_HOSTS = %w[https://codeberg.org https://gitea.com].freeze

  def self.hosts
    configured_hosts_value = ENV.fetch('FORGE_HOSTS', '')
    return @hosts if defined?(@hosts) && @configured_hosts == configured_hosts_value

    @configured_hosts = configured_hosts_value
    @hosts = (DEFAULT_HOSTS + configured_hosts(configured_hosts_value))
      .filter_map { |url| build_host(url) }
      .uniq(&:base_url)
  end

  def self.configured_hosts(hosts)
    hosts.split(',').map(&:strip)
  end

  def self.build_host(url)
    uri = URI.parse(url)
    return unless uri.is_a?(URI::HTTPS) && uri.host.present? && uri.userinfo.nil? && uri.query.nil? && uri.fragment.nil?

    Host.new(
      hostname: uri.host.downcase,
      port: uri.port == uri.default_port ? nil : uri.port,
      path_prefix: uri.path.split('/').reject(&:blank?)
    )
  rescue URI::InvalidURIError
    nil
  end

  private

  def full_domain
    host_config.base_url
  end

  def parseable?
    host_config.present?
  end

  def includes_domain?
    host_config.present?
  end

  def extractable_early?
    false
  end

  def remove_domain
    port = host_config.port ? ":#{host_config.port}" : '(?::443)?'
    url.gsub!(/#{Regexp.escape(host_config.hostname)}#{port}(?::|\/)?/i, '')
  end

  def remove_extra_segments
    segments = url.dup.split('/').reject(&:blank?)
    path_prefix = host_config.path_prefix
    return self.url = [] unless segments.first(path_prefix.length) == path_prefix

    self.url = segments.drop(path_prefix.length).first(2)
  end

  def host_config
    @host_config ||= self.class.hosts.find do |host|
      url.gsub(/\s/, '').match?(authority_pattern(host))
    end
  end

  def authority_pattern(host)
    subdomain = '(?:(?:www|ssh|raw|git|wiki)\\.)?'
    host_name = Regexp.escape(host.hostname)

    if host.port
      /(?:\A|\/\/|@|(?:git|ssh|https?|hg|svn|scm):)#{subdomain}#{host_name}:#{host.port}(?=\/|\z)/i
    else
      /(?:(?:\A|@|(?:git|ssh|https?|hg|svn|scm):)#{subdomain}#{host_name}(?=[:\/]|\z)|\/\/#{subdomain}#{host_name}(?::443)?(?=\/|\z))/i
    end
  end
end
