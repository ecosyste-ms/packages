require 'test_helper'
require_relative '../../lib/corpus/selection'

class CorpusSelectionTest < ActiveSupport::TestCase
  class Database
    attr_reader :rows, :sample, :small
    def initialize(rows, sample: [], small: false)
      @rows, @sample, @small = rows, sample, small
    end
    def catalog
      {'estimated_rows'=>100_000}
    end
    def read(sql, **)
      return [{'id'=>1,'name'=>'example.org','packages_count'=>small ? rows.size : 100_000}] if sql.start_with?('SELECT * FROM registries')
      return sample.map { |id| {'id'=>id,'registry_id'=>1} } if sql.include?('TABLESAMPLE')
      return rows if sql.start_with?('SELECT id, downloads AS downloads')
      metric=Corpus::Selection::METRICS.find { |m| sql.include?(m) }
      raise sql unless metric
      rows.select { |r| r[metric] && r[metric]>0 }.sort_by { |r| [-r[metric],r['id']] }.first(sql[/LIMIT (\d+)/,1].to_i).map { |r| {'id'=>r['id'],'value'=>r[metric]} }
    end
  end

  def test_usage_selection_rejects_shared_repository_popularity_and_caps_background_fill
    rows=[{'id'=>1,'downloads'=>5}, {'id'=>2,'downloads'=>nil,'stargazers_count'=>100_000,'forks_count'=>10_000}, {'id'=>3,'downloads'=>0,'stargazers_count'=>100_000}]
    rows.concat((100..199).map { |id| {'id'=>id,'downloads'=>nil,'stargazers_count'=>100_000} })
    selector=Corpus::Selection.new(database:Database.new(rows,sample:(100..199).to_a),target:20,head_limit:500,census_limit:0)
    ids=selector.run
    assert_includes ids,1
    refute_includes ids,2
    refute_includes ids,3
    assert_equal 3,ids.size
    assert_equal 2,selector.selected.values.count { |r| r[:reason]=='background_outside99' }
    assert_equal [1],selector.report[:package_usage_registries]
    refute selector.report[:signals].find { |r| r[:signal]=='stargazers_count' }[:selection_eligible]
    assert_equal ids,Corpus::Selection.new(database:Database.new(rows,sample:(100..199).to_a),target:20,head_limit:500,census_limit:0).run
  end

  def test_registry_without_download_observations_keeps_repository_selection
    selector=Corpus::Selection.new(database:Database.new([{'id'=>2,'downloads'=>nil,'stargazers_count'=>100_000}]),target:20,census_limit:0)
    assert_equal [2],selector.run
    assert_empty selector.report[:package_usage_registries]
  end

  def test_small_registry_census_keeps_low_and_missing_usage
    rows=[{'id'=>1,'downloads'=>5}, {'id'=>2,'downloads'=>nil,'stargazers_count'=>100_000}, {'id'=>3,'downloads'=>0}]
    selector=Corpus::Selection.new(database:Database.new(rows,small:true),target:20)
    assert_equal [1,2,3],selector.run
    assert_empty selector.report[:package_usage_registries]
  end
end
