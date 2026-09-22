require 'strscan'

class OpamManifest
  attr_reader :fields

  def initialize(source)
    @source = source
    @scanner = StringScanner.new(source)
    nodes = read_nodes
    @nodes = nodes
    @fields = {}
    index = 0
    while index < nodes.length
      node = nodes[index]
      if node[:type] == :word && nodes[index + 1]&.dig(:text) == ':'
        name = node[:text]
        index += 2
        start = index
        index += 1 while index < nodes.length && !field_start?(nodes, index)
        @fields[name] = nodes[start...index]
      else
        index += 1
      end
    end
  end

  def section(name)
    index = @nodes.index { |node| node[:type] == :word && node[:text] == name }
    group = @nodes[index + 1] if index
    return unless group && group[:delimiter] == '{'
    self.class.new(@source.byteslice((group[:start] + 1)...(group[:finish] - 1)))
  end

  def field_start?(nodes, index)
    return false unless nodes[index][:type] == :word
    nodes[index + 1]&.dig(:text) == ':' || nodes[index + 1]&.dig(:delimiter) == '{' ||
      (nodes[index + 1]&.dig(:type) == :string && nodes[index + 2]&.dig(:delimiter) == '{')
  end

  def read_nodes(closing = nil)
    nodes = []
    until @scanner.eos?
      next if @scanner.scan(/\s+|\#[^\n]*/)
      if @scanner.scan(/\(\*/)
        depth = 1
        while depth.positive?
          marker = @scanner.scan_until(/\(\*|\*\)/)
          raise ArgumentError, 'Unterminated opam comment' unless marker
          depth += marker.end_with?('(*') ? 1 : -1
        end
        next
      end

      start = @scanner.pos
      if @scanner.scan(/"""(?:[^"\\]|\\.|"(?!""))*"""|"(?:\\.|[^"\\])*"/m)
        nodes << { type: :string, text: @scanner.matched, start: start, finish: @scanner.pos }
      elsif @scanner.scan(/[\[({]/)
        delimiter = @scanner.matched
        children = read_nodes({ '[' => ']', '(' => ')', '{' => '}' }.fetch(delimiter))
        nodes << { type: :group, delimiter: delimiter, children: children, start: start, finish: @scanner.pos }
      elsif @scanner.scan(/[\])}]/)
        raise ArgumentError, 'Mismatched opam delimiter' unless @scanner.matched == closing
        return nodes
      elsif @scanner.scan(/[a-zA-Z0-9_+.-]+/)
        nodes << { type: :word, text: @scanner.matched, start: start, finish: @scanner.pos }
      elsif @scanner.scan(/[:!<>=|&?]+/)
        nodes << { type: :operator, text: @scanner.matched, start: start, finish: @scanner.pos }
      else
        raise ArgumentError, "Invalid opam syntax at byte #{@scanner.pos}"
      end
    end
    raise ArgumentError, 'Unterminated opam group' if closing
    nodes
  end

  def strings(field)
    nodes = fields.fetch(field, [])
    nodes = nodes.first[:children] if nodes.length == 1 && nodes.first[:delimiter] == '['
    nodes.select { |node| node[:type] == :string }.map { |node| decode_string(node[:text]) }
  end

  def decode_string(text)
    value = text.start_with?('"""') ? text[3...-3] : text[1...-1]
    value.b.gsub(/\\(?:\r?\n[ \t]*|[0-9]{3}|x[0-9a-fA-F]{2}|.)/m) do |escape|
      case escape
      when /\A\\\r?\n/ then ''
      when /\A\\[0-9]{3}\z/ then escape[1..].to_i.chr
      when /\A\\x/ then escape[2..].to_i(16).chr
      else { '\\n' => "\n", '\\r' => "\r", '\\t' => "\t", '\\b' => "\b" }.fetch(escape, escape[1..])
      end
    end.force_encoding(Encoding::UTF_8)
  end

  def raw(field)
    nodes = fields.fetch(field, [])
    return nil if nodes.empty?
    @source.byteslice(nodes.first[:start]...nodes.last[:finish])
  end

  def formula(field)
    nodes = fields.fetch(field, [])
    nodes = nodes.first[:children] if nodes.length == 1 && nodes.first[:delimiter] == '['
    parse_formula(nodes)
  end

  def parse_formula(nodes)
    return nil if nodes.empty?
    alternatives = [[]]
    nodes.each do |node|
      node[:text] == '|' ? alternatives << [] : alternatives.last << node
    end
    if alternatives.length > 1
      raise ArgumentError, 'Empty opam alternative' if alternatives.any?(&:empty?)
      return { 'or' => alternatives.map { |part| parse_formula(part) } }
    end

    terms = []
    index = 0
    while index < nodes.length
      node = nodes[index]
      if node[:delimiter] == '('
        terms << parse_formula(node[:children])
      elsif node[:type] == :string
        term = { 'name' => decode_string(node[:text]) }
        if nodes[index + 1]&.dig(:delimiter) == '{'
          index += 1
          filter = nodes[index]
          term['constraint'] = @source.byteslice((filter[:start] + 1)...(filter[:finish] - 1)).strip
        end
        terms << term
      else
        raise ArgumentError, 'Invalid opam dependency formula'
      end
      index += 1
      if nodes[index]&.dig(:text) == '&'
        index += 1
        raise ArgumentError, 'Incomplete opam conjunction' if index == nodes.length
      end
    end
    terms.length == 1 ? terms.first : { 'and' => terms }
  end

  def dependencies(field, optional: false)
    dependency_leaves(formula(field), optional: optional).uniq
  end

  def dependency_leaves(node, optional: false)
    return [] unless node
    if node.key?('name')
      return [{ name: node['name'], constraints: node['constraint'], optional: optional }]
    end
    children = node['and'] || node.fetch('or')
    children.flat_map { |child| dependency_leaves(child, optional: optional || node.key?('or')) }
  end
end
