require 'digest'
require 'net/http'
require 'openssl'
require 'uri'

class CorpusUpload
  def initialize(endpoint:, bucket:, region:, access_key:, secret_key:, session_token: nil)
    @endpoint = URI(endpoint)
    unless @endpoint.is_a?(URI::HTTPS) && @endpoint.host && [nil, '', '/'].include?(@endpoint.path) && !@endpoint.query && !@endpoint.fragment && !@endpoint.userinfo
      raise ArgumentError, 'Endpoint must be an HTTPS origin'
    end
    raise ArgumentError, 'Invalid bucket' unless bucket.match?(/\A[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]\z/)
    raise ArgumentError, 'Missing region or credentials' if [region, access_key, secret_key].any? { |v| v.to_s.empty? }
    @bucket, @region, @access_key, @secret_key, @session_token = bucket, region, access_key, secret_key, session_token
  end

  def upload(path, key:)
    raise ArgumentError, 'Missing object key' if key.empty?
    raise ArgumentError, 'Archive exceeds single-request upload limit' if File.size(path) > 5_000_000_000
    uri = @endpoint.dup
    uri.path = '/' + encode(@bucket) + '/' + encode(key)
    sha = Digest::SHA256.file(path).hexdigest
    request = Net::HTTP::Put.new(uri)
    headers(uri, sha, Time.now.utc).each { |name, value| request[name] = value }
    request['Content-Type'] = 'application/gzip'
    request.content_length = File.size(path)
    File.open(path, 'rb') do |file|
      request.body_stream = file
      Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 120, write_timeout: 120, max_retries: 0) do |http|
        http.request(request) do |response|
          raise "Upload failed (HTTP #{response.code}); local archive retained" unless response.is_a?(Net::HTTPSuccess)
          response.read_body { |_chunk| }
        end
      end
    end
    {bucket: @bucket, key: key, sha256: sha}
  end

  def encode(value)
    value.b.gsub(/[^A-Za-z0-9\-._~\/]/) { |char| '%%%02X' % char.ord }
  end

  def headers(uri, sha, time, extra = {})
    date = time.strftime('%Y%m%d')
    stamp = time.strftime('%Y%m%dT%H%M%SZ')
    headers = extra.merge('host' => uri.host + (uri.port == 443 ? '' : ":#{uri.port}"), 'x-amz-content-sha256' => sha, 'x-amz-date' => stamp)
    headers['x-amz-security-token'] = @session_token if @session_token && !@session_token.empty?
    signed = headers.keys.sort.join(';')
    canonical = ['PUT', uri.path, '', headers.sort.map { |k, v| "#{k}:#{v.strip}\n" }.join, signed, sha].join("\n")
    scope = "#{date}/#{@region}/s3/aws4_request"
    signing_key = [date, @region, 's3', 'aws4_request'].reduce('AWS4' + @secret_key) { |key, value| OpenSSL::HMAC.digest('SHA256', key, value) }
    signature = OpenSSL::HMAC.hexdigest('SHA256', signing_key, ['AWS4-HMAC-SHA256', stamp, scope, Digest::SHA256.hexdigest(canonical)].join("\n"))
    headers.merge('Authorization' => "AWS4-HMAC-SHA256 Credential=#{@access_key}/#{scope}, SignedHeaders=#{signed}, Signature=#{signature}")
  end
end
