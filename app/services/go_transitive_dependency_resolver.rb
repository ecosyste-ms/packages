class GoTransitiveDependencyResolver < TransitiveDependencyResolver
  private

  def select_best_version(matching_versions)
    matching_versions.sort.last
  end
end