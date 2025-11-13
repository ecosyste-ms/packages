class AddStargazersIndex < ActiveRecord::Migration[8.1]
  def change
    add_index :packages,
              "(((repo_metadata ->> 'stargazers_count')::text::integer)) DESC NULLS LAST",
              name: "index_packages_on_stargazers_desc",
              where: "length(repo_metadata::text) > 2"
  end
end
