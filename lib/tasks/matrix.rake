require 'matrix'
require 'csv'

namespace :matrix do
  task correlations: :environment do
    csv_path = Rails.root.join('data/matrix.csv')

    puts "Processing: #{csv_path}"

    headers = ['Ecosystem', 'Downloads', 'dependent_repos_count', 'stargazers_count', 'forks_count', 'dependent_packages_count', 'docker_downloads_count', 'docker_dependents_count']

    col_ecosystem = headers.find_index('Ecosystem')
    numeric_headers = headers[1..] # All except 'Ecosystem'
    numeric_indices = numeric_headers.map { |h| headers.find_index(h) }

    ecosystems = Hash.new { |hash, key| hash[key] = Hash.new { |h, k| h[k] = [] } }
    combined_data = Hash.new { |h, k| h[k] = [] }

    count = 0
    download_threshold = 1 # Keep filtering minimal

    CSV.foreach(csv_path, headers: true) do |row|
      downloads = row[headers.find_index('Downloads')].to_i
      next if downloads < download_threshold # Exclude low-download rows

      ecosystem = row[col_ecosystem]

      numeric_headers.each do |col|
        value = row[headers.find_index(col)].to_i
        ecosystems[ecosystem][col] << value
        combined_data[col] << value
      end

      count += 1
      puts "Processed #{count} rows..." if (count % 100000).zero?
    end

    def compute_correlation(data, headers)
      correlations = {}

      headers.combination(2).each do |col1, col2|
        x_values = data[col1]
        y_values = data[col2]

        next if x_values.size < 2 || y_values.size < 2 # Avoid computing for small datasets

        mean_x = x_values.sum.to_f / x_values.size
        mean_y = y_values.sum.to_f / y_values.size

        covariance = x_values.zip(y_values).sum { |x, y| (x - mean_x) * (y - mean_y) }.to_f / x_values.size
        std_x = Math.sqrt(x_values.sum { |x| (x - mean_x) ** 2 }.to_f / x_values.size)
        std_y = Math.sqrt(y_values.sum { |y| (y - mean_y) ** 2 }.to_f / y_values.size)

        correlation = (std_x > 0 && std_y > 0) ? (covariance / (std_x * std_y)) : nil
        correlations[[col1, col2]] = correlation
      end

      correlations
    end

    # Compute overall correlations
    combined_correlations = compute_correlation(combined_data, numeric_headers)

    # Compute per-ecosystem correlations
    ecosystem_correlations = {}
    ecosystems.each do |ecosystem, data|
      ecosystem_correlations[ecosystem] = compute_correlation(data, numeric_headers)
    end

    # Output results
    puts "\n🔹 Overall Pairwise Correlation Results:"
    combined_correlations.each do |(col1, col2), correlation|
      puts "#{col1} ↔ #{col2}: #{correlation.nil? ? 'No correlation' : correlation.round(4)}"
    end

    puts "\n🔹 Per-Ecosystem Correlations:"
    ecosystem_correlations.each do |ecosystem, correlations|
      puts "\n🌍 Ecosystem: #{ecosystem}"
      correlations.each do |(col1, col2), correlation|
        puts "  #{col1} ↔ #{col2}: #{correlation.nil? ? 'No correlation' : correlation.round(4)}"
      end
    end
  end
end