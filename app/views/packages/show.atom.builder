xml.instruct! :xml, version: '1.0', encoding: 'UTF-8'
xml.feed xmlns: 'http://www.w3.org/2005/Atom' do
  xml.title "#{@package.name} versions"
  xml.id registry_package_url(@registry, @package)
  xml.link href: registry_package_url(@registry, @package)
  xml.link href: registry_package_url(@registry, @package, format: :atom), rel: 'self', type: 'application/atom+xml'
  xml.updated((@versions.first&.published_at || @versions.first&.created_at || Time.current).iso8601)
  @versions.each do |version|
    xml.entry do
      xml.title version.number
      xml.id registry_package_version_url(@registry, @package, version)
      xml.link href: registry_package_version_url(@registry, @package, version)
      xml.updated((version.published_at || version.created_at || Time.current).iso8601)
    end
  end
end
