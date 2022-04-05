default_registries = [
  {name: 'Bower.io', url: 'https://bower.io', ecosystem: 'bower', github: 'bower'},
  {name: 'Crates.io', url: 'https://crates.io', ecosystem: 'Cargo', github: 'rust-lang'},
  {name: 'Cocoapod.org', url: 'https://cocoapods.org', ecosystem: 'Cocoapods', github: 'Cocoapods'},
  {name: 'Metacpan.org', url: 'https://metacpan.org', ecosystem: 'cpan', github: 'metacpan'},
  {name: 'proxy.golang.org', url: 'https://proxy.golang.org', ecosystem: 'Go', github: 'golang'},
  {name: 'Hex.pm', url: 'https://hex.pm', ecosystem: 'Hex', github: 'hexpm'},
  {name: 'Npmjs.org', url: 'https://registry.npmjs.org', ecosystem: 'npm', github: 'npm'},
  {name: 'NuGet.org', url: 'https://www.nuget.org', ecosystem: 'nuget', github: 'nuget'},
  {name: 'Packagist.org', url: 'https://packagist.org', ecosystem: 'Packagist', github: 'Packagist'},
  {name: 'Pub.dev', url: 'https://pub.dev', ecosystem: 'pub', github: 'dart-lang'},
  {name: 'Pypi.org', url: 'https://pypi.org', ecosystem: 'pypi', github: 'pypi'},
  {name: 'Rubygems.org', url: 'https://rubygems.org', ecosystem: 'rubygems', github: 'rubygems'},
  {name: 'Spack.io', url: 'https://spack.github.io', ecosystem: 'spack', github: 'spack'},
  {name: 'Hackage.haskell.org', url: 'https://hackage.haskell.org', ecosystem: 'hackage', github: 'haskell'}
]

default_registries.each do |registry|
  data = registry.merge(default: true)
  r = Registry.find_or_initialize_by(url: data[:url])
  r.assign_attributes(data)
  r.save
end