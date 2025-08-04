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
      registry_ids = Registry.where(ecosystem: ecosystem).pluck(:id)
      Package.where(name: name, registry_id: registry_ids)
    end
  rescue
    Package.none
  end
end
