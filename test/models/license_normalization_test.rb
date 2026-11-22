require 'test_helper'

class LicenseNormalizationTest < ActiveSupport::TestCase
  setup do
    LicenseNormalization.clear_cache
  end

  test 'normalize returns [] without a license and Other when nothing matches' do
    assert_equal [], LicenseNormalization.normalize(nil)
    assert_equal [], LicenseNormalization.normalize('')
    assert_equal ['Other'], LicenseNormalization.normalize('other')
    assert_equal ['Other'], LicenseNormalization.normalize('x' * 151)
  end

  test 'normalize flattens SPDX expressions and license names' do
    assert_equal ['Apache-2.0', 'BSD-3-Clause', 'PSF-2.0'], LicenseNormalization.normalize('(Apache-2.0 OR BSD-3-Clause) AND PSF-2.0')
    assert_equal ['GPL-2.0', 'MIT'], LicenseNormalization.normalize('GPLv2,MIT')
    assert_equal ['Apache-2.0'], LicenseNormalization.normalize('ASF 2.0')
  end

  test 'normalize returns a copy that callers can change' do
    first = LicenseNormalization.normalize('MIT')
    first << 'Apache-2.0'

    assert_equal ['MIT'], LicenseNormalization.normalize('MIT')
  end

  test 'expression keeps valid SPDX expressions with their operators' do
    assert_equal '(Apache-2.0 OR BSD-3-Clause) AND PSF-2.0', LicenseNormalization.expression('(Apache-2.0 OR BSD-3-Clause) AND PSF-2.0')
    assert_equal 'GPL-2.0-only WITH Classpath-exception-2.0', LicenseNormalization.expression('GPL-2.0-only WITH Classpath-exception-2.0')
    assert_equal 'MIT OR Apache-2.0', LicenseNormalization.expression('  MIT   OR Apache-2.0 ')
  end

  test 'expression accepts lowercase operators between valid ids' do
    assert_equal 'Apache-2.0 OR MIT', LicenseNormalization.expression('Apache-2.0 or MIT')
  end

  test 'expression replaces deprecated ids that fold in the classpath exception' do
    assert_equal 'GPL-2.0-only WITH Classpath-exception-2.0', LicenseNormalization.expression('GPL-2.0-with-classpath-exception')
    assert_equal 'MIT OR GPL-2.0-only WITH Classpath-exception-2.0', LicenseNormalization.expression('MIT OR GPL-2.0-with-classpath-exception')
    assert_equal 'GPL-2.0-only WITH Classpath-exception-2.0', LicenseNormalization.expression('GPL2 w/ CPE')
  end

  test 'expression uses the single id a license name resolves to' do
    assert_equal 'Apache-2.0', LicenseNormalization.expression('Apache License, Version 2.0')
    assert_equal 'MIT', LicenseNormalization.expression('mit')
  end

  test 'expression is nil when the operator between several licenses is unknown' do
    assert_nil LicenseNormalization.expression('GPLv2,MIT')
  end

  test 'expression joins several licenses with the given operator' do
    assert_equal 'GPL-2.0 OR MIT', LicenseNormalization.expression('GPLv2,MIT', multiple: 'OR')
    assert_equal 'EPL-2.0 OR GPL-2.0-only WITH Classpath-exception-2.0',
                 LicenseNormalization.expression('Eclipse Public License 2.0,GNU General Public License, version 2 with the GNU Classpath Exception', multiple: 'OR')
    assert_equal 'Apache-2.0', LicenseNormalization.expression('Apache-2.0,Apache-2.0', multiple: 'OR')
  end

  test 'expression is nil when any listed license does not resolve' do
    assert_nil LicenseNormalization.expression('MIT,unknown')
    assert_nil LicenseNormalization.expression('MIT,unknown', multiple: 'OR')
    assert_nil LicenseNormalization.expression('Apache License, Version 2.0,other', multiple: 'OR')
  end

  test 'caches a nil expression without recomputing it' do
    assert_nil LicenseNormalization.expression('GPLv2,MIT')
    Spdx.expects(:valid_spdx?).never

    assert_nil LicenseNormalization.expression('GPLv2,MIT')
  end

  test 'expression does not join licenses whose string already says how they combine' do
    assert_nil LicenseNormalization.expression('GPLv2 and MIT', multiple: 'OR')
  end

  test 'expression is nil without a usable license' do
    [nil, '', 'NONE', 'NOASSERTION', 'other', 'unknown', 'x' * 151].each do |licenses|
      assert_nil LicenseNormalization.expression(licenses), licenses.inspect
    end
  end

  test 'caches results' do
    assert_equal 'MIT', LicenseNormalization.expression('MIT')
    Spdx.expects(:valid_spdx?).never

    assert_equal 'MIT', LicenseNormalization.expression('MIT')
  end

  test 'clears the cache once it reaches the limit' do
    cache = LicenseNormalization.instance_variable_get(:@cache)
    LicenseNormalization::CACHE_LIMIT.times { |i| cache[[:filler, i]] = true }

    assert_equal 'MIT', LicenseNormalization.expression('MIT')
    assert_equal 1, cache.size
  end
end
