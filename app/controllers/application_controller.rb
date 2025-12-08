class ApplicationController < ActionController::Base
  include Pagy::Backend

  skip_before_action :verify_authenticity_token

  after_action lambda {
    request.session_options[:skip] = true
  }

  def lookup_by_purl(purl_string)
    purl_param = purl_string.gsub('npm/@', 'npm/%40')
    purl = Purl.parse(purl_param)
    if purl.type == 'docker' && purl.namespace.nil?
      namespace = 'library'
    else
      namespace = purl.namespace
    end
    if purl.type == 'github'
      repository_url = "https://github.com/#{purl.namespace}/#{purl.name}"
      scope = Package.repository_url(repository_url)
    else
      name = [namespace, purl.name].compact.join(Ecosystem::Base.purl_type_to_namespace_separator(purl.type))
      ecosystem = Ecosystem::Base.purl_type_to_ecosystem(purl.type)

      # Filter by repository_url qualifier if provided
      if purl.qualifiers && purl.qualifiers['repository_url'].present?
        # Do URL matching in Ruby to ensure proper normalization
        target_url = normalize_url(purl.qualifiers['repository_url'])
        registries = Registry.where(ecosystem: ecosystem).select { |r| normalize_url(r.url) == target_url }
        registry_ids = registries.map(&:id)
      else
        registry_ids = Registry.where(ecosystem: ecosystem).pluck(:id)
      end

      Package.where(name: name, registry_id: registry_ids)
    end
  rescue
    Package.none
  end

  private

  def normalize_url(url)
    return nil if url.nil?
    url.to_s.downcase.sub(/\/+$/, '')
  end
end
