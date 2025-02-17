namespace :ecosystems do
  task :update_shared_assets do
    shared_asset_repo = "https://github.com/ecosyste-ms/advisories"
    branch = "main"
    temp_dir = "tmp/ecosystems_assets"
    ecosystems_rake_path = "lib/tasks/ecosystems.rake"
    temp_rake_file = "#{temp_dir}/lib/tasks/ecosystems.rake"

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

    # Check if ecosystems.rake has changed
    if !FileUtils.compare_file(temp_rake_file, ecosystems_rake_path)
      puts "ecosystems.rake has changed, restarting task with new code..."
      `cp #{temp_rake_file} #{ecosystems_rake_path}`

      # Cleanup
      `rm -rf #{temp_dir}`

      # Re-execute the current Rake task using exec to replace the running process
      exec("rake ecosystems:update_shared_assets")
    end

    # Copy required files
    `cp #{temp_rake_file} #{ecosystems_rake_path}`
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