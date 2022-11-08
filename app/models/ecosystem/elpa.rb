# frozen_string_literal: true

module Ecosystem
  class Elpa < Base
    def registry_url(package, version = nil)
      "#{@registry_url}/#{package.name}.html"
    end

    def download_url(package, version)
      return nil unless version.present?
      "#{@registry_url}/#{package.name}-#{version}.tar"
    end

    def install_command(package, version = nil)
      "M-x package-install RET #{package.name} RET"
    end

    def all_package_names
      get_html("#{@registry_url}").css('table td a:first').map(&:text)
    rescue
      []
    end

    def recently_updated_package_names
      all_package_names
    end

    def fetch_package_metadata(name)
      page = get_html("#{@registry_url}/#{name}.html", headers: { "Accept" => "text/html" })
      {
        name: name,
        page: page
      }
    end

    def extract_fields(page)
      keys = page.css('dl').first.css('dt').map(&:text)
      values = page.css('dl').first.css('dd').map(&:text)
      Hash[keys.zip(values)] 
    end

    def map_package_metadata(package)
      return nil if package[:page].blank?
      fields = extract_fields(package[:page])
      {
        name: package[:name],
        description: fields["Description"],
        homepage: fields["Home page"],
        repository_url: repo_fallback(fields["Home page"], ''),
        page: package[:page]
      }
    end

    def versions_metadata(package)
      fields = extract_fields(package[:page])
      filename = fields['Latest'].split(',')[0]
      date = fields['Latest'].split(', ')[1]
      version = filename.gsub("#{package[:name]}-",'').gsub('.tar','')
      [{ number: version, published_at: date }]
    end

    def maintainers_metadata(name)
      page = get_html("#{@registry_url}/#{name}.html", headers: { "Accept" => "text/html" })
      fields = extract_fields(page)
      fields['Maintainer'].split(', ').map do |string|
        name, email = string.split(' <')
        email = email.gsub('>','')
        {
          uuid: email,
          name: name,
          email: email
        }
      end
    rescue StandardError
      []
    end
  end
end
