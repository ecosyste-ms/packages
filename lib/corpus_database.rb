require 'json'

class CorpusDatabase
  attr_reader :catalog, :queries

  def initialize
    @queries = 0
    @catalog = read("SELECT reltuples::bigint AS estimated_rows, pg_total_relation_size(oid) AS total_bytes FROM pg_class WHERE oid = 'packages'::regclass", limit: 1, catalog: true).first
    @catalog['indexes'] = read("SELECT tablename, indexdef FROM pg_indexes WHERE schemaname = current_schema() AND tablename IN ('packages', 'maintainerships', 'maintainers')", limit: 200, catalog: true)
  end

  def read(sql, limit:, sample: false, catalog: false)
    ActiveRecord::Base.connection_pool.with_connection do |connection|
      connection.transaction do
        connection.execute('SET TRANSACTION READ ONLY')
        connection.execute("SET LOCAL statement_timeout = '5s'")
        connection.execute("SET LOCAL lock_timeout = '500ms'")
        connection.execute("SET LOCAL idle_in_transaction_session_timeout = '15s'")
        connection.execute('SET LOCAL max_parallel_workers_per_gather = 0')
        connection.execute('SET LOCAL jit = off')
        plan = JSON.parse(connection.select_value("EXPLAIN (FORMAT JSON) #{sql}")).first.fetch('Plan')
        nodes = [plan]
        nodes.each { |node| nodes.concat(node.fetch('Plans', [])) }
        large_scan = nodes.any? { |node| node['Node Type'] == 'Seq Scan' && (node.fetch('Total Cost') > 10_000 || node.fetch('Plan Rows', 0) > 10_000) }
        if plan.fetch('Total Cost') > 200_000 || (!catalog && large_scan)
          raise 'Export query exceeds the cost budget or would scan a large table sequentially'
        end
        raise 'Unexpected sample query' if !sample && plan.to_json.include?('Sample Scan')
        result = connection.select_all(sql).to_a
        raise 'Export query exceeded its row limit' if result.size > limit
        @queries += 1
        result
      end
    end
  end
end
