class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  def self.column_sort_order(column, direction)
    ordering = Arel.sql(column).public_send(direction)
    columns_hash[column]&.null == false ? ordering : ordering.nulls_last
  end

  def self.fast_total
    ActiveRecord::Base.count_by_sql "SELECT (reltuples)::bigint FROM pg_class r WHERE relkind = 'r' AND relname = '#{self.table_name}'"
  end
end
