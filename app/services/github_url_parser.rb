class GithubUrlParser < UrlParser
  private

  def full_domain
    'https://github.com'
  end

  def tlds
    %w(io com org)
  end

  def domain
    'github'
  end

  def remove_domain
    url.sub!(/(github\.io|github\.com|github\.org|raw\.githubusercontent\.com)(:|\/)?/i, '')
  end
end
