default_registries = [
  {name: 'bower.io', url: 'https://bower.io', ecosystem: 'bower', github: 'bower', default: true},
  {name: 'crates.io', url: 'https://crates.io', ecosystem: 'cargo', github: 'rust-lang', default: true},
  {name: 'cocoapods.org', url: 'https://cocoapods.org', ecosystem: 'cocoapods', github: 'cocoapods', default: true},
  {name: 'metacpan.org', url: 'https://metacpan.org', ecosystem: 'cpan', github: 'metacpan', default: true},
  {name: 'proxy.golang.org', url: 'https://proxy.golang.org', ecosystem: 'go', github: 'golang', default: true},
  {name: 'hex.pm', url: 'https://hex.pm', ecosystem: 'hex', github: 'hexpm', default: true},
  {name: 'npmjs.org', url: 'https://registry.npmjs.org', ecosystem: 'npm', github: 'npm', default: true},
  {name: 'nuget.org', url: 'https://www.nuget.org', ecosystem: 'nuget', github: 'nuget', default: true},
  {name: 'packagist.org', url: 'https://packagist.org', ecosystem: 'packagist', github: 'packagist', default: true},
  {name: 'pub.dev', url: 'https://pub.dev', ecosystem: 'pub', github: 'dart-lang', default: true},
  {name: 'pypi.org', url: 'https://pypi.org', ecosystem: 'pypi', github: 'pypi', default: true},
  {name: 'rubygems.org', url: 'https://rubygems.org', ecosystem: 'rubygems', github: 'rubygems', default: true},
  {name: 'spack.io', url: 'https://packages.spack.io', ecosystem: 'spack', github: 'spack', default: true},
  {name: 'hackage.haskell.org', url: 'https://hackage.haskell.org', ecosystem: 'hackage', github: 'haskell-infra', default: true},
  {name: 'cran.r-project.org', url: 'https://cran.r-project.org', ecosystem: 'cran', github: 'r-project-org', default: true},
  {name: 'formulae.brew.sh', url: 'https://formulae.brew.sh', ecosystem: 'homebrew', github: 'homebrew', default: true},
  {name: 'forge.puppet.com', url: 'https://forge.puppet.com', ecosystem: 'puppet', github: 'puppet', default: true},
  {name: 'juliahub.com', url: 'https://juliahub.com', ecosystem: 'julia', github: 'JuliaRegistries', default: true},
  {name: 'package.elm-lang.org', url: 'https://package.elm-lang.org', ecosystem: 'elm', github: 'elm', default: true},
  {name: 'deno.land', url: 'https://deno.land', ecosystem: 'deno', github: 'denoland', default: true},
  {name: 'clojars.org', url: 'https://repo.clojars.org', ecosystem: 'clojars', github: 'clojars', default: true},
  {name: 'repo1.maven.org', url: 'https://repo1.maven.org/maven2', ecosystem: 'maven', github: 'maven-central', default: true},
  {name: 'repository.jboss.org', url: 'https://repository.jboss.org/nexus/content/repositories/releases', ecosystem: 'maven', github: 'jboss-eap', default: false},
  {name: 'repository.apache.org-releases', url: 'https://repository.apache.org/content/repositories/releases', ecosystem: 'maven', github: 'apache', default: false},
  {name: 'repository.apache.org-snapshots', url: 'https://repository.apache.org/content/repositories/snapshots', ecosystem: 'maven', github: 'apache', default: false},
  {name: 'artifacts.alfresco.com', url: 'https://artifacts.alfresco.com/nexus/content/repositories/public', ecosystem: 'maven', github: 'alfresco', default: false},
  {name: 'repository.cloudera.com', url: 'https://repository.cloudera.com/content/repositories/public', ecosystem: 'maven', github: 'cloudera', default: false},
  {name: 'pkgs.racket-lang.org', url: 'https://pkgs.racket-lang.org', ecosystem: 'racket', github: 'racket-lang', default: true},
  {name: 'elpa.gnu.org', url: 'https://elpa.gnu.org/packages', ecosystem: 'elpa', github: 'emacs', default: true},
  {name: 'elpa.nongnu.org', url: 'https://elpa.nongnu.org/nongnu', ecosystem: 'elpa', github: 'emacs', default: false},
  {name: 'anaconda.org', url: 'https://anaconda.org', ecosystem: 'conda', github: 'Anaconda', metadata: {'kind' => 'anaconda', 'key' => 'Main', 'api' => 'https://repo.ananconda.com'}, default: true},
  {name: 'conda-forge.org', url: 'https://conda-forge.org', ecosystem: 'conda', github: 'conda-forge', metadata: {'kind' => 'conda-forge', 'key' => 'CondaForge', 'api' => 'https://conda.anaconda.org'}, default: false},
  {name: 'hub.docker.com', url: 'https://hub.docker.com', ecosystem: 'docker', github: 'docker', metadata: {api_url: 'https://registry-1.docker.io'}, default: true},
  {name: 'swiftpackageindex.com', url: 'https://swiftpackageindex.com', ecosystem: 'swiftpm', github: 'SwiftPackageIndex', default: true},
  {name: 'vcpkg.io', url: 'https://vcpkg.io', ecosystem: 'vcpkg', github: 'vcpkg', default: true},
  {name: "carthage", url: "https://github.com/Carthage/Carthage", ecosystem: "carthage", github: "Carthage", default: true},
  {name: 'github actions', url: 'https://github.com/marketplace/actions/', ecosystem: 'actions', github: 'actions', default: true},
  {name: 'pkg.adelielinux.org', url: "https://pkg.adelielinux.org/current", ecosystem: "adelie", github: "AdelieLinux", default: true, metadata: {repos: ['system', 'user']}},
  {name: 'bioconductor.org', url: 'https://bioconductor.org', ecosystem: 'bioconductor', github: 'Bioconductor', default: true},
]

default_registries.each do |data|
  r = Registry.find_or_initialize_by(url: data[:url])
  r.assign_attributes(data)
  r.save
end

alpine_registries = []
# TODO automate version list from https://dl-cdn.alpinelinux.org/alpine/
alpine_versions = ['edge', 'v3.22', 'v3.21', 'v3.20', 'v3.19', 'v3.18', 'v3.17','v3.16','v3.15','v3.14','v3.13','v3.12', 'v3.11', 'v3.10', 'v3.9', 'v3.8', 'v3.7', 'v3.6', 'v3.5', 'v3.4', 'v3.3']

alpine_versions.each do |version|
  repos = ['main', 'community']
  repos << 'testing' if version == 'edge'
  alpine_registries << {
    name: "alpine-#{version}", 
    url: "https://pkgs.alpinelinux.org/packages?branch=#{version}", 
    ecosystem: 'alpine', 
    github: 'alpinelinux', 
    default: false,
    version: version,
    metadata: {
      repos: repos
    }
  }
end

alpine_registries.each do |data|
  r = Registry.find_or_initialize_by(url: data[:url])
  r.assign_attributes(data)
  r.save
end

postmarketos_registries = []
# TODO automate version list from http://mirror.postmarketos.org/postmarketos/
postmarketos_versions = ['master', 'v25.06', 'v24.12', 'v24.06', 'v23.12', 'v23.06', 'v22.12', 'v22.06', 'v21.12', 'v21.06', 'v21.03', 'v20.05']

postmarketos_versions.each do |version|
  postmarketos_registries << {
    name: "postmarketos-#{version}", 
    url: "https://pkgs.postmarketos.org/packages?branch=#{version}", 
    ecosystem: 'postmarketos', 
    github: 'postmarketos', 
    default: false,
    version: version
  }
end

postmarketos_registries.each do |data|
  r = Registry.find_or_initialize_by(url: data[:url])
  r.assign_attributes(data)
  r.save
end
