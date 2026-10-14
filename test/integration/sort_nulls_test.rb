require 'test_helper'

class SortNullsTest < ActionDispatch::IntegrationTest
  setup do
    @registry = Registry.create!(name: 'crates.io', url: 'https://crates.io', ecosystem: 'cargo')
    @package = @registry.packages.create!(ecosystem: 'cargo', name: 'rand')
  end

  %w[recent index].each do |action|
    %w[created_at updated_at published_at number].each do |column|
      %w[asc desc].each do |direction|
        test "versions #{action} sorts #{column} #{direction} with schema nullability" do
          travel_to Time.utc(2026, 9, 26, 12) do
            3.times do |i|
              @package.versions.create!(
                registry: @registry, number: "1.0.#{i}",
                created_at: (3 - i).days.ago, updated_at: (30 - i).minutes.ago,
                published_at: i == 2 ? nil : (3 - i).days.ago
              )
            end
            params = {
              sort: column, order: direction, per_page: 500,
              created_after: 7.days.ago.iso8601, created_before: Time.current.iso8601,
              updated_after: 1.hour.ago.iso8601, updated_before: Time.current.iso8601
            }

            sql = capture_ordered_query('versions') { get versions_path(action), params: params }

            assert_response :success
            null_order = %w[published_at number].include?(column) ? ' NULLS LAST' : ''
            assert_match(/ORDER BY #{column} #{direction.upcase}#{null_order} LIMIT/, sql)
            refute_match(/NULLS LAST/i, sql) if null_order.empty?
            assert_includes sql, 'EXISTS (SELECT 1 FROM packages WHERE packages.id = versions.package_id)' if action == 'recent'
            expected = direction == 'asc' ? %w[1.0.0 1.0.1 1.0.2] : %w[1.0.2 1.0.1 1.0.0]
            expected = %w[1.0.1 1.0.0 1.0.2] if column == 'published_at' && direction == 'desc'
            assert_equal expected, response.parsed_body.map { |version| version['number'] }
          end
        end
      end
    end

    test "versions #{action} preserves default published_at null ordering and created_at tie breaker" do
      sql = capture_ordered_query('versions') { get versions_path(action) }

      assert_response :success
      assert_match(/ORDER BY published_at DESC nulls last, created_at DESC LIMIT/i, sql)
    end

    test "versions #{action} falls back to nullable published_at for invalid sort" do
      sql = capture_ordered_query('versions') do
        get versions_path(action), params: { sort: 'created_at; DROP TABLE versions', order: 'invalid' }
      end

      assert_response :success
      assert_match(/ORDER BY published_at DESC NULLS LAST LIMIT/, sql)
    end
  end

  %w[asc desc].each do |direction|
    { 'id' => '', 'package_name' => ' NULLS LAST' }.each do |column, null_order|
      test "dependencies sort #{column} #{direction} with schema nullability" do
        sql = capture_ordered_query('dependencies') do
          get api_v1_dependencies_path, params: { sort: column, order: direction }
        end

        assert_response :success
        assert_match(/ORDER BY #{column} #{direction.upcase}#{null_order} LIMIT/, sql)
      end
    end

    { 'created_at' => '', 'updated_at' => '', 'packages_count' => ' NULLS LAST' }.each do |column, null_order|
      test "maintainers sort #{column} #{direction} with schema nullability" do
        sql = capture_ordered_query('maintainers') do
          get registry_maintainers_path(registry_id: @registry.name), params: { sort: column, order: direction }
        end

        assert_response :success
        assert_match(/ORDER BY #{column} #{direction.upcase}#{null_order} LIMIT/, sql)
      end
    end
  end

  %w[api html].each do |format|
    %w[created_at updated_at versions_count].each do |column|
      %w[asc desc].each do |direction|
        test "#{format} packages sort #{column} #{direction} without null ordering" do
          @package.update!(created_at: 2.days.ago, updated_at: 2.days.ago, versions_count: 1)
          @registry.packages.create!(ecosystem: 'cargo', name: 'serde', versions_count: 2)
          path = format == 'api' ? api_v1_registry_packages_path(registry_id: @registry.name) : registry_packages_path(registry_id: @registry.name)

          sql = capture_ordered_query('packages') { get path, params: { sort: column, order: direction } }

          assert_response :success
          assert_match(/ORDER BY #{column} #{direction.upcase} LIMIT/, sql)
          refute_match(/NULLS LAST/i, sql)
          names = if format == 'api'
            response.parsed_body.map { |package| package['name'] }
          else
            css_select('h5 a').map(&:text)
          end
          assert_equal(direction == 'asc' ? %w[rand serde] : %w[serde rand], names)
        end
      end
    end
  end

  { 'downloads' => 'downloads', 'stargazers_count' => "(repo_metadata ->> 'stargazers_count')::text::integer" }.each do |sort, expression|
    test "api packages retain nulls last for #{sort}" do
      @registry.packages.create!(ecosystem: 'cargo', name: 'serde', downloads: 10, repo_metadata: { stargazers_count: 10 })

      sql = capture_ordered_query('packages') do
        get api_v1_registry_packages_path(registry_id: @registry.name), params: { sort: sort, order: 'desc' }
      end

      assert_response :success
      assert_includes sql, "ORDER BY #{expression} DESC NULLS LAST LIMIT"
      assert_equal %w[serde rand], response.parsed_body.map { |package| package['name'] }
    end
  end

  test 'top versions count omits null ordering and keeps descending order' do
    @package.update!(versions_count: 1)
    @registry.packages.create!(ecosystem: 'cargo', name: 'serde', versions_count: 2)

    sql = capture_ordered_query('packages') do
      get top_ecosystem_path(ecosystem: 'cargo'), params: { sort: 'versions_count', order: 'asc' }
    end

    assert_response :success
    assert_match(/ORDER BY versions_count DESC LIMIT/, sql)
    refute_match(/NULLS LAST/i, sql)
    assert_select 'tbody tr td:first-of-type a', text: 'serde'
    assert_equal %w[serde rand], css_select('tbody tr td:first-of-type a').map(&:text)
  end

  def versions_path(action)
    if action == 'recent'
      versions_api_v1_registry_path(id: @registry.name)
    else
      api_v1_registry_package_versions_path(registry_id: @registry.name, package_id: @package.name)
    end
  end

  def capture_ordered_query(table)
    queries = []
    subscriber = lambda do |_name, _start, _finish, _id, payload|
      sql = payload[:sql]
      queries << sql if sql.include?("FROM \"#{table}\"") && sql.include?('ORDER BY') && sql.include?('LIMIT')
    end
    ActiveSupport::Notifications.subscribed(subscriber, 'sql.active_record') { yield }
    assert_equal 1, queries.size, queries.inspect
    queries.first
  end
end
