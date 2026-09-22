require 'test_helper'

class OpamManifestTest < ActiveSupport::TestCase
  test 'reads fields around named sections without treating strings as syntax' do
    manifest = OpamManifest.new(<<~'OPAM')
      opam-version: "2.0"
      description: """Text containing depends: ["fake"] # not a comment"""
      depends: ["real" {>= "1.0"}]
      extra-source "file.patch" {
        src: "https://example.org/file.patch"
      }
      (* outer comment (* nested comment *) *)
      dev-repo: "git+https://example.org/repository.git"
      depopts: "optional"
    OPAM

    assert_equal [{ name: 'real', constraints: '>= "1.0"', optional: false }], manifest.dependencies('depends')
    assert_equal ['git+https://example.org/repository.git'], manifest.strings('dev-repo')
    assert_equal 'optional', manifest.dependencies('depopts', optional: true).sole[:name]
  end

  test 'preserves precedence and nested alternative groups' do
    manifest = OpamManifest.new('depends: ["a" | "b" & ("c" | "d" {>= "2" | < "1"})]')

    assert_equal({ 'or' => [
      { 'name' => 'a' },
      { 'and' => [{ 'name' => 'b' }, { 'or' => [{ 'name' => 'c' }, { 'name' => 'd', 'constraint' => '>= "2" | < "1"' }] }] }
    ] }, manifest.formula('depends'))
    assert manifest.dependencies('depends').all? { |dep| dep[:optional] }
  end

  test 'decodes opam string escapes including UTF-8 byte sequences' do
    manifest = OpamManifest.new(<<~'OPAM')
      authors: ["Ren\195\169" "line\nquote\"" "hex\x21"]
    OPAM

    assert_equal ["René", "line\nquote\"", 'hex!'], manifest.strings('authors')
  end

  test 'retains platform filters and system dependencies as raw metadata' do
    manifest = OpamManifest.new(<<~'OPAM')
      available: [os != "win32"]
      depexts: [["libev-dev"] {os-family = "debian"}]
      conflicts: ["old" {< "1"}]
    OPAM

    assert_equal '[os != "win32"]', manifest.raw('available')
    assert_equal '[["libev-dev"] {os-family = "debian"}]', manifest.raw('depexts')
    assert_equal '["old" {< "1"}]', manifest.raw('conflicts')
  end

  test 'rejects malformed manifests and formulas' do
    ['depends: ["a"', 'depends: ["a")', '(* unfinished', 'depends: ["a" | ]', 'depends: ["a" & ]'].each do |source|
      assert_raises(ArgumentError) { OpamManifest.new(source).formula('depends') }
    end
  end
end
