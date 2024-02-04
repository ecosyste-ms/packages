SitemapGenerator::Sitemap.default_host = "https://packages.ecosyste.ms"
SitemapGenerator::Sitemap.sitemaps_path = 'sitemap/'
SitemapGenerator::Sitemap.create do
  add root_path, priority: 1, changefreq: 'daily'

  Registry.all.each do |registry|
    add registry_packages_path(registry), lastmod: registry.updated_at
    if registry.maintainers_count > 0
      add registry_maintainers_path(registry), lastmod: registry.updated_at

      registry.maintainers.order('packages_count DESC').limit(100).each do |maintainer|
        next if maintainer.to_param.blank?
        add registry_maintainer_path(registry, maintainer), lastmod: maintainer.updated_at
      end
    end
    if registry.namespaces_count > 0
      add registry_namespaces_path(registry), lastmod: registry.updated_at
      registry.packages.where.not(namespace: nil).group(:namespace).order('COUNT(id) desc').count.to_a.first(100).each do |namespace, _count|
        add registry_namespace_path(registry, namespace), lastmod: registry.updated_at
      end
    end
  end

  Package.includes(:registry).active.top(1).limit(10_000).includes(:maintainers).each_instance do |package|
    add registry_package_path(package.registry.name, package.name), lastmod: package.updated_at
    if package.dependent_packages_count > 0
      add dependent_packages_registry_package_path(package.registry.name, package.name), lastmod: package.updated_at
    end
    if package.maintainers_count > 0
      add maintainers_registry_package_path(package.registry.name, package.name), lastmod: package.updated_at
    end
    if package.related_packages.count > 0 
      add related_packages_registry_package_path(package.registry.name, package.name), lastmod: package.updated_at
    end
  end
end