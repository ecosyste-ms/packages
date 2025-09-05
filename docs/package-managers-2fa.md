# Package Managers - 2FA Support Overview

**Context:** US and allies have declared a national defence crisis. Critical open source dependencies are an attack vector for state actors. We recommend contacting your mobile service provider, and using biometric-protected passkeys over SMS as a two-factor authentication solution.

| Package Manager | Number of Packages | 2FA Supported | 2FA Methods | SMS/Mobile Only | Documentation |
|-----------------|-------------------|---------------|-------------|-----------------|---------------|
| [npm](https://npmjs.org) | 5,131,352 | ✅ Required | WebAuthn/TOTP | ❌ (No SMS) | [npm 2FA docs](https://docs.npmjs.com/configuring-two-factor-authentication/) |
| [Go Proxy](https://proxy.golang.org) | 1,952,122 | N/A | N/A | N/A | No user accounts |
| [Docker Hub](https://hub.docker.com) | 1,002,256 | ✅ Available | TOTP only | ❌ (No SMS) | [Docker 2FA docs](https://docs.docker.com/security/2fa/) |
| [NuGet](https://nuget.org) | 740,221 | ✅ Required* | Via Microsoft Account | ❌ | [NuGet 2FA wiki](https://github.com/NuGet/Home/wiki/2-Factor-Auth-for-NuGet.org-sign-in) |
| [PyPI](https://pypi.org) | 725,183 | ✅ Required | WebAuthn/TOTP | ❌ (No SMS) | [PyPI 2FA help](https://pypi.org/help/#twofa) |
| [Maven Central](https://repo1.maven.org) | 547,830 | ⚠️ Unknown | Unknown | Unknown | Unknown |
| [Packagist](https://packagist.org) | 466,319 | ✅ Available | TOTP | ❌ | [PR #1031](https://github.com/composer/packagist/pull/1031) |
| [Crates.io](https://crates.io) | 204,483 | ⚠️ Via GitHub | GitHub 2FA | N/A | [Discussion #4200](https://github.com/rust-lang/crates.io/discussions/4200) |
| [RubyGems](https://rubygems.org) | 199,693 | ✅ Available | WebAuthn/TOTP | ❌ | [RubyGems MFA guide](https://guides.rubygems.org/setting-up-multifactor-authentication/) |
| [CocoaPods](https://cocoapods.org) | 101,227 | ❌ No | Email tokens only | N/A | [Trunk setup guide](https://guides.cocoapods.org/making/getting-setup-with-trunk.html) |
| [GitHub Actions](https://github.com/actions) | 32,174 | ✅ Required | Via GitHub Account | N/A | [GitHub 2FA docs](https://docs.github.com/en/authentication/securing-your-account-with-two-factor-authentication-2fa) |
| [CRAN](https://cran.r-project.org) | 26,177 | ❌ No | Email only | N/A | [CRAN submission](https://cran.r-project.org/submit.html) |
| [Clojars](https://clojars.org) | 21,103 | ✅ Optional | TOTP | ❌ | [Clojars 2FA wiki](https://github.com/clojars/clojars-web/wiki/Two-Factor-Auth) |
| [Conda-forge](https://conda-forge.org) | 20,636 | N/A | Registry on GitHub | N/A | [Maintainer docs](https://conda-forge.org/docs/maintainer/knowledge_base/) |
| [Hex.pm](https://hex.pm) | 18,539 | ✅ Optional | TOTP | ❌ | [Hex.pm blog](https://hex.pm/blog/announcing-two-factor-auth) |
| [Hackage](https://hackage.haskell.org) | 18,401 | ❌ No | Token auth only | N/A | [Issue #1265](https://github.com/haskell/hackage-server/issues/1265) |
| [JuliaHub](https://juliahub.com) | 12,681 | ⚠️ Via SSO | Depends on SSO | N/A | [Auth guide](https://help.juliahub.com/juliahub-jl/stable/guides/authentication/) |
| [Swift Package Index](https://swiftpackageindex.com) | 10,651 | N/A | Discovery only | N/A | Index/discovery platform |
| [Spack](https://spack.io) | 8,772 | ⚠️ Via GitHub | GitHub 2FA/Signatures | N/A | [GitHub packages](https://github.com/spack/spack-packages) |
| [Homebrew](https://formulae.brew.sh) | 8,580 | ⚠️ Via GitHub | GitHub 2FA/PAT | N/A | [Contributing docs](https://docs.brew.sh/Adding-Software-to-Homebrew) |

## Legend
- ✅ **Available/Required**: 2FA is either available or mandatory
- ❌ **Not Available**: 2FA is not currently supported
- ⚠️ **Indirect/Varies**: Authentication depends on third-party provider
- **N/A**: No user authentication system (read-only proxy, discovery platform, etc.)

## Notes
- **NuGet**: Uses Microsoft Account authentication which requires 2FA as of 2025
- **Crates.io**: Uses GitHub authentication exclusively; 2FA depends on GitHub account settings
- **CocoaPods**: Going read-only in late 2026; uses email-based session tokens only
- **Conda-forge**: No user logins; package registry managed entirely on GitHub
- **JuliaHub**: Enterprise/Team editions use SSO; 2FA depends on identity provider
- **Swift Package Index**: Discovery/documentation platform, not a package registry
- **Spack**: Package registry managed on GitHub; uses both GitHub 2FA and cryptographic signatures
- **Homebrew**: Contributions via GitHub PRs; requires GitHub PAT with 2FA enabled