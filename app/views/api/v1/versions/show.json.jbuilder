json.partial! 'api/v1/versions/version', version: @version
json.package_url api_v1_registry_package_url(@registry, @package)