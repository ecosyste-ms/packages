class UrlParser
  def self.parse(url)
    new(url).parse
  end

  def initialize(url)
    @url = url.to_s.dup
  end

  def parse
    return nil unless parseable?

    if url = extractable_early?
      url
    else
      clean_url
      format_url
    end
  end

  def self.parse_to_full_url(url)
    new(url).parse_to_full_url
  end

  def self.try_all(url)
    GithubUrlParser.parse_to_full_url(url) ||
    GitlabUrlParser.parse_to_full_url(url) ||
    BitbucketUrlParser.parse_to_full_url(url)
  end

  def parse_to_full_url
    path = parse
    return nil unless path.present?
    [full_domain, path].join('/')
  end

  private

  attr_accessor :url

  def clean_url
    remove_whitespace
    remove_brackets
    remove_anchors
    remove_querystring
    remove_auth_user
    remove_equals_sign
    remove_scheme
    return nil unless includes_domain?
    remove_subdomain
    remove_domain
    remove_git_extension
    remove_git_scheme
    remove_extra_segments
  end

  def format_url
    return nil unless url.length == 2
    url.join('/')
  end

  def parseable?
    !url.nil? && url.include?(domain)
  end

  def tlds
    raise NotImplementedError
  end

  def domain
    raise NotImplementedError
  end

  def includes_domain?
    raise NotImplementedError
  end

  def extractable_early?
    raise NotImplementedError
  end

  def domain_regex
    "#{domain}\.(#{tlds.join('|')})"
  end

  def website_url?
    url.match(/www\.#{domain_regex}/i)
  end

  def includes_domain?
    url.match(/#{domain_regex}/i)
  end

  def extractable_early?
    return false if website_url?

    match = url.match(/([\w\.@\:\-_~]+)\.#{domain_regex}\/([\w\.@\:\-\_\~]+)/i)
    if match && match.length == 4
      return "#{match[1]}/#{match[3]}"
    end

    nil
  end

  def remove_anchors
    self.url = url.dup.gsub(/(#\S*)$/i, '')
  end

  def remove_auth_user
    self.url = url.dup.split('@')[-1]
  end

  def remove_domain
    raise NotImplementedError
  end

  def remove_brackets
    self.url = url.dup.gsub(/>|<|\(|\)|\[|\]/, '')
  end

  def remove_equals_sign
    self.url = url.dup.split('=')[-1]
  end

  def remove_extra_segments
    self.url = url.dup.split('/').reject(&:blank?)[0..1]
  end

  def remove_git_extension
    self.url = url.dup.gsub(/(\.git|\/)$/i, '')
  end

  def remove_git_scheme
    self.url = url.dup.gsub(/git\/\//i, '')
  end

  def remove_querystring
    self.url = url.dup.gsub(/(\?\S*)$/i, '')
  end

  def remove_scheme
    self.url = url.dup.gsub(/(((git\+https|git|ssh|hg|svn|scm|http|https)+?:)+?)/i, '')
  end

  def remove_subdomain
    self.url = url.dup.gsub(/(www|ssh|raw|git|wiki)+?\./i, '')
  end

  def remove_whitespace
    self.url = url.dup.gsub(/\s/, '')
  end
end