class GitlabUrlParser < UrlParser
  private

  def full_domain
    'https://gitlab.com'
  end

  def tlds
    %w(com)
  end

  def domain
    'gitlab'
  end

  def remove_domain
    url.gsub!(/(gitlab.com)+?(:|\/)?/i, '')
  end

  def remove_extra_segments
    segments = url.dup.split('/').reject(&:blank?)
    repository_segments = trim_repository_suffix(segments)

    self.url = repository_segments
  end

  def format_url
    return nil unless url.is_a?(Array) && url.length >= 2

    url.join('/')
  end

  def trim_repository_suffix(segments)
    gitlab_separator_index = segments.index('-')
    return segments[0...gitlab_separator_index] if gitlab_separator_index

    tags_index = segments.index('tags')
    return segments[0...tags_index] if tags_index

    segments
  end
end
