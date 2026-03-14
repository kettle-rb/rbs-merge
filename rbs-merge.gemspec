# coding: utf-8
# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name = "rbs-merge"
  spec.version = Module.new.tap { |mod| Kernel.load("#{__dir__}/lib/rbs/merge/version.rb", mod) }::Rbs::Merge::Version::VERSION
  spec.authors = ["Peter H. Boling"]
  spec.email = ["floss@galtzo.com"]

  spec.summary = "☯️ Smart merge for RBS type signature files using AST analysis"
  spec.description = "☯️ Intelligently merge RBS type signature files by parsing and comparing AST structures. Supports freeze blocks to protect customizations, signature-based matching, and configurable merge strategies."
  spec.homepage = "https://github.com/kettle-rb/rbs-merge"
  spec.licenses = ["MIT"]
  spec.required_ruby_version = ">= 3.2.0"

  # Linux distros often package gems and securely certify them independent
  #   of the official RubyGem certification process. Allowed via ENV["SKIP_GEM_SIGNING"]
  # Ref: https://gitlab.com/ruby-oauth/version_gem/-/issues/3
  # Hence, only enable signing if `SKIP_GEM_SIGNING` is not set in ENV.
  # See CONTRIBUTING.md
  unless ENV.include?("SKIP_GEM_SIGNING")
    user_cert = "certs/#{ENV.fetch("GEM_CERT_USER", ENV["USER"])}.pem"
    cert_file_path = File.join(__dir__, user_cert)
    cert_chain = cert_file_path.split(",")
    cert_chain.select! { |fp| File.exist?(fp) }
    if cert_file_path && cert_chain.any?
      spec.cert_chain = cert_chain
      if $PROGRAM_NAME.end_with?("gem") && ARGV[0] == "build"
        spec.signing_key = File.join(Gem.user_home, ".ssh", "gem-private_key.pem")
      end
    end
  end

  spec.metadata["homepage_uri"] = "https://#{spec.name.tr("_", "-")}.galtzo.com/"
  spec.metadata["source_code_uri"] = "#{spec.homepage}/tree/v#{spec.version}"
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/v#{spec.version}/CHANGELOG.md"
  spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues"
  spec.metadata["documentation_uri"] = "https://www.rubydoc.info/gems/#{spec.name}/#{spec.version}"
  spec.metadata["funding_uri"] = "https://github.com/sponsors/pboling"
  spec.metadata["wiki_uri"] = "#{spec.homepage}/wiki"
  spec.metadata["news_uri"] = "https://www.railsbling.com/tags/#{spec.name}"
  spec.metadata["discord_uri"] = "https://discord.gg/3qme4XHNKN"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files are part of the released package.
  spec.files = Dir[
    # Code / tasks / data (NOTE: exe/ is specified via spec.bindir and spec.executables below)
    "lib/**/*.rb",
    "lib/**/*.rake",
    # Signatures
    "sig/**/*.rbs",
  ]

  # Automatically included with gem package, no need to list again in files.
  spec.extra_rdoc_files = Dir[
    # Files (alphabetical)
    "CHANGELOG.md",
    "CITATION.cff",
    "CODE_OF_CONDUCT.md",
    "CONTRIBUTING.md",
    "FUNDING.md",
    "LICENSE.txt",
    "README.md",
    "REEK",
    "RUBOCOP.md",
    "SECURITY.md",
  ]
  spec.rdoc_options += [
    "--title",
    "#{spec.name} - #{spec.summary}",
    "--main",
    "README.md",
    "--exclude",
    "^sig/",
    "--line-numbers",
    "--inline-source",
    "--quiet",
  ]
  spec.require_paths = ["lib"]
  spec.bindir = "exe"
  # Listed files are the relative paths from bindir above.
  spec.executables = []

  # Parser - tree_haver provides unified tree-sitter & citrus interface
  spec.add_dependency("tree_haver", "~> 5.0", ">= 5.0.5")                           # ruby >= 3.2.0

  # Shared merge infrastructure
  spec.add_dependency("ast-merge", "~> 4.0", ">= 4.0.5")                # ruby >= 3.2.0

  # Utilities
  spec.add_dependency("version_gem", "~> 1.1", ">= 1.1.9")              # ruby >= 2.2.0

  # Keep development dependencies here when they match the current project Ruby.
  # Put stricter tooling constraints in modular gemfiles.

  # Dev, Test, & Release Tasks
  spec.add_development_dependency("kettle-dev", "~> 2.0")                           # ruby >= 2.3.0

  # Security
  spec.add_development_dependency("bundler-audit", "~> 0.9.2")                      # ruby >= 2.0.0

  # Tasks
  spec.add_development_dependency("rake", "~> 13.0")                                # ruby >= 2.2.0

  # Debugging
  spec.add_development_dependency("require_bench", "~> 1.0", ">= 1.0.4")            # ruby >= 2.2.0

  # Testing
  spec.add_development_dependency("appraisal2", "~> 3.0")
  spec.add_development_dependency("kettle-test", "~> 1.0", ">= 1.0.6")              # ruby >= 2.3

  # Releasing
  spec.add_development_dependency("ruby-progressbar", "~> 1.13")                    # ruby >= 0
  spec.add_development_dependency("stone_checksums", "~> 1.0", ">= 1.0.2")          # ruby >= 2.2.0

  # Git integration (optional)
  # spec.add_dependency("git", ">= 1.19.1")                               # ruby >= 2.3

  spec.add_development_dependency("gitmoji-regex", "~> 1.0", ">= 1.0.3")            # ruby >= 2.3.0

  # Optional HTTP-recording dependencies for deterministic specs
  # spec.add_development_dependency("vcr", ">= 4")
  # spec.add_development_dependency("webmock", ">= 3")
end
