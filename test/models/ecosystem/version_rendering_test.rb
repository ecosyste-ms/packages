require 'test_helper'

class EcosystemVersionRenderingTest < ActiveSupport::TestCase
  CASES = {
    'actions' => { name: 'actions/checkout', install: nil, documentation: nil },
    'adelie' => { name: 'curl', install: 'apk add curl', documentation: nil },
    'alpine' => { name: 'curl', install: 'apk add curl', documentation: nil },
    'bazel' => {
      name: 'abseil-cpp',
      install: ['bazel_dep(name = "abseil-cpp")', 'bazel_dep(name = "abseil-cpp", version = "1.2.3")'],
      documentation: ['https://registry.bazel.build/docs/abseil-cpp', 'https://registry.bazel.build/docs/abseil-cpp/1.2.3']
    },
    'bioconductor' => {
      name: 'Biobase', install: nil,
      documentation: 'https://bioconductor.org/packages/release/bioc/vignettes/Biobase/inst/doc/Biobase.pdf'
    },
    'bower' => { name: 'jquery', install: ['bower install jquery', 'bower install jquery#1.2.3'], documentation: nil },
    'cargo' => {
      name: 'rand', install: ['cargo install rand', 'cargo install rand --version 1.2.3'],
      documentation: ['https://docs.rs/rand/', 'https://docs.rs/rand/1.2.3']
    },
    'carthage' => { name: 'Alamofire/Alamofire', install: nil, documentation: nil },
    'clojars' => {
      name: 'ring/ring-core', install: nil,
      documentation: ['https://cljdoc.org/d/ring/ring-core/', 'https://cljdoc.org/d/ring/ring-core/1.2.3']
    },
    'cocoapods' => {
      name: 'Alamofire', install: 'pod try Alamofire',
      documentation: ['https://cocoadocs.org/docsets/Alamofire/', 'https://cocoadocs.org/docsets/Alamofire/1.2.3']
    },
    'conan' => {
      name: 'zlib', install: ['conan install --requires=zlib', 'conan install --requires=zlib/1.2.3'],
      documentation: 'https://conan.io/center/recipes/zlib'
    },
    'conda' => {
      name: 'llama.cpp', registry_metadata: { kind: 'conda-forge' },
      install: ['conda install -c conda-forge llama.cpp', 'conda install -c conda-forge llama.cpp=1.2.3'], documentation: nil
    },
    'cpan' => { name: 'Moose', install: nil, documentation: nil },
    'cran' => { name: 'ggplot2', install: nil, documentation: 'http://cran.r-project.org/web/packages/ggplot2/ggplot2.pdf' },
    'ctan' => { name: 'amsmath', install: 'tlmgr install amsmath', documentation: nil },
    'deb' => { name: 'curl', install: 'apt-get install curl', documentation: nil },
    'debian' => {
      name: 'curl', registry_metadata: { codename: 'bookworm' },
      install: 'apt-get install curl', documentation: 'https://packages.debian.org/bookworm/curl'
    },
    'deno' => {
      name: 'oak', install: nil,
      documentation: ['https://doc.deno.land/https://deno.land/x/oak/mod.ts', 'https://doc.deno.land/https://deno.land/x/oak@1.2.3/mod.ts']
    },
    'docker' => { name: 'library/redis', install: ['docker pull library/redis', 'docker pull library/redis:1.2.3'], documentation: nil },
    'elm' => { name: 'elm/core', install: ['elm-package install elm/core', 'elm-package install elm/core 1.2.3'], documentation: nil },
    'elpa' => { name: 'magit', install: 'M-x package-install RET magit RET', documentation: nil },
    'fdroid' => { name: 'org.fdroid.fdroid', install: 'fdroidcl install org.fdroid.fdroid', documentation: nil },
    'freebsd' => {
      name: 'curl', package_metadata: { origin: 'ftp/curl' },
      install: 'pkg install curl', documentation: 'https://www.freshports.org/ftp/curl/'
    },
    'gentoo' => {
      name: 'net-misc/curl', install: ['emerge net-misc/curl', 'emerge =net-misc/curl-1.2.3'],
      documentation: 'https://packages.gentoo.org/packages/net-misc/curl'
    },
    'go' => {
      name: 'golang.org/x/text', install: ['go get golang.org/x/text', 'go get golang.org/x/text@1.2.3'],
      documentation: ['https://pkg.go.dev/golang.org/x/text#section-documentation', 'https://pkg.go.dev/golang.org/x/text@1.2.3#section-documentation']
    },
    'guix' => {
      name: 'hello', package_metadata: { location: 'gnu/packages/base.scm:100' },
      install: ['guix install hello', 'guix install hello@1.2.3'],
      documentation: 'https://git.savannah.gnu.org/cgit/guix.git/tree/gnu/packages/base.scm#n100'
    },
    'hackage' => { name: 'aeson', install: ['cabal install aeson', 'cabal install aeson-1.2.3'], documentation: nil },
    'helm' => {
      name: 'bitnami/redis', package_metadata: { repository_url: 'https://charts.bitnami.com/bitnami' },
      install: ['helm repo add bitnami https://charts.bitnami.com/bitnami && helm install redis bitnami/redis',
                'helm repo add bitnami https://charts.bitnami.com/bitnami && helm install redis bitnami/redis --version 1.2.3'],
      documentation: 'https://artifacthub.io/packages/helm/bitnami/redis'
    },
    'hex' => {
      name: 'phoenix', install: ['mix hex.package fetch phoenix', 'mix hex.package fetch phoenix 1.2.3'],
      documentation: ['http://hexdocs.pm/phoenix/', 'http://hexdocs.pm/phoenix/1.2.3']
    },
    'homebrew' => { name: 'wget', install: 'brew install wget', documentation: nil },
    'ips' => { name: 'web/curl', install: 'pkg install web/curl', documentation: nil },
    'julia' => {
      name: 'JSON', install: ['Pkg.add("JSON")', 'Pkg.add("JSON@1.2.3")'],
      documentation: ['https://docs.juliahub.com/General/JSON/stable/', 'https://docs.juliahub.com/General/JSON/1.2.3/']
    },
    'lean' => { name: 'leanprover-community/mathlib4', install: nil, documentation: nil },
    'maven' => {
      name: 'org.apache.commons:commons-lang3', install: nil,
      documentation: ['https://appdoc.app/artifact/org.apache.commons/commons-lang3/', 'https://appdoc.app/artifact/org.apache.commons/commons-lang3/1.2.3']
    },
    'nixpkgs' => {
      name: 'hello', package_metadata: { position: 'pkgs/by-name/he/hello/package.nix:10' },
      install: 'nix-env -iA nixpkgs.hello',
      documentation: 'https://github.com/NixOS/nixpkgs/blob/nixos-unstable/pkgs/by-name/he/hello/package.nix#L10'
    },
    'npm' => { name: '@babel/core', install: ['npm install @babel/core', 'npm install @babel/core@1.2.3'], documentation: nil },
    'nuget' => { name: 'Newtonsoft.Json', install: ['Install-Package Newtonsoft.Json', 'Install-Package Newtonsoft.Json -Version 1.2.3'], documentation: nil },
    'opam' => {
      name: 'lwt', install: ['opam install lwt', 'opam install lwt.1.2.3'],
      documentation: ['https://ocaml.org/p/lwt/latest/doc/index.html', 'https://ocaml.org/p/lwt/1.2.3/doc/index.html']
    },
    'openbsd' => {
      name: 'devel/protobuf-c', package_metadata: { fullpkgname: 'protobuf-c-1.2.4' },
      version_metadata: { fullpkgname: 'protobuf-c-1.2.3' },
      install: ['pkg_add protobuf-c-1.2.4', 'pkg_add protobuf-c-1.2.3'], documentation: nil
    },
    'openvsx' => { name: 'redhat/java', install: nil, documentation: nil },
    'packagist' => { name: 'symfony/console', install: ['composer require symfony/console', 'composer require symfony/console:1.2.3'], documentation: nil },
    'pkgsrc' => {
      name: 'devel/protobuf-c', package_metadata: { pkgbase: 'protobuf-c' }, version_metadata: { pkgname: 'protobuf-c-1.2.3nb1' },
      install: ['pkg_add protobuf-c', 'pkg_add protobuf-c-1.2.3nb1'], documentation: 'https://pkgsrc.se/devel/protobuf-c'
    },
    'postmarketos' => { name: 'curl', install: 'apk add curl', documentation: nil },
    'pub' => {
      name: 'http', url: 'https://pub.dev', install: ['dart pub add http', 'dart pub add http:1.2.3'],
      documentation: ['https://pub.dev/documentation/http/', 'https://pub.dev/documentation/http/1.2.3']
    },
    'puppet' => { name: 'puppetlabs-stdlib', install: ['puppet module install puppetlabs-stdlib', 'puppet module install puppetlabs-stdlib --version 1.2.3'], documentation: nil },
    'pypi' => {
      name: 'requests', url: 'https://pypi.org',
      install: ['pip install requests --index-url https://pypi.org/simple', 'pip install requests==1.2.3 --index-url https://pypi.org/simple'],
      documentation: ['https://requests.readthedocs.io/', 'https://requests.readthedocs.io/en/1.2.3']
    },
    'racket' => { name: 'rackunit', install: 'raco pkg install rackunit', documentation: 'https://docs.racket-lang.org/rackunit/index.html' },
    'rubygems' => {
      name: 'rails', url: 'https://rubygems.org',
      install: ['gem install rails -s https://rubygems.org', 'gem install rails -s https://rubygems.org -v 1.2.3'],
      documentation: ['http://www.rubydoc.info/gems/rails/', 'http://www.rubydoc.info/gems/rails/1.2.3']
    },
    'spack' => { name: 'zlib', install: ['spack install zlib', 'spack install zlib@1.2.3'], documentation: nil },
    'swiftpm' => {
      name: 'github.com/swift-cloud/Compute', install: nil,
      documentation: ['https://swiftpackageindex.com/swift-cloud/Compute/documentation', 'https://swiftpackageindex.com/swift-cloud/Compute/1.2.3/documentation']
    },
    'terraform' => {
      name: 'terraform-aws-modules/vpc/aws',
      install: ["module \"example\" {\n  source  = \"terraform-aws-modules/vpc/aws\"\n}",
                "module \"example\" {\n  source  = \"terraform-aws-modules/vpc/aws\"\n  version = \"1.2.3\"\n}"],
      documentation: 'https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws'
    },
    'ubuntu' => { name: 'curl', install: 'apt-get install curl', documentation: nil },
    'vcpkg' => { name: 'zlib', install: '.\vcpkg install zlib', documentation: nil }
  }.freeze

  test 'rendering cases cover every ecosystem' do
    assert_equal Ecosystem::Base.list.map(&:lowercase_name).sort, CASES.keys.sort
  end

  CASES.each do |ecosystem, attributes|
    { install_command: :install, documentation_url: :documentation }.each do |method, expectation|
      [:package, :version].each_with_index do |target, index|
        test "#{ecosystem} #{target} #{method}" do
          registry = Registry.new(name: "#{ecosystem}.example", url: attributes.fetch(:url, 'https://registry.example.test'),
                                  ecosystem: ecosystem, metadata: attributes.fetch(:registry_metadata, {}))
          package = registry.packages.build(name: attributes.fetch(:name), ecosystem: ecosystem,
                                            metadata: attributes.fetch(:package_metadata, {}))
          version = package.versions.build(number: '1.2.3', metadata: attributes.fetch(:version_metadata, {}))
          record = target == :package ? package : version
          expected = attributes.fetch(expectation)
          expected = expected[index] if expected.is_a?(Array)

          actual = record.public_send(method)

          expected.nil? ? assert_nil(actual) : assert_equal(expected, actual)
          assert_not_requested :any, /.*/
        end
      end
    end
  end
end
