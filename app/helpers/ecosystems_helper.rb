module EcosystemsHelper
  
  def github_repo_name
    ENV['GITHUB_REPO_NAME'] || request.subdomains.first || Rails.application.class.module_parent_name.underscore
  end

  def ecosystems_services
    {
      "Data" => [
        {
          name: "Packages",
          url: "https://packages.ecosyste.ms"
        },
        {
          name: "Repositories",
          url: "https://repos.ecosyste.ms"
        },
        {
          name: "Advisories",
          url: "https://advisories.ecosyste.ms"
        }
      ],
      "Tools" => [
        {
          name: "Dependency Parser",
          url: "https://parser.ecosyste.ms"
        },
        {
          name: "Dependency Resolver",
          url: "https://resolve.ecosyste.ms"
        },
        {
          name: "SBOM Parser",
          url: "https://sbom.ecosyste.ms"
        },
        {
          name: "License Parser",
          url: "https://licenses.ecosyste.ms",
        },
        {
          name: "Digest",
          url: "https://digest.ecosyste.ms"
        },
        {
          name: "Archives",
          url: "https://archives.ecosyste.ms"
        },
        {
          name: "Diff",
          url: "https://diff.ecosyste.ms"
        },
        {
          name: "Summary",
          url: "https://summary.ecosyste.ms"
        }
      ],
      "Indexes" => [
        {
          name: "Timeline",
          url: "https://timeline.ecosyste.ms"
        },
        {
          name: "Commits",
          url: "https://commits.ecosyste.ms"
        },
        {
          name: "Issues",
          url: "https://issues.ecosyste.ms"
        },
        {
          name: "Sponsors",
          url: "https://sponsors.ecosyste.ms"
        },
        {
          name: "Docker",
          url: "https://docker.ecosyste.ms"
        },
        {
          name: "Open Collective",
          url: "https://opencollective.ecosyste.ms"
        },
        {
          name: "Dependabot",
          url: "https://dependabot.ecosyste.ms"
        }
      ],
      "Applications" => [
        {
          name: "Funds",
          url: "https://funds.ecosyste.ms"
        },
        {
          name: "Dashboards",
          url: "https://dashboards.ecosyste.ms"
        },
      ],
      "Experiments" => [
        {
          name: "OST",
          url: "https://ost.ecosyste.ms"
        },
        {
          name: "Papers",
          url: "https://papers.ecosyste.ms"
        },
        {
          name: "Awesome",
          url: "https://awesome.ecosyste.ms"
        },
        {
          name: "Ruby",
          url: "https://ruby.ecosyste.ms"
        }
      ]
    }
  end
  
end