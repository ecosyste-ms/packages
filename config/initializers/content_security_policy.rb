SecureHeaders::Configuration.default do |config|
  config.csp = {
    default_src: %w('self'),
    script_src: %w('self' 'unsafe-inline' https://cdnjs.cloudflare.com https://unpkg.com https://static.cloudflareinsights.com),
    style_src: %w('self' 'unsafe-inline' https://fonts.googleapis.com https://unpkg.com),
    font_src: %w('self' https://fonts.gstatic.com),
    img_src: %w('self' data: https:),
    connect_src: %w('self' *.ecosyste.ms)
  }
end
