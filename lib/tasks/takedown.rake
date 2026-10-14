namespace :takedown do
  desc "Hide a maintainer and remove their package associations. LOGIN=username REGISTRY=registry"
  task hide_user: :environment do
    login = ENV['LOGIN']
    registry_name = ENV['REGISTRY']
    abort "LOGIN is required" if login.blank?
    abort "REGISTRY is required" if registry_name.blank?

    registry = Registry.find_by('lower(name) = ?', registry_name.downcase)
    abort "Registry #{registry_name} not found" if registry.nil?

    maintainers = registry.maintainers.matching_identity(login).to_a
    maintainers << registry.maintainers.create!(uuid: login, login: login) if maintainers.empty?
    package_count = maintainers.sum { |maintainer| maintainer.maintainerships.count }

    maintainers.each(&:hide!)

    puts "[packages] hidden #{maintainers.length} maintainer record(s) for #{registry.name}/#{login}"
    puts "[packages] removed #{package_count} package association(s) for #{registry.name}/#{login}"
  end

  desc "Report what exists for a maintainer. LOGIN=username REGISTRY=registry"
  task report: :environment do
    login = ENV['LOGIN']
    registry_name = ENV['REGISTRY']
    abort "LOGIN is required" if login.blank?
    abort "REGISTRY is required" if registry_name.blank?

    registry = Registry.find_by('lower(name) = ?', registry_name.downcase)
    abort "Registry #{registry_name} not found" if registry.nil?

    maintainers = registry.maintainers.matching_identity(login)
    hidden_count = maintainers.hidden.count
    visible_count = maintainers.visible.count
    package_count = Maintainership.where(maintainer: maintainers).count
    puts "[packages] #{registry.name}/#{login}: hidden=#{hidden_count} visible=#{visible_count} packages=#{package_count}"
  end
end
