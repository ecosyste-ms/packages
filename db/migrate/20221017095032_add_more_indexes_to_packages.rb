class AddMoreIndexesToPackages < ActiveRecord::Migration[7.0]
  def change
    add_index :packages, "((rankings->>'average')::text::float)", name: "index_packages_on_rankings_average"
    add_index :packages, "registry_id, ((repo_metadata ->> 'stargazers_count')::text::integer)", name: "index_packages_on_stargazers_count"
    add_index :packages, "registry_id, ((repo_metadata ->> 'forks_count')::text::integer)", name: "index_packages_on_forks_count"
  end
end
