# Turns the raw license strings registries report into SPDX license ids and expressions.
# Shared by Package (stored normalized_licenses) and Version (worked out when the API response is built).
module LicenseNormalization
  MAX_LENGTH = 150
  CACHE_LIMIT = 10_000

  NON_SPDX_LICENSE_VALUES = ["other", "unknown", "none", "noassertion", "proprietary", "custom", "see license", "open source"].freeze

  # Common registry license names that Spdx.find fuzzy matches to the wrong license (e.g. "ASF 2.0" to MulanPSL-2.0)
  LICENSE_NAME_PATTERNS = {
    /\A(asf|asl|al)[\s-]?v?2(\.0)?\z/ => "Apache-2.0",
    /\A(eclipse distribution license|edl)\b.*(?<![\d.])1\.0\z/ => "BSD-3-Clause",
    /\Agpl ?v?2 with cpe\z/ => "GPL-2.0-with-classpath-exception"
  }.freeze

  # Deprecated SPDX ids that fold an exception into the license id, and the expression that replaces them
  DEPRECATED_EXCEPTION_IDS = {
    "GPL-2.0-with-classpath-exception" => "GPL-2.0-only WITH Classpath-exception-2.0"
  }.freeze

  EMPTY_SPDX_EXPRESSIONS = ["NONE", "NOASSERTION"].freeze

  @cache = Concurrent::Map.new

  class << self
    # Flattened SPDX ids, ["Other"] when nothing matches and [] when there is no license
    def normalize(licenses)
      return [] if licenses.blank?
      return ["Other"] if licenses.length > MAX_LENGTH

      ids = spdx_ids(licenses)
      ids.empty? ? ["Other"] : ids
    end

    def spdx_ids(licenses)
      return [] if licenses.blank?

      cached([:ids, licenses]) { compute_spdx_ids(licenses) }.dup
    end

    # A valid SPDX expression keeping AND, OR and WITH, or nil when the operator would have to be guessed.
    # Pass multiple: "OR" for registries where listing several licenses means the user may pick any of them.
    def expression(licenses, multiple: nil)
      return if licenses.blank? || licenses.length > MAX_LENGTH

      cached([:expression, licenses, multiple]) { compute_expression(licenses.squish, multiple) }
    end

    def clear_cache
      @cache.clear
    end

    private

    def cached(key)
      return @cache[key] if @cache.key?(key)

      @cache.clear if @cache.size >= CACHE_LIMIT
      @cache[key] = yield.freeze
    end

    def compute_spdx_ids(licenses)
      return Spdx.parse_spdx(licenses).licenses if Spdx.valid_spdx?(licenses)

      licenses
        .downcase
        .sub(/^\(/, "")
        .sub(/\)$/, "")
        .split(" or ")
        .flat_map { |l| l.split(" and ") }
        .map { |l| manual_license_format(l) }
        .flat_map { |l| l.split(/[,\/]/) }
        .map(&:strip)
        .reject { |l| l.blank? || l.match?(/\A(version\s+)?[\d.]+\z/) }
        .map { |l| NON_SPDX_LICENSE_VALUES.include?(l) ? nil : find_spdx_license(l) }
        .compact
        .map(&:id)
    end

    def compute_expression(licenses, multiple)
      return if EMPTY_SPDX_EXPRESSIONS.include?(licenses)

      spdx = valid_expression(licenses)
      return replace_deprecated_ids(spdx) if spdx

      ids = spdx_ids(licenses).uniq
      return replace_deprecated_ids(ids.first) if ids.one?
      # only join a list of licenses, never a string that itself says how they combine ("CDDL and GPL")
      return ids.map { |id| replace_deprecated_ids(id) }.join(" #{multiple} ") if multiple && ids.many? && !licenses.match?(/\s(and|or)\s/i)

      nil
    end

    # The string as given when it is already a valid SPDX expression, also accepting lowercase operators ("MIT or Apache-2.0")
    def valid_expression(licenses)
      return licenses if Spdx.valid_spdx?(licenses)

      upcased = licenses.gsub(/\s+(or|and|with)\s+/i) { " #{Regexp.last_match(1).upcase} " }
      upcased if upcased != licenses && Spdx.valid_spdx?(upcased)
    end

    def replace_deprecated_ids(expression)
      DEPRECATED_EXCEPTION_IDS.reduce(expression) do |result, (id, replacement)|
        result.gsub(/(?<![\w.+-])#{Regexp.escape(id)}(?![\w.+-])/, replacement)
      end
    end

    def find_spdx_license(name)
      LICENSE_NAME_PATTERNS.each { |pattern, id| return Spdx.find(id) if name.match?(pattern) }

      # "EPL 2.0" or "Apache 2.0" are exact SPDX ids once the space is a hyphen, so skip the fuzzy match
      hyphenated = name.sub(/\s+v?(?=\d)/, "-")
      (hyphenated != name && Spdx.lookup(hyphenated)) || Spdx.find(name)
    end

    def manual_license_format(license)
      # fixes "Apache License, Version 2.0" etc being incorrectly split on the comma
      # and "GPL2 w/ CPE" being split on the slash
      license
        .gsub(/\b(license|licence)( \([a-z]+\))?, version\b/, 'license\2 version')
        .gsub(/\b(license|licence)( \([a-z]+\))?, v(\d)/, 'license\2 v\3')
        .gsub(%r{\bw/\s*}, 'with ')
    end
  end
end
