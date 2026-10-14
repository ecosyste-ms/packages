# FFI and native-extension tools for Brief

This is a working catalogue of tools and source signals that Brief could report when a repository mixes a package ecosystem with compiled code. The first use is finding Rust inside packages published to PyPI, npm, RubyGems, Hex, Packagist, CRAN, CPAN, Maven, NuGet, LuaRocks, and Julia's General registry. The same detections can later support studies of C, C++, Fortran, Go, Zig, and other compiled languages.

Packages published as Rust software through Homebrew, Debian, or another system package collection are outside this work. A Homebrew formula for a Rust command should not enter the count merely because the command is written in Rust.

Brief currently reports four native-extension tools:

| Brief definition | What it finds |
| --- | --- |
| `knowledge/python/cext.toml` | setuptools `Extension`, `ext_modules`, and any `.pyx` file |
| `knowledge/node/node-gyp.toml` | `binding.gyp`, `node-gyp`, `node-addon-api`, NAN, and `bindings` |
| `knowledge/ruby/mkmf.toml` | Ruby `extconf.rb` files |
| `knowledge/php/phpize.toml` | PHP extension macros in `config.m4` |

These generic rules are useful, but two of them merge several distinct tools. Once dedicated rules exist, Cython should own `.pyx`, while `node-addon-api`, NAN, and `bindings` should each be reported separately from `node-gyp`. The generic setuptools, node-gyp, mkmf, and phpize rules should remain.

## Reading the signals

The proposed detections fall into three bands:

1. A build or packaging tool dedicated to a native extension is strong evidence. Examples are Maturin, napi-rs, Rustler, and scikit-build-core.
2. A bridge library identifies the language boundary but may not say how the result is shipped. Examples are PyO3, Magnus, Rcpp, and CXX.
3. A runtime FFI library may call a library supplied by the operating system. Examples are Python CFFI in ABI mode, Ruby FFI, JNA, P/Invoke, and LuaJIT FFI. These are leads, not evidence that compiled code is bundled in the package.

Brief currently treats the file, dependency, and content methods in one tool definition as alternatives. Ecosystem gating can require a detected host language, but a rule cannot require a particular host manifest, co-location, and a second specific signal. Entries that rely on combined generic markers should wait for composite detection support.

## Coverage map

This table gives the main paths from implementation language to host package ecosystem. A blank cell does not mean that FFI is impossible. It usually means projects use a plain C ABI and host-specific glue instead of a named bridge.

| Compiled side | Python | Node | Ruby | BEAM | PHP | R | JVM | .NET | Lua | Swift/Kotlin |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| C | setuptools, CFFI, Cython | Node-API, node-addon-api | mkmf | elixir_make, NIF API | phpize | native R API | JNI, JNA, JNR-FFI | P/Invoke | Lua C API | UniFFI through a C ABI |
| C++ | pybind11, nanobind, SWIG | node-addon-api, NAN, cmake-js | Rice | elixir_make | PHP-CPP, SWIG | Rcpp, cpp11 | JavaCPP, SWIG | CppSharp, SWIG | CxxWrap for Julia | CXX or a C wrapper |
| Rust | Maturin, PyO3, setuptools-rust | napi-rs, Neon, node-bindgen | rb-sys, Magnus, Rutie | Rustler | ext-php-rs | extendr | jni-rs, robusta_jni | csbindgen, Interoptopus | mlua | UniFFI, swift-bridge |
| Fortran | F2PY |  |  |  |  | native R API | JNI through C | P/Invoke through C |  |  |
| Go | gopy, C shared library | C shared library | C shared library | C shared library | C shared library | C shared library | JNI through C | P/Invoke through C | C shared library | C shared library |
| Zig | Pydust, C ABI | Node-API through C | Ruby C API | Zigler | PHP C API | R C API | JNI through C | P/Invoke through C | Lua C API | C ABI |
| Nim, D, Haskell, OCaml, Ada | Usually a C ABI | Usually a C ABI | Usually a C ABI | Usually a C ABI | Usually a C ABI | Usually a C ABI | JNI through C | P/Invoke through C | Lua C API | C ABI |

## Python

Python should be the first host ecosystem. It has several high-signal build backends and is likely to provide the largest set of Rust examples.

| Proposed Brief file | Tool | Compiled side | Category | Candidate signals |
| --- | --- | --- | --- | --- |
| `knowledge/python/maturin.toml` | [Maturin](https://www.maturin.rs/) | Rust | `native_extension` | `pyproject.toml` contains `build-backend = "maturin"` or `[tool.maturin]`; build requirement `maturin` |
| `knowledge/python/setuptools-rust.toml` | [setuptools-rust](https://setuptools-rust.readthedocs.io/) | Rust | `native_extension` | dependency `setuptools-rust`; `pyproject.toml` contains `[[tool.setuptools-rust.ext-modules]]` or `[[tool.setuptools-rust.bins]]`; `setup.py` contains `RustExtension(` |
| `knowledge/python/pyo3.toml` | [PyO3](https://pyo3.rs/) | Rust | `library` | Cargo dependency `pyo3` or `pyo3-ffi`; standard root `Cargo.toml` only |
| `knowledge/python/rust-cpython.toml` | [rust-cpython](https://github.com/dgrunwald/rust-cpython) | Rust | `library` | Cargo dependency `cpython` or `python3-sys`; useful for older repositories |
| `knowledge/python/scikit-build-core.toml` | [scikit-build-core](https://scikit-build-core.readthedocs.io/) | C, C++, Fortran, Cython, Rust | `native_extension` | `pyproject.toml` contains `build-backend = "scikit_build_core.build"` or build requirement `scikit-build-core` |
| `knowledge/python/meson-python.toml` | [meson-python](https://mesonbuild.com/meson-python/) | C, C++, Fortran, Cython, Rust | `native_extension` | `pyproject.toml` contains `build-backend = "mesonpy"` or build requirement `meson-python`; pair with the existing Meson result |
| `knowledge/python/cython.toml` | [Cython](https://cython.readthedocs.io/) | C or C++ output | `codegen` | dependency or build requirement `Cython`; `*.pyx`, `**/*.pyx`, `*.pxd`, and `**/*.pxd`; `setup.py` contains `cythonize(` |
| `knowledge/python/pybind11.toml` | [pybind11](https://pybind11.readthedocs.io/) | C++ | `library` | dependency or build requirement `pybind11`; root `CMakeLists.txt` contains `pybind11_add_module` |
| `knowledge/python/nanobind.toml` | [nanobind](https://nanobind.readthedocs.io/) | C++ | `library` | dependency or build requirement `nanobind`; root `CMakeLists.txt` contains `nanobind_add_module` |
| `knowledge/python/hpy.toml` | [HPy](https://docs.hpyproject.org/) | C or C++ | `library` | dependency or build requirement `hpy`; `setup.py` contains `hpy_ext_modules`; `HPy_MODINIT` needs recursive content matching |
| `knowledge/python/boost-python.toml` | [Boost.Python](https://www.boost.org/doc/libs/release/libs/python/) | C++ | `library` | `BOOST_PYTHON_MODULE` or an include of `boost/python.hpp` needs recursive content matching; useful for older extensions |
| `knowledge/python/cffi.toml` | [CFFI](https://cffi.readthedocs.io/) | Any C ABI | `library` | dependency `cffi`; `setup.py` contains `cffi_modules` or `set_source(` |
| `knowledge/python/ctypes.toml` | [ctypes](https://docs.python.org/3/library/ctypes.html) | Any C ABI | `library` | `ctypes.CDLL`, `ctypes.PyDLL`, or `ctypes.cdll.LoadLibrary` needs recursive content matching; runtime-only signal |
| `knowledge/python/f2py.toml` | [F2PY](https://numpy.org/doc/stable/f2py/) | Fortran and C | `codegen` | `*.pyf` or `**/*.pyf`; fixed build files containing `numpy.f2py` or an `f2py` command |
| `knowledge/python/pydust.toml` | [Ziggy Pydust](https://pydust.fulcrum.so/) | Zig | `native_extension` | build requirement `ziggy-pydust`; Pydust configuration in `pyproject.toml`; `build.zig` as supporting evidence |
| `knowledge/python/gopy.toml` | [gopy](https://pkg.go.dev/github.com/go-python/gopy) | Go | `codegen` | Go dependency or tool reference `github.com/go-python/gopy`; generated/build scripts containing a `gopy build` command need recursive content matching |

The Maturin result should say which binding mode was configured when `[tool.maturin] bindings` is present: `pyo3`, `cffi`, `uniffi`, or `bin`. A `bin` project packages a Rust executable in a Python distribution, not a Python extension, but it still answers the broader question about Rust inside a non-Cargo package.

CFFI needs a cautious description. `cffi_modules` or `FFI.set_source()` points to a compiled out-of-line module. A dependency on `cffi` alone often means a pure Python wrapper around an external shared library.

Do not use `cibuildwheel` as native-code evidence. It builds wheel matrices for both native and pure Python projects.

## Node and npm

| Proposed Brief file | Tool | Compiled side | Category | Candidate signals |
| --- | --- | --- | --- | --- |
| `knowledge/node/napi-rs.toml` | [napi-rs](https://napi.rs/) | Rust | `native_extension` | npm dependency `@napi-rs/cli`; Cargo dependencies `napi`, `napi-derive`, or `napi-build`; `package.json` scripts containing `napi build` |
| `knowledge/node/neon.toml` | [Neon](https://neon-rs.dev/) | Rust | `native_extension` | Cargo dependency `neon`; npm dependency `@neon-rs/cli`; `package.json` scripts containing `cargo-cp-artifact` as supporting evidence |
| `knowledge/node/node-bindgen.toml` | [node-bindgen](https://github.com/infinyon/node-bindgen) | Rust | `native_extension` | Cargo dependencies `node-bindgen` or `node-bindgen-macro`; npm build command `nj-cli` |
| `knowledge/node/node-addon-api.toml` | [node-addon-api](https://github.com/nodejs/node-addon-api) | C++ | `library` | npm dependency `node-addon-api`; source includes need recursive content matching |
| `knowledge/node/nan.toml` | [NAN](https://github.com/nodejs/nan) | C++ | `library` | npm dependency `nan`; useful for older V8-based addons |
| `knowledge/node/cmake-js.toml` | [CMake.js](https://github.com/cmake-js/cmake-js) | C or C++ | `native_extension` | npm dependency `cmake-js`; root `CMakeLists.txt` contains `CMAKE_JS_INC`, `CMAKE_JS_LIB`, or `CMAKE_JS_SRC` |
| `knowledge/node/bindings.toml` | [bindings](https://github.com/TooTallNate/node-bindings) | Any native addon | `library` | npm dependency `bindings`; supporting signal only |
| `knowledge/node/node-gyp-build.toml` | [node-gyp-build](https://github.com/prebuild/node-gyp-build) | Any native addon | `native_extension` | npm dependency `node-gyp-build` or `node-gyp-build-optional-packages`; install script calling `node-gyp-build` |
| `knowledge/node/prebuildify.toml` | [prebuildify](https://github.com/prebuild/prebuildify) | Any native addon | `release` | npm dependency `prebuildify`; scripts containing `prebuildify`; `prebuilds/` |
| `knowledge/node/prebuild.toml` | [prebuild](https://github.com/prebuild/prebuild) | Any native addon | `release` | npm dependency `prebuild`; scripts containing `prebuild` |
| `knowledge/node/node-pre-gyp.toml` | [node-pre-gyp](https://github.com/mapbox/node-pre-gyp) | Any native addon | `release` | dependency `@mapbox/node-pre-gyp` or legacy `node-pre-gyp`; `package.json` key `binary` |
| `knowledge/node/ffi-napi.toml` | [ffi-napi](https://github.com/node-ffi-napi/node-ffi-napi) | Any C ABI | `library` | npm dependency `ffi-napi`; runtime-only signal |

The existing `node-gyp` rule should keep `binding.gyp` and the `node-gyp` dependency. Moving `node-addon-api`, NAN, and `bindings` into their own definitions will show whether a package uses the build tool, the C++ API, an older V8 compatibility layer, or only a loader.

Prebuildify is especially useful for later archive work because it places native binaries under `prebuilds/` inside the npm tarball. napi-rs often publishes one small npm package per operating-system and architecture combination. Those packages should be joined to the root package before counting projects.

## Ruby

| Proposed Brief file | Tool | Compiled side | Category | Candidate signals |
| --- | --- | --- | --- | --- |
| `knowledge/ruby/rake-compiler.toml` | [rake-compiler](https://github.com/rake-compiler/rake-compiler) | C, C++, Java, Rust | `native_extension` | gem dependency `rake-compiler`; `Rakefile` contains `Rake::ExtensionTask` |
| `knowledge/ruby/rb-sys.toml` | [rb-sys](https://oxidize-rb.github.io/rb-sys/) | Rust | `native_extension` | Ruby dependency `rb_sys`; Cargo dependency `rb-sys`; `extconf.rb` contains `create_rust_makefile` |
| `knowledge/ruby/magnus.toml` | [Magnus](https://docs.rs/magnus/) | Rust | `library` | Cargo dependency `magnus`; commonly appears with rb-sys |
| `knowledge/ruby/rutie.toml` | [Rutie](https://github.com/danielpclark/rutie) | Rust | `library` | Cargo dependency `rutie`; useful for older or manually built extensions |
| `knowledge/ruby/helix.toml` | [Helix](https://github.com/tildeio/helix) | Rust | `native_extension` | Cargo dependency `helix`; `use Helix` or Helix build tasks need recursive matching; historical |
| `knowledge/ruby/rice.toml` | [Rice](https://ruby-rice.github.io/) | C++ | `library` | Ruby dependency `rice`; C++ includes need recursive content matching |
| `knowledge/ruby/ffi.toml` | [Ruby FFI](https://github.com/ffi/ffi) | Any C ABI | `library` | gem dependency `ffi`; `extend FFI::Library` needs recursive content matching |
| `knowledge/ruby/fiddle.toml` | [Fiddle](https://docs.ruby-lang.org/en/master/Fiddle.html) | Any C ABI | `library` | `require "fiddle"` or `Fiddle.dlopen` needs recursive content matching; runtime-only signal |

The existing mkmf definition will still catch most C extensions and rb-sys extensions through `extconf.rb`. The new rules add the missing implementation detail.

## Elixir and Erlang

| Proposed Brief file | Tool | Compiled side | Category | Candidate signals |
| --- | --- | --- | --- | --- |
| `knowledge/elixir/rustler.toml` | [Rustler](https://rustler.hexdocs.pm/) | Rust | `native_extension` | Mix dependency `rustler`; `native/*/Cargo.toml`; standard source path `native/` |
| `knowledge/elixir/rustler-precompiled.toml` | [RustlerPrecompiled](https://rustler-precompiled.hexdocs.pm/) | Rust | `release` | Mix dependency `rustler_precompiled`; source contains `use RustlerPrecompiled` after recursive matching is added |
| `knowledge/elixir/elixir-make.toml` | [elixir_make](https://hexdocs.pm/elixir_make/) | Any compiled language | `native_extension` | Mix dependency `elixir_make`; `mix.exs` contains `compilers: [:elixir_make]`; `Makefile` |
| `knowledge/elixir/cc-precompiler.toml` | [cc_precompiler](https://hexdocs.pm/cc_precompiler/) | C or C++ | `release` | Mix dependency `cc_precompiler`; `mix.exs` contains `make_precompiler` |
| `knowledge/elixir/zigler.toml` | [Zigler](https://hexdocs.pm/zigler/) | Zig | `native_extension` | Mix or rebar dependency `zigler`; source contains `use Zig` after recursive matching is added |
| `knowledge/erlang/rebar3-port-compiler.toml` | [rebar3 port compiler](https://github.com/blt/port_compiler) | C or C++ | `native_extension` | rebar dependency or plugin `pc`; `rebar.config` contains `port_specs`; `c_src/` |

RustlerPrecompiled and elixir_make precompiler settings also identify projects that distribute or download per-platform NIF artifacts. That is a separate fact from the source language and should appear in Brief's output.

## PHP

| Proposed Brief file | Tool | Compiled side | Category | Candidate signals |
| --- | --- | --- | --- | --- |
| `knowledge/php/ext-php-rs.toml` | [ext-php-rs](https://ext-php.rs/) | Rust | `native_extension` | Cargo dependency `ext-php-rs`; use of `cargo-php`; `#[php_module]` needs recursive content matching |
| `knowledge/php/zephir.toml` | [Zephir](https://docs.zephir-lang.com/) | Generated C | `codegen` | `zephir.json`; `*.zep` and `**/*.zep`; Composer development dependency on Zephir packages |
| `knowledge/php/php-cpp.toml` | [PHP-CPP](https://www.php-cpp.com/) | C++ | `library` | C++ include `phpcpp.h` needs recursive content matching; project-specific build files |
| `knowledge/php/ffi.toml` | [PHP FFI](https://www.php.net/manual/en/book.ffi.php) | Any C ABI | `library` | `FFI::cdef`, `FFI::load`, or `FFI::scope` needs recursive content matching; runtime-only signal |

The current phpize rule remains the generic direct-extension detector. ext-php-rs should be an additional result, not a replacement.

## R

| Proposed Brief file | Tool | Compiled side | Category | Candidate signals |
| --- | --- | --- | --- | --- |
| `knowledge/r/native-code.toml` | R native code | C, C++, Fortran, or another linked language | `native_extension` | `DESCRIPTION` contains `NeedsCompilation: yes`; `src/Makevars`, `src/Makevars.win`, or native source under `src/` |
| `knowledge/r/rcpp.toml` | [Rcpp](https://www.rcpp.org/) | C++ | `library` | DESCRIPTION dependency or `LinkingTo` entry `Rcpp`; `src/RcppExports.cpp` |
| `knowledge/r/cpp11.toml` | [cpp11](https://cpp11.r-lib.org/) | C++ | `library` | DESCRIPTION dependency or `LinkingTo` entry `cpp11`; `src/cpp11.cpp`; source annotation needs recursive matching |
| `knowledge/r/extendr.toml` | [extendr and rextendr](https://extendr.github.io/rextendr/) | Rust | `native_extension` | exact `src/rust/Cargo.toml` containing `extendr-api`; `src/entrypoint.c`; `src/Makevars` containing a Cargo command |

The standard rextendr package layout is unusually helpful: `src/rust/Cargo.toml`, `src/entrypoint.c`, and Cargo calls from `src/Makevars` form a strong repository signature even though packages using extendr do not need a runtime dependency on the `rextendr` R package.

`NeedsCompilation: yes` is also useful package metadata and should be taken directly from CRAN data when packages.ecosyste.ms exposes it. The Brief result remains valuable for repositories and registries that do not carry an equivalent field.

## Perl

| Proposed Brief file | Tool | Compiled side | Category | Candidate signals |
| --- | --- | --- | --- | --- |
| `knowledge/perl/xs.toml` | [XS and ExtUtils::ParseXS](https://metacpan.org/pod/ExtUtils%3A%3AParseXS) | C or C++ | `native_extension` | `*.xs` and `**/*.xs`; dependency `ExtUtils::ParseXS`; `typemap` |
| `knowledge/perl/inline-c.toml` | [Inline::C](https://metacpan.org/pod/Inline%3A%3AC) | C | `native_extension` | CPAN dependency `Inline::C`; source use needs recursive matching |
| `knowledge/perl/inline-cpp.toml` | [Inline::CPP](https://metacpan.org/pod/Inline%3A%3ACPP) | C++ | `native_extension` | CPAN dependency `Inline::CPP`; source use needs recursive matching |
| `knowledge/perl/ffi-platypus.toml` | [FFI::Platypus](https://metacpan.org/pod/FFI%3A%3APlatypus) | Any C ABI | `library` | CPAN dependency `FFI::Platypus`; runtime-only unless native source is also present |
| `knowledge/perl/alien-build.toml` | [Alien::Build](https://metacpan.org/pod/Alien%3A%3ABuild) | External compiled library | `build` | dependency `Alien::Build`; `alienfile`; says a dependency may be downloaded and compiled, not that it is part of the Perl distribution |
| `knowledge/perl/perlmod-rs.toml` | [perlmod-rs](https://github.com/proxmox/perlmod-rs) | Rust | `codegen` | Cargo dependencies `perlmod` or `perlmod-macro`; rare, but a direct Rust-to-Perl signal |

## JVM packages

| Proposed Brief file | Tool | Compiled side | Category | Candidate signals |
| --- | --- | --- | --- | --- |
| `knowledge/java/jni.toml` | [JNI](https://docs.oracle.com/en/java/javase/25/docs/specs/jni/) | Any native language | `native_extension` | generated `*.h` plus fixed build-file references to JNI; direct source markers need recursive matching |
| `knowledge/java/jna.toml` | [JNA](https://github.com/java-native-access/jna) | Any C ABI | `library` | Maven or Gradle dependency `net.java.dev.jna:jna`; usually runtime-only |
| `knowledge/java/jnr-ffi.toml` | [JNR-FFI](https://github.com/jnr/jnr-ffi) | Any C ABI | `library` | dependency `com.github.jnr:jnr-ffi`; usually runtime-only |
| `knowledge/java/javacpp.toml` | [JavaCPP](https://bytedeco.org/) | C or C++ | `codegen` | dependency `org.bytedeco:javacpp`; `javacpp-maven-plugin`; JavaCPP annotations need recursive matching |
| `knowledge/java/hawtjni.toml` | [HawtJNI](https://fusesource.github.io/hawtjni/) | C or C++ | `codegen` | Maven plugin or dependency with group `org.fusesource.hawtjni`; generated native source directories |
| `knowledge/java/jni-rs.toml` | [jni-rs](https://docs.rs/jni/) | Rust | `library` | Cargo dependency `jni`; stronger when a JVM project and `cdylib` crate are both present |
| `knowledge/java/robusta-jni.toml` | [robusta_jni](https://docs.rs/robusta_jni/) | Rust | `codegen` | Cargo dependency `robusta_jni`; `#[bridge]` is supporting source evidence |

JNA and JNR-FFI often call a library already installed on the machine. JavaCPP presets and JAR layouts such as `META-INF/native/` or `org/bytedeco/*/<platform>/` are better indicators of bundled binaries.

The JVM definitions should use ecosystem gates for Java, Kotlin, Scala, Clojure, and Groovy. The dependency or source marker carries more meaning than the language used for the managed wrapper.

## .NET and NuGet

| Proposed Brief file | Tool | Compiled side | Category | Candidate signals |
| --- | --- | --- | --- | --- |
| `knowledge/csharp/pinvoke.toml` | [P/Invoke](https://learn.microsoft.com/en-us/dotnet/standard/native-interop/) | Any C ABI | `library` | `[LibraryImport(` and `[DllImport(` need recursive content matching; runtime-only without native assets |
| `knowledge/csharp/native-assets.toml` | NuGet native assets | Any native language | `native_extension` | `runtimes/*/native/`; `.nuspec` entries targeting `runtimes/.../native`; native files copied by `.csproj` |
| `knowledge/csharp/cppsharp.toml` | [CppSharp](https://github.com/mono/CppSharp) | C or C++ | `codegen` | NuGet dependency `CppSharp`; generator project references |
| `knowledge/csharp/clangsharp.toml` | [ClangSharpPInvokeGenerator](https://github.com/dotnet/ClangSharp) | C or C++ | `codegen` | NuGet or tool dependency `ClangSharpPInvokeGenerator`; generated P/Invoke source |
| `knowledge/csharp/csbindgen.toml` | [csbindgen](https://docs.rs/csbindgen/) | Rust | `codegen` | Cargo build dependency `csbindgen`; generated C# files commonly contain a generator notice |
| `knowledge/csharp/interoptopus.toml` | [Interoptopus](https://interoptopus.rs/) | Rust | `codegen` | Cargo dependencies `interoptopus` and `interoptopus_csharp`; generated `[DllImport]` bindings |

NuGet's `runtimes/<rid>/native/` layout is stronger evidence of a binary inside a package than a P/Invoke declaration. It should be checked directly when archive inspection is added.

The .NET definitions should cover C# and F# projects. P/Invoke source matching will mostly be C#, while native asset layout applies to any NuGet package.

## Lua and Julia

| Proposed Brief file | Tool | Compiled side | Category | Candidate signals |
| --- | --- | --- | --- | --- |
| `knowledge/lua/native-module.toml` | Lua C module | Any C ABI | `native_extension` | rockspec native module declarations need glob-aware content matching; `luaopen_` is the direct ABI marker |
| `knowledge/lua/luajit-ffi.toml` | [LuaJIT FFI](https://luajit.org/ext_ffi.html) | Any C ABI | `library` | `require("ffi")`, `ffi.cdef`, and `ffi.load` need recursive matching; runtime-only without native assets |
| `knowledge/lua/mlua.toml` | [mlua module mode](https://docs.rs/mlua/) | Rust | `native_extension` | Cargo dependency `mlua`; the `module` feature and `#[mlua::lua_module]` separate a loadable Lua module from a Rust program embedding Lua |
| `knowledge/julia/cxxwrap.toml` | [CxxWrap.jl](https://github.com/JuliaInterop/CxxWrap.jl) | C++ | `library` | Julia dependency `CxxWrap`; CMake dependency `JlCxx`; native source alongside `Project.toml` |
| `knowledge/julia/native-call.toml` | Julia native call | Any C ABI | `library` | `ccall`, `@ccall`, and `Libdl.dlopen` need recursive matching; runtime-only without native assets |
| `knowledge/julia/jlrs.toml` | [jlrs](https://docs.rs/jlrs/) | Rust | `library` | Cargo dependency `jlrs`; direction can be Julia calling Rust or Rust embedding Julia |

Julia JLL packages and `Artifacts.toml` usually refer to binaries stored as separate artifacts. They should be recorded as external binary dependencies, not automatically counted as native code bundled in the Julia package archive.

## Shared generators and Rust-native bridges

These definitions describe mixed-language repositories but do not identify a package host on their own.

| Proposed Brief file | Tool | Direction | Category | Signals |
| --- | --- | --- | --- | --- |
| `knowledge/_shared/swig.toml` | [SWIG](https://www.swig.org/Doc4.3/) | C or C++ to many host languages | `codegen` | `*.i` and `**/*.i`; CMake `UseSWIG`; fixed build files invoking `swig` |
| `knowledge/rust/uniffi.toml` | [UniFFI](https://mozilla.github.io/uniffi-rs/latest/) | Rust to Kotlin, Swift, Python, and Ruby | `codegen` | Cargo dependency `uniffi`; `uniffi.toml`; `*.udl` and `**/*.udl` |
| `knowledge/rust/cbindgen.toml` | [cbindgen](https://github.com/mozilla/cbindgen) | Rust to C or C++ headers | `codegen` | `cbindgen.toml`; Cargo build dependency `cbindgen`; build scripts invoking the executable |
| `knowledge/rust/cxx.toml` | [CXX](https://cxx.rs/) | Rust and C++ in both directions | `codegen` | Cargo dependencies `cxx` and `cxx-build`; `#[cxx::bridge]` needs recursive matching |
| `knowledge/rust/autocxx.toml` | [autocxx](https://google.github.io/autocxx/) | C++ to Rust, with calls in both directions | `codegen` | Cargo dependencies `autocxx` and `autocxx-build`; `include_cpp!` needs recursive matching |
| `knowledge/rust/bindgen.toml` | [bindgen](https://rust-lang.github.io/rust-bindgen/) | C or C++ to Rust | `codegen` | Cargo build dependency `bindgen`; this proves Rust consumes native code, not that Rust is exposed to another package |
| `knowledge/rust/swift-bridge.toml` | [swift-bridge](https://docs.rs/swift-bridge/) | Rust and Swift in both directions | `codegen` | Cargo dependencies `swift-bridge` and `swift-bridge-build`; `#[swift_bridge::bridge]` |
| `knowledge/rust/safer-ffi.toml` | [safer-ffi](https://getditto.github.io/safer_ffi/) | Rust to a C ABI, with optional generated headers | `codegen` | Cargo dependency `safer-ffi`; exported FFI annotations need recursive matching |
| `knowledge/rust/diplomat.toml` | [Diplomat](https://rust-diplomat.github.io/diplomat/) | Rust to several host languages | `codegen` | Cargo dependencies beginning `diplomat`; generated binding directories are supporting evidence |

`bindgen`, CXX, and autocxx are useful mixed-language signals, but should not be counted as proof that a non-Rust package contains Rust. `cbindgen`, UniFFI, swift-bridge, and host-specific Rust bridges point in the more relevant direction.

WebAssembly should be kept adjacent but separate. `wasm-bindgen`, `wasm-pack`, Emscripten, and wasm-packaged npm modules answer a related question about compiled code in dynamic-language packages, but a WebAssembly module is not a native extension. Brief could report them as `codegen` or `build` without mixing them into `native_extension` totals.

## Direct ABI markers

Named tools will miss hand-written extensions. Recursive content matching would allow a second set of generic native-extension definitions:

| Host | Strong source markers |
| --- | --- |
| Python | `#include <Python.h>`, `PyInit_`, `PyModuleDef`, `HPy_MODINIT` |
| Node | `NAPI_MODULE`, `NAPI_MODULE_INIT`, `node::NODE_MODULE`, `#include <napi.h>` |
| Ruby | `#include <ruby.h>`, exported functions named `Init_` |
| Erlang/Elixir | `#include <erl_nif.h>`, `ERL_NIF_INIT` |
| PHP | `PHP_NEW_EXTENSION`, `zend_module_entry`, `ZEND_GET_MODULE` |
| R | `R_CallMethodDef`, `R_registerRoutines`, `useDynLib` in `NAMESPACE` |
| Perl | `.xs` files, `XS(`, `boot_` functions generated by xsubpp |
| JVM | `#include <jni.h>`, `JNIEXPORT`, `System.loadLibrary`, Java `native` methods |
| .NET | `LibraryImport`, `DllImport`, `UnmanagedCallersOnly` |
| Lua | `#include <lua.h>`, `luaopen_` |
| Julia | `ccall`, `@ccall`, `JLCXX_MODULE` |

Compiled languages that expose a plain C ABI also have useful supporting markers:

| Language | Markers |
| --- | --- |
| Rust | Cargo `crate-type` containing `cdylib` or `staticlib`; `extern "C"` exports; `no_mangle` or `unsafe(no_mangle)` |
| Go | `go build -buildmode=c-shared`; cgo `//export` declarations |
| Zig | `export fn`; shared-library targets in `build.zig` |
| Fortran | `.pyf` files; `bind(C)` |
| Haskell | `foreign export ccall` |
| OCaml | dune `foreign_stubs`; `ctypes`; C stubs using `CAMLprim` |
| Nim | `{.exportc.}` and `{.dynlib.}` pragmas |
| D | `extern(C)` exported functions |
| Ada | `pragma Export (C, ...)` |
| V | `@[export: 'name']`; builds using `-shared` |
| Odin | `@(export)`; builds using `-build-mode:shared` |

These markers are supporting evidence until Brief can require a particular host package manifest and an export marker together. A Rust `cdylib`, for example, may be a plugin for a desktop application rather than code inside a PyPI or npm package.

## Brief changes exposed by this list

Most first-batch rules fit Brief's current TOML format. Four additions would make the lower-confidence rules much more useful:

- Allow `file_contains` keys to be globs, such as `**/*.rs`, `**/*.ex`, and `**/*.gemspec`.
- Add an all-of detection group so a rule can require a host manifest, a compiled-language manifest, and an ABI or build signal.
- Parse manifests below the root even when they are not declared workspace members. Rust crates under `native/`, `ext/`, `src/rust/`, and language-specific binding directories are common.
- Return the matched detector and path in Brief's structured output. Research code can then keep a build-backend match separate from a runtime FFI dependency.

An optional `implementation_languages` field on a tool would avoid reconstructing the compiled side from tool names. A Maturin result could report `rust`, F2PY could report `fortran`, and scikit-build-core could leave the field unset until source-language evidence is combined with it.

## Suggested implementation order

The first batch should favor exact dependencies and fixed configuration files:

1. Maturin, setuptools-rust, PyO3, napi-rs, Neon, rb-sys, Magnus, Rustler, RustlerPrecompiled, ext-php-rs, extendr, mlua module mode, jni-rs, csbindgen, and Interoptopus.
2. scikit-build-core, meson-python, Cython, pybind11, nanobind, HPy, Boost.Python, F2PY, node-addon-api, cmake-js, node-gyp-build, prebuildify, rake-compiler, elixir_make, Zigler, R native code, Rcpp, cpp11, Perl XS, JavaCPP, NuGet native assets, and SWIG.
3. CFFI, ctypes, Ruby FFI, Fiddle, ffi-napi, JNA, JNR-FFI, P/Invoke, LuaJIT FFI, and Julia native calls. Keep these as runtime FFI leads unless a second signal shows bundled source or binary assets.
4. Older and lower-volume tools such as rust-cpython, node-bindgen, Rutie, Helix, PHP-CPP, perlmod-rs, robusta_jni, Pydust, gopy, safer-ffi, and Diplomat.

Each Brief definition should get a small positive fixture and a near miss. The near misses matter most for generic names such as `bindings`, `ffi`, and `native`. Before accepting a rule, run it over a sample of repositories from repos.ecosyste.ms and inspect the matches. That will expose package-manager parsing gaps and names that are too broad before the rule affects a full scan.
