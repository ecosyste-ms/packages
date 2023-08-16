module Ecosystem
  class Deno < Base
    def registry_url(package, version = nil)
      "https://deno.land/x/#{package.name}"  + (version ? "@#{version}" : "")
    end

    def documentation_url(package, version = nil)
      if version
        "https://doc.deno.land/https://deno.land/x/#{package.name}@#{version}/mod.ts"
      else 
        "https://doc.deno.land/https://deno.land/x/#{package.name}/mod.ts"
      end
    end

    def check_status(package)
      url = check_status_url(package)
      response = Typhoeus.head(url)
      "removed" if [400, 404, 410].include?(response.response_code)
    end

    def all_package_names
      page = 1
      packages = []
      loop do
        r = get("https://apiland.deno.dev/v2/modules?page=#{page}&limit=100")['items']
        break if r == []

        packages += r
        page += 1
      end
      packages.map { |package| package["name"] }.uniq
    rescue
      []
    end

    def recently_updated_package_names
      json = get("https://apiland.deno.dev/v2/modules")
      names = json['items'].map { |p| p["name"] }
      names.uniq
    rescue
      []
    end

    def fetch_package_metadata(name)
      meta = get("https://apiland.deno.dev/v2/modules/#{name}")
      versions = meta['versions']
      latest_version_number = meta['latest_version']
      latest_version = get("https://cdn.deno.land/#{name}/versions/#{CGI.escape(latest_version_number)}/meta/meta.json")
      {
        name: name,
        description: meta['description'],
        repository_url: 'https://github.com/'+latest_version['upload_options']['repository'],
        keywords: meta['tags'],
        versions: versions
      }
    rescue
      nil
    end

    def map_package_metadata(package)
      package
    end

    def versions_metadata(pkg_metadata, existing_version_numbers = [])
      pkg_metadata[:versions].reject{|v| existing_version_numbers.include?(v)}.map do |version|
        begin
          ver = get("https://cdn.deno.land/#{pkg_metadata[:name]}/versions/#{CGI.escape(version)}/meta/meta.json")
          {
            number: version,
            published_at: ver['uploaded_at'],
          }
        rescue
          nil
        end
      end.compact
    end

    def dependencies_metadata(name, version, _mapped_package)
      nodes = get("https://cdn.deno.land/#{name}/versions/#{CGI.escape(version)}/meta/deps_v2.json").fetch("graph", {}).fetch("nodes", {})
      deps = nodes.select{|k,v| k.split('/')[4] == "#{name}@#{version}"}
                  .map{|k,v| v['deps']}.flatten.uniq
                  .map{|k| k.split('/')[4]}.uniq
                  .select{|k| k.include?('@')}
                  .map{|k| k.split('@')}

      deps.map do |name, requirement|
          {
            package_name: name,
            requirements: requirement,
            kind: "runtime",
            ecosystem: self.class.name.demodulize.downcase,
          }
        end
    end
  end
end
