xml.instruct! :xml, version: '1.0', encoding: 'UTF-8'
xml.feed xmlns: 'http://www.w3.org/2005/Atom' do
  xml.title "#{@registry.name} packages"
  xml.id registry_packages_url(@registry)
  xml.link href: registry_packages_url(@registry)
  xml.link href: registry_packages_url(@registry, format: :atom), rel: 'self', type: 'application/atom+xml'
  xml.updated((@packages.first&.updated_at || Time.current).iso8601)
  @packages.each do |package|
    xml.entry do
      xml.title package.name
      xml.id registry_package_url(@registry, package)
      xml.link href: registry_package_url(@registry, package)
      xml.updated((package.updated_at || Time.current).iso8601)
      xml.summary package.description if package.description.present?
    end
  end
end
