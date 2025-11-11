json.array! @maintainers do |maintainer|
  json.login maintainer[:login]
  json.url maintainer[:url]
  json.packages_count maintainer[:packages_count]
  json.packages maintainer[:packages] do |package|
    json.name package[:name]
    json.ecosystem package[:ecosystem]
    json.downloads package[:downloads]
    json.registry_name package[:registry_name]
  end
end
