json.extract! version, :number, :published_at, :licenses, :integrity, :status, :download_url, :registry_url, :documentation_url, :install_command

json.dependencies version.dependencies, partial: 'api/v1/dependencies/dependency', as: :dependency