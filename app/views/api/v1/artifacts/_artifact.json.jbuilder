json.extract! artifact, :id, :identifier, :filename, :kind, :download_url, :size, :published_at, :status, :integrity, :metadata, :created_at, :updated_at
json.artifact_url api_v1_artifact_url(artifact)
json.version_url api_v1_registry_package_version_url(artifact.version.package.registry, artifact.version.package, artifact.version)
