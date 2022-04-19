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
  {name: 'spack.io', url: 'https://spack.github.io', ecosystem: 'spack', github: 'spack'},
  {name: 'hackage.haskell.org', url: 'https://hackage.haskell.org', ecosystem: 'hackage', github: 'haskell-infra'},
  {name: 'cran.r-project.org', url: 'https://cran.r-project.org', ecosystem: 'cran', github: 'r-project-org'},
  {name: 'formulae.brew.sh', url: 'http://formulae.brew.sh', ecosystem: 'homebrew', github: 'homebrew'},
  {name: 'forge.puppet.com', url: 'https://forge.puppet.com', ecosystem: 'puppet', github: 'puppet'},
  {name: 'juliahub.com', url: 'https://juliahub.com', ecosystem: 'julia', github: 'JuliaRegistries'},
]

default_registries.each do |registry|
  data = registry.merge(default: true)
  r = Registry.find_or_initialize_by(url: data[:url])
  r.assign_attributes(data)
  r.save
end