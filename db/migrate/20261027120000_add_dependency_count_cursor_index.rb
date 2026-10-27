class AddDependencyCountCursorIndex < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    with_index_timeouts do
      add_index :dependencies, [:package_id, :id], include: [:version_id],
                where: 'package_id IS NOT NULL',
                name: 'index_dependencies_on_package_id_and_id', algorithm: :concurrently
    end
  end

  def down
    with_index_timeouts do
      remove_index :dependencies, name: 'index_dependencies_on_package_id_and_id', algorithm: :concurrently
    end
  end

  def with_index_timeouts
    settings = %w[statement_timeout lock_timeout].to_h { |name| [name, connection.select_value("SHOW #{name}")] }
    connection.execute("SET statement_timeout = '0'")
    connection.execute("SET lock_timeout = '250ms'")
    yield
  ensure
    settings&.each { |name, value| connection.execute("SET #{name} = #{connection.quote(value)}") }
  end
end
