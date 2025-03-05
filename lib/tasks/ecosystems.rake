namespace :ecosystems do
  task :update_shared_assets do
    shared_asset_repo = "https://github.com/ecosyste-ms/documentation"
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

    # Install required gems
    `bundle add bootstrap-icons-helper`

    # Copy required files
    `cp #{temp_rake_file} #{ecosystems_rake_path}`
    `cp #{temp_dir}/app/views/shared/_footer.html.erb app/views/shared/`
    `cp #{temp_dir}/app/views/layouts/application.html.erb app/views/layouts/`
    `cp #{temp_dir}/app/assets/stylesheets/ecosystems.scss app/assets/stylesheets/`
    `cp #{temp_dir}/app/helpers/ecosystems_helper.rb app/helpers/`
    `cp -r #{temp_dir}/app/assets/images/. app/assets/images/`
    `cp -r #{temp_dir}/public/. public/`

    # Copy _menu.html.erb only if it does not already exist
    menu_file = "app/views/shared/_menu.html.erb"
    unless File.exist?(menu_file)
      `cp #{temp_dir}/app/views/shared/_menu.html.erb #{menu_file}`
    end

    # Copy _header.html.erb only if it does not already exist
    header_file = "app/views/shared/_header.html.erb"
    unless File.exist?(header_file)
      `cp #{temp_dir}/app/views/shared/_header.html.erb #{header_file}`
    end

    # Cleanup
    `rm -rf #{temp_dir}`

    # git add and commit
    `git add lib/tasks/ecosystems.rake app/views/shared/_header.html.erb app/views/shared/_footer.html.erb app/views/shared/_menu.html.erb app/views/layouts/application.html.erb app/assets/stylesheets/ecosystems.scss app/helpers/ecosystems_helper.rb app/assets/images/ public/`
    `git commit -m "Update shared assets from #{shared_asset_repo}"`

    puts "Shared assets updated successfully."
  end

  task :setup_shared_assets, [:target_repo] do |_t, args|
    target_repo_path = "../#{args[:target_repo]}"
    puts "Setting up shared assets for repository at: #{target_repo_path}"

    # Ensure target directory exists
    `mkdir -p #{target_repo_path}/lib/tasks`

    # Copy required files
    `cp lib/tasks/ecosystems.rake #{target_repo_path}/lib/tasks/`

    puts "Shared assets setup completed successfully."

    # add app_name and app_description to the target repo
    puts "Add the following to app/helpers/application_helper.rb in the target repo:"
    puts "module ApplicationHelper"
    puts "  def app_name"
    puts "    \"AppName\""
    puts "  end"
    puts ""
    puts "  def app_description"
    puts "    \"Description of the app.\""
    puts "  end"
    puts "end"
  end
end