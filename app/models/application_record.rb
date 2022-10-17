class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  def self.fast_total
    ActiveRecord::Base.count_by_sql "SELECT (reltuples)::bigint FROM pg_class r WHERE relkind = 'r' AND relname = '#{self.table_name}'"
  end
end
