json.extract! version, :number, :published_at

json.dependencies version.dependencies, partial: 'api/v1/dependencies/dependency', as: :dependency