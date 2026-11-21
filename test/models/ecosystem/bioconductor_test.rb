require "test_helper"

class BioconductorTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(default: true, name: 'bioconductor.org', url: 'https://bioconductor.org', ecosystem: 'bioconductor')
    @ecosystem = Ecosystem::Bioconductor.new(@registry)
  end

  test 'repository_url falls back to collected Bug Reports when URL has no forge' do
    properties = {
      "URL" => "https://bioconductor.org/packages/BiocGenerics",
      "Bug Reports" => "https://github.com/Bioconductor/BiocGenerics/issues",
      "License" => "Artistic-2.0",
      "biocViews" => "Infrastructure",
    }
    html = Nokogiri::HTML(<<~HTML)
      <h2>BiocGenerics</h2>
      <h3 id="details">Details</h3>
      <table>
        <tr><td>URL</td><td>https://bioconductor.org/packages/BiocGenerics</td></tr>
        <tr><td>Bug Reports</td><td><a href="https://github.com/Bioconductor/BiocGenerics/issues">https://github.com/Bioconductor/BiocGenerics/issues</a></td></tr>
        <tr><td>License</td><td>Artistic-2.0</td></tr>
        <tr><td>biocViews</td><td>Infrastructure</td></tr>
      </table>
    HTML
    @ecosystem.stubs(:get_html).with("https://www.bioconductor.org/packages/release/bioc/html/BiocGenerics.html").returns(html)
    @ecosystem.stubs(:downloads).returns(nil)
    package = @ecosystem.fetch_package_metadata_uncached('BiocGenerics')

    assert_equal properties, package[:properties]
    mapped = @ecosystem.map_package_metadata(package)

    assert_equal "https://bioconductor.org/packages/BiocGenerics", mapped[:homepage]
    assert_equal "https://github.com/Bioconductor/BiocGenerics", mapped[:repository_url]
    assert_equal properties, mapped[:properties]
  end

  test 'repository_url falls back to BugReports when URL has no forge' do
    properties = {
      "URL" => "https://bioconductor.org/packages/BiocGenerics",
      "BugReports" => "https://github.com/Bioconductor/BiocGenerics/issues",
      "License" => "Artistic-2.0",
      "biocViews" => "Infrastructure",
    }
    html = Nokogiri::HTML("<h2>BiocGenerics</h2>")
    @ecosystem.stubs(:downloads).returns(nil)
    mapped = @ecosystem.map_package_metadata(name: 'BiocGenerics', html: html, properties: properties)

    assert_equal "https://bioconductor.org/packages/BiocGenerics", mapped[:homepage]
    assert_equal "https://github.com/Bioconductor/BiocGenerics", mapped[:repository_url]
  end

  test 'repository_url scans all URL entries' do
    properties = {
      "URL" => "https://example.org/foo,\nhttps://github.com/Bioconductor/limma",
      "License" => "GPL",
      "biocViews" => "Infrastructure",
    }
    html = Nokogiri::HTML("<h2>limma</h2>")
    @ecosystem.stubs(:downloads).returns(nil)
    mapped = @ecosystem.map_package_metadata(name: 'limma', html: html, properties: properties)

    assert_equal "https://example.org/foo", mapped[:homepage]
    assert_equal "https://github.com/Bioconductor/limma", mapped[:repository_url]
  end
end
