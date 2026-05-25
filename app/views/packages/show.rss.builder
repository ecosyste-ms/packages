xml.instruct! :xml, version: '1.0', encoding: 'UTF-8'
xml.rss version: '2.0' do
  xml.channel do
    xml.title "#{@package.name} versions"
    xml.description "Latest versions for #{@package.name}"
    xml.link registry_package_url(@registry, @package)
    xml.language 'en'
    @versions.each do |version|
      xml.item do
        xml.title version.number
        xml.link registry_package_version_url(@registry, @package, version)
        xml.guid registry_package_version_url(@registry, @package, version), isPermaLink: true
        xml.pubDate((version.published_at || version.created_at).rfc2822) if (version.published_at || version.created_at)
      end
    end
  end
end
