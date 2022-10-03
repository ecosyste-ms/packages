default_registries = [
  {name: 'bower.io', url: 'https://bower.io', ecosystem: 'bower', github: 'bower'},
  {name: 'crates.io', url: 'https://crates.io', ecosystem: 'cargo', github: 'rust-lang'},
  {name: 'cocoapod.org', url: 'https://cocoapods.org', ecosystem: 'cocoapods', github: 'cocoapods'},
  {name: 'metacpan.org', url: 'https://metacpan.org', ecosystem: 'cpan', github: 'metacpan'},
  {name: 'proxy.golang.org', url: 'https://proxy.golang.org', ecosystem: 'go', github: 'golang'},
  {name: 'hex.pm', url: 'https://hex.pm', ecosystem: 'hex', github: 'hexpm'},
  {name: 'npmjs.org', url: 'https://registry.npmjs.org', ecosystem: 'npm', github: 'npm'},
  {name: 'nuget.org', url: 'https://www.nuget.org', ecosystem: 'nuget', github: 'nuget'},
  {name: 'packagist.org', url: 'https://packagist.org', ecosystem: 'packagist', github: 'packagist'},
  {name: 'pub.dev', url: 'https://pub.dev', ecosystem: 'pub', github: 'dart-lang'},
  {name: 'pypi.org', url: 'https://pypi.org', ecosystem: 'pypi', github: 'pypi'},
  {name: 'rubygems.org', url: 'https://rubygems.org', ecosystem: 'rubygems', github: 'rubygems'},
  {name: 'spack.io', url: 'https://packages.spack.io', ecosystem: 'spack', github: 'spack'},
  {name: 'hackage.haskell.org', url: 'https://hackage.haskell.org', ecosystem: 'hackage', github: 'haskell-infra'},
  {name: 'cran.r-project.org', url: 'https://cran.r-project.org', ecosystem: 'cran', github: 'r-project-org'},
  {name: 'formulae.brew.sh', url: 'http://formulae.brew.sh', ecosystem: 'homebrew', github: 'homebrew'},
  {name: 'forge.puppet.com', url: 'https://forge.puppet.com', ecosystem: 'puppet', github: 'puppet'},
  {name: 'juliahub.com', url: 'https://juliahub.com', ecosystem: 'julia', github: 'JuliaRegistries'},
  {name: 'package.elm-lang.org', url: 'https://package.elm-lang.org', ecosystem: 'elm', github: 'elm'},
  {name: 'deno.land', url: 'https://deno.land', ecosystem: 'deno', github: 'denoland'},
  {name: 'clojars.org', url: 'https://repo.clojars.org', ecosystem: 'clojars', github: 'clojars'},
  {name: 'repo1.maven.org', url: 'https://repo1.maven.org/maven2', ecosystem: 'maven', github: 'maven-central'},
  {name: 'pkgs.racket-lang.org', url: 'http://pkgs.racket-lang.org', ecosystem: 'racket', github: 'racket-lang'},
  {name: 'elpa.gnu.org', url: 'https://elpa.gnu.org/packages', ecosystem: 'elpa', github: 'emacs'},
  {name: 'elpa.nongnu.org', url: 'https://elpa.nongnu.org/nongnu', ecosystem: 'elpa', github: 'emacs'},
  {name: 'anaconda.org', url: 'https://anaconda.org', ecosystem: 'conda', github: 'Anaconda', metadata: {'kind' => 'anaconda', 'key' => 'Main', 'api' => 'https://repo.ananconda.com'}},
  {name: 'conda-forge.org', url: 'https://conda-forge.org', ecosystem: 'conda', github: 'conda-forge', metadata: {'kind' => 'conda-forge', 'key' => 'CondaForge', 'api' => 'https://conda.anaconda.org'}},
]

default_registries.each do |registry|
  data = registry.merge(default: true)
  r = Registry.find_or_initialize_by(url: data[:url])
  r.assign_attributes(data)
  r.save
end