json.array! @maintainers do |maintainer|
  json.login maintainer[:login]
  json.name maintainer[:name]
  json.registry_name maintainer[:registry].name
  json.packages_count maintainer[:packages_count]
  json.packages maintainer[:packages], partial: 'api/v1/packages/package', as: :package
end
