namespace :ecosystems do
  task :update_shared_assets do
    shared_asset_repo = "https://github.com/ecosyste-ms/advisories"
    branch = "main"
    temp_dir = "tmp/ecosystems_assets"

    # Ensure temp directory is clean
    `rm -rf #{temp_dir}`
    `mkdir -p #{temp_dir}`

    # Clone the repo with only the required branch
    `git clone --depth=1 --branch #{branch} #{shared_asset_repo} #{temp_dir}`

    # Ensure target directories exist
    `mkdir -p app/views/shared`
    `mkdir -p app/assets/stylesheets`
    `mkdir -p app/helpers`
    `mkdir -p app/assets/images`
    `mkdir -p public`

    # Copy required files
    `cp #{temp_dir}/app/views/shared/_header.html.erb app/views/shared/` 
    `cp #{temp_dir}/app/views/shared/_footer.html.erb app/views/shared/`
    `cp #{temp_dir}/app/views/shared/_menu.html.erb app/views/shared/`
    `cp #{temp_dir}/app/assets/stylesheets/ecosystems.scss app/assets/stylesheets/`
    `cp #{temp_dir}/app/helpers/ecosystems_helper.rb app/helpers/`
    `cp -r #{temp_dir}/app/assets/images/. app/assets/images/`
    `cp -r #{temp_dir}/public/. public/`

    # Cleanup
    `rm -rf #{temp_dir}`

    puts "Shared assets updated successfully."
  end
end
