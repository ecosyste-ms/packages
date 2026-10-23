# frozen_string_literal: true

class EasyconfigParser
  attr_reader :source, :data

  def self.parse(source)
    new(source).parse
  end

  def initialize(source)
    @source = source.to_s
    @data = {}
  end

  def parse
    @data = {
      name: extract_string_var('name'),
      version: extract_string_var('version'),
      homepage: extract_string_var('homepage'),
      description: extract_multiline_string_var('description'),
      easyblock: extract_string_var('easyblock'),
      versionsuffix: extract_string_var('versionsuffix'),
      toolchain: extract_toolchain,
      dependencies: extract_dependencies('dependencies', kind: 'runtime'),
      builddependencies: extract_dependencies('builddependencies', kind: 'build'),
      source_urls: extract_string_array('source_urls'),
      sources: extract_string_array('sources'),
      patches: extract_string_array('patches'),
      checksums: extract_string_array('checksums')
    }
  end

  private

  # Extract single or double quoted string variable e.g. name = 'TensorFlow'
  def extract_string_var(var_name)
    pattern = /^\s*#{Regexp.escape(var_name)}\s*=\s*(?:'([^']*)'|"([^"]*)")/
    if (m = @source.match(pattern))
      m[1] || m[2]
    end
  end

  # Extract multiline triple-quoted or single-quoted string e.g. description = """..."""
  def extract_multiline_string_var(var_name)
    # Triple double quotes
    if (m = @source.match(/^\s*#{Regexp.escape(var_name)}\s*=\s*"""(.*?)"""/m))
      return m[1].strip
    end
    # Triple single quotes
    if (m = @source.match(/^\s*#{Regexp.escape(var_name)}\s*=\s*'''(.*?)'''/m))
      return m[1].strip
    end
    # Fallback to single/double quote
    extract_string_var(var_name)
  end

  # Extract toolchain: {'name': 'foss', 'version': '2023a'} or SYSTEM
  def extract_toolchain
    if (m = @source.match(/^\s*toolchain\s*=\s*\{([^}]*)\}/m))
      dict_body = m[1]
      tc_name = dict_body.match(/['"]name['"]\s*:\s*['"]([^'"]+)['"]/)
      tc_ver = dict_body.match(/['"]version['"]\s*:\s*['"]([^'"]+)['"]/)
      res = {}
      res[:name] = tc_name[1] if tc_name
      res[:version] = tc_ver[1] if tc_ver
      res
    elsif @source.match(/^\s*toolchain\s*=\s*SYSTEM/i)
      { name: 'system' }
    else
      {}
    end
  end

  # Extract dependencies list of tuples: [('name', 'ver'), ...]
  def extract_dependencies(var_name, kind: 'runtime')
    pattern = /^\s*#{Regexp.escape(var_name)}\s*=\s*\[(.*?)\](?:\n|\r\n|\Z)/m
    m = @source.match(pattern)
    return [] unless m

    body = m[1]
    deps = []

    # Match each tuple: ('name', 'ver', ...) or ("name", "ver", ...)
    tuple_pattern = /\(\s*(?:'([^']*)'|"([^"]*)")\s*,\s*(?:'([^']*)'|"([^"]*)")(?:[^\)]*)\)/
    body.scan(tuple_pattern) do
      # $1/$2 is name, $3/$4 is version
      dep_name = $1 || $2
      dep_ver = $3 || $4
      next if dep_name.nil? || dep_name.empty?

      v = (dep_ver.nil? || dep_ver.empty?) ? '*' : dep_ver
      deps << {
        name: dep_name,
        version: v,
        kind: kind
      }
    end

    deps
  end

  # Extract list of strings e.g. source_urls = ['url1', 'url2']
  def extract_string_array(var_name)
    pattern = /^\s*#{Regexp.escape(var_name)}\s*=\s*\[(.*?)\](?:\n|\r\n|\Z)/m
    m = @source.match(pattern)
    return [] unless m

    body = m[1]
    items = []
    body.scan(/(?:'([^']*)'|"([^"]*)")/) do |single_q, double_q|
      val = single_q || double_q
      items << val if val && !val.empty?
    end
    items
  end
end
