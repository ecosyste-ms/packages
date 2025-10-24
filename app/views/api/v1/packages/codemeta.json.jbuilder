json.set! '@context', 'https://w3id.org/codemeta/3.0'
json.set! '@type', 'SoftwareSourceCode'

json.identifier @package.purl
json.name @package.name
json.description @package.description_with_fallback if @package.description_with_fallback.present?

json.version @package.latest_release_number if @package.latest_release_number.present?
json.softwareVersion @package.latest_release_number if @package.latest_release_number.present?

if @package.normalized_licenses.present? && @package.normalized_licenses.any?
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

json.dateCreated @package.first_release_published_at.iso8601 if @package.first_release_published_at.present?
json.dateModified @package.latest_release_published_at.iso8601 if @package.latest_release_published_at.present?
json.datePublished @package.latest_release_published_at.iso8601 if @package.latest_release_published_at.present?

if @package.first_release_published_at.present?
  json.copyrightYear @package.first_release_published_at.year
end

if @package.download_url.present?
  json.downloadUrl @package.download_url
end

if @package.documentation_url.present?
  json.softwareHelp do
    json.set! '@type', 'WebSite'
    json.url @package.documentation_url
  end
end

if @package.ecosystem.present?
  json.applicationCategory @package.ecosystem
  json.runtimePlatform @package.ecosystem
end

if @package.status.present?
  json.developmentStatus @package.status
elsif @package.repo_metadata.present? && @package.repo_metadata['default_branch'].present?
  json.developmentStatus 'active'
end

# Alternative identifiers - only include if we have registry_url
if @package.registry_url.present?
  same_as_urls = [@package.registry_url]
  json.sameAs same_as_urls
end

# Funding information (SWH supports schema.org/funder)
if @package.funding_links.any?
  json.funder @package.funding_links do |funding_url|
    json.set! '@type', 'Organization'
    json.url funding_url
  end
end

# Repository statistics using ActivityStreams and ForgeFed vocabularies (SWH supported)
if @package.stars.present? && @package.stars > 0
  json.set! 'https://www.w3.org/ns/activitystreams#likes', @package.stars
end

if @package.forks.present? && @package.forks > 0
  json.set! 'https://forgefed.org/ns#forks', @package.forks
end
