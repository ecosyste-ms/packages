namespace :funding do
  desc "funding of critical packages"
  task critical: :environment do
    
    total_critical_packages = 0
    total_critical_packages_with_funding_links = 0
    total_critical_packages_with_open_collective = 0
    total_critical_packages_with_github_sponsors = 0

    open_collective_packages = []
    get_github_sponors_usernames = []

    Package.critical.find_each do |package|

      total_critical_packages += 1


      if package.funding_links.present?
        # total_critical_packages_with_funding_links += 1
        # if package.funding_links.any?{|link| link.include?('opencollective.com') }
        #   total_critical_packages_with_open_collective += 1

        #   oc_data = fetch_opencollective_data(package)

        #   if oc_data.present?
        #     open_collective_packages << [package.ecosystem, package.name, oc_data[:slug], oc_data[:total_donations], oc_data[:total_expenses], oc_data[:current_balance]]
        #   end

        # end
        if package.funding_links.any?{|link| link.include?('github.com/sponsors') }
          total_critical_packages_with_github_sponsors += 1
          gh_username = get_github_sponors_username(package)
          get_github_sponors_usernames << gh_username
        end
      end

    end

    oc_csv = CSV.generate do |csv|
      csv << ['Ecosystem', 'name', 'OC Slug', 'Donations', 'Expenses', 'Current Balance']
      open_collective_packages.each do |package|
        # puts "#{package[0]}/#{package[1]}: #{package[2]} - Donations: #{package[3]} - Expenses: #{package[4]} - Balance: #{package[5]}"
        csv << [package[0], package[1], package[2], package[3].round(2), package[4].round(2), package[5].round(2)]
      end
    end
    puts oc_csv

    second_csv = CSV.generate do |csv|
      csv << ['oc slug', 'total donations', 'total expenses', 'current balance']
      @oc_cache.each do |slug, data|
        csv << [slug, data[:total_donations].round(2), data[:total_expenses].round(2), data[:current_balance].round(2)]
      end
    end

    puts second_csv
  end
end

def get_github_sponors_username(package)
  gh_funding_link = package.funding_links.find{|link| link.include?('github.com/sponsors') }
  return if gh_funding_link.blank?
      
  gh_funding_link.split('/').last.downcase
end 
  

@oc_cache = {}

def fetch_opencollective_data(package)
  oc_funding_link = package.funding_links.find{|link| link.include?('opencollective.com') }
  return if oc_funding_link.blank?
  
  oc_slug = oc_funding_link.split('/').last
  
  if @oc_cache[oc_slug].present?
    return @oc_cache[oc_slug]
  else

    oc_data = fetch_opencollective_data_from_api(oc_slug)

    if oc_data.present?
      @oc_cache[oc_slug] = oc_data
      return oc_data
    else
      return nil
    end
  end

end

def fetch_opencollective_data_from_api(oc_slug)
  puts "Fetching data for Open Collective: #{oc_slug}"

  url = "https://opencollective.ecosyste.ms/api/v1/collectives/#{oc_slug}"

  response = Faraday.get(url)

  if response.status == 200
    data = JSON.parse(response.body, symbolize_names: true)
    return data
  else
    return nil
  end
end

# @sponors = File.read('lib/tasks/sponsors.json')
# sponsors = JSON.parse(@sponors)

# csv = CSV.generate do |csv|
#   csv << ['username', 'total_sponsors', 'current_sponsors', 'past_sponsors']
#   gh_usernames.each do |username|
#     gh = sponsors.find{|s| s['username'] == username }
#     if gh.present?
#       gh['total_sponsors'] = (gh['current_sponsors'].to_i ||0) + (gh['past_sponsors'].to_i || 0)
#       csv << [gh['username'], gh['total_sponsors'],( gh['current_sponsors'].to_i || 0), (gh['past_sponsors'].to_i || 0 )]
#     end

#   end
# end 
