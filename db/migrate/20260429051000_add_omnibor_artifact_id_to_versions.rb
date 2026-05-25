class AddOmniborArtifactIdToVersions < ActiveRecord::Migration[7.0]
  def change
    add_column :versions, :omnibor_artifact_id, :string
    add_index :versions, :omnibor_artifact_id, unique: true, where: "omnibor_artifact_id IS NOT NULL"
  end
end
