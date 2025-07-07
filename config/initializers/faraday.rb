require 'faraday/typhoeus'
Faraday.default_adapter = :typhoeus

# Set default User-Agent for all Faraday connections
Faraday.default_connection_options = {
  headers: {
    'User-Agent' => 'packages.ecosyste.ms'
  }
}
