default_registries = [
  {name: 'bower.io', url: 'https://bower.io', ecosystem: 'bower', github: 'bower', default: true},
  {name: 'crates.io', url: 'https://crates.io', ecosystem: 'cargo', github: 'rust-lang', default: true},
  {name: 'cocoapod.org', url: 'https://cocoapods.org', ecosystem: 'cocoapods', github: 'cocoapods', default: true},
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
]

default_registries.each do |registry|
  data = registry.merge()
  r = Registry.find_or_initialize_by(url: data[:url])
  r.assign_attributes(data)
  r.save
end