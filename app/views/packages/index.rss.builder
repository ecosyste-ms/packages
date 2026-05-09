xml.instruct! :xml, version: '1.0', encoding: 'UTF-8'
xml.rss version: '2.0' do
  xml.channel do
    xml.title "#{@registry.name} packages"
    xml.description "Latest packages for #{@registry.name}"
    xml.link registry_packages_url(@registry)
    xml.language 'en'
    @packages.each do |package|
      xml.item do
        xml.title package.name
        xml.description package.description if package.description.present?
        xml.link registry_package_url(@registry, package)
        xml.guid registry_package_url(@registry, package), isPermaLink: true
        xml.pubDate(package.updated_at.rfc2822) if package.updated_at.present?
      end
    end
  end
end
