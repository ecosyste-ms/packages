class ApplicationController < ActionController::Base
  include Pagy::Backend

  rescue_from Package::UnsupportedSortDirection do |error|
    respond_to do |format|
      format.json { render json: { error: error.message }, status: :unprocessable_content }
      format.any { render plain: error.message, status: :unprocessable_content }
    end
  end

  skip_before_action :verify_authenticity_token
  before_action :reject_path_traversal_in_params
  before_action :set_cache_headers

  after_action lambda {
    request.session_options[:skip] = true
  }

  def set_cache_headers(browser_ttl: 5.minutes, cdn_ttl: 6.hours)
    return unless request.get?
    response.cache_control.merge!(
      public: true,
      max_age: browser_ttl.to_i,
      stale_while_revalidate: cdn_ttl.to_i,
      stale_if_error: 1.day.to_i
    )
    response.cache_control[:extras] = ["s-maxage=#{cdn_ttl.to_i}"]
  end

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

  # Several routes accept ids matching /.*/ because package names, version
  # numbers, keywords etc. can legitimately contain slashes and dots. A value
  # whose /-delimited segments include "." or ".." produces a URL that CDNs
  # normalise into a different path (e.g. "/keywords/../.." collapses to "/"),
  # so a 200 response here would be cached against the wrong page. Refuse to
  # serve any request where a path parameter contains such a segment.
  def reject_path_traversal_in_params
    request.path_parameters.each do |key, value|
      next if key == :controller || key == :action || key == :format
      next unless value.is_a?(String)
      raise ActiveRecord::RecordNotFound if value.match?(Package::PATH_TRAVERSAL_SEGMENT)
    end
  end

  def find_package_with_normalization!(registry, name)
    package = registry.packages.find_by_name(name)
    return package if package

    if registry.ecosystem == 'pypi'
      registry.packages.find_by_normalized_name!(name)
    elsif registry.ecosystem == 'docker' && !name.include?('/')
      registry.packages.find_by_name!("library/#{name}")
    else
      registry.packages.find_by_name!(name.downcase)
    end
  end

  def normalize_url(url)
    return nil if url.nil?
    url.to_s.downcase.sub(/\/+$/, '')
  end

  def sanitize_sort(allowed_columns, default: 'updated_at')
    sort_param = params[:sort].presence || default
    sql = allowed_columns[sort_param] || allowed_columns[default] || default
    Arel.sql(sql)
  end

  def package_sort_order(default: 'updated_at')
    Package.sort_order(sort: params[:sort], order: params[:order], default: default)
  end
end
