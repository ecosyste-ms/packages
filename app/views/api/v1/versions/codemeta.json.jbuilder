json.set! '@context', 'https://w3id.org/codemeta/3.0'
json.set! '@type', 'SoftwareSourceCode'

json.identifier @version.purl
json.name @package.name
json.description @package.description_with_fallback if @package.description_with_fallback.present?

json.version @version.number
json.softwareVersion @version.number

if @version.licenses.present?
  normalized_licenses = @version.licenses.is_a?(String) ? [@version.licenses] : @version.licenses
  if normalized_licenses.length == 1
    json.license "https://spdx.org/licenses/#{normalized_licenses.first}"
  else
    json.license normalized_licenses.map { |l| "https://spdx.org/licenses/#{l}" }
  end
elsif @package.normalized_licenses.present? && @package.normalized_licenses.any?
  if @package.normalized_licenses.length == 1
    json.license "https://spdx.org/licenses/#{@package.normalized_licenses.first}"
  else
    json.license @package.normalized_licenses.map { |l| "https://spdx.org/licenses/#{l}" }
  end
end

json.codeRepository @package.repository_url if @package.repository_url.present?

if @package.repo_metadata.present? && @package.repo_metadata['html_url'].present?
  issues_url = "#{@package.repo_metadata['html_url']}/issues"
  json.issueTracker issues_url
end

json.url @package.homepage if @package.homepage.present?

if @package.keywords_array.present? && @package.keywords_array.any?
  json.keywords @package.keywords_array.reject(&:blank?)
end

if @package.language.present?
  json.programmingLanguage do
    json.set! '@type', 'ComputerLanguage'
    json.name @package.language
  end
end

maintainers = @package.maintainerships.select { |m| m.maintainer.present? }.map(&:maintainer)
if maintainers.any?
  json.maintainer maintainers do |maintainer|
    json.set! '@type', 'Person'
    json.name maintainer.login
    json.url maintainer.url if maintainer.url.present?
  end

  json.author maintainers do |maintainer|
    json.set! '@type', 'Person'
    json.name maintainer.login
    json.url maintainer.url if maintainer.url.present?
  end

  json.copyrightHolder maintainers do |maintainer|
    json.set! '@type', 'Person'
    json.name maintainer.login
    json.url maintainer.url if maintainer.url.present?
  end
end

json.dateCreated @version.published_at.to_date.iso8601 if @version.published_at.present?
json.dateModified @version.updated_at.to_date.iso8601 if @version.updated_at.present?
json.datePublished @version.published_at.to_date.iso8601 if @version.published_at.present?

if @version.published_at.present?
  json.copyrightYear @version.published_at.year
end

if @version.download_url.present?
  json.downloadUrl @version.download_url
end

if @version.documentation_url.present?
  json.softwareHelp do
    json.set! '@type', 'WebSite'
    json.url @version.documentation_url
  end
end

if @package.ecosystem.present?
  json.applicationCategory @package.ecosystem
  json.runtimePlatform @package.ecosystem
end

if @version.status.present?
  json.developmentStatus @version.status
elsif @package.status.present?
  json.developmentStatus @package.status
elsif @package.repo_metadata.present? && @package.repo_metadata['default_branch'].present?
  json.developmentStatus 'active'
end

if @version.registry_url.present?
  same_as_urls = [@version.registry_url]
  json.sameAs same_as_urls
end

if @package.funding_links.any?
  json.funder @package.funding_links do |funding_url|
    json.set! '@type', 'Organization'
    json.url funding_url
  end
end

if @package.stars.present? && @package.stars > 0
  json.set! 'https://www.w3.org/ns/activitystreams#likes', @package.stars
end

if @package.forks.present? && @package.forks > 0
  json.set! 'https://forgefed.org/ns#forks', @package.forks
end
