# frozen_string_literal: true

# HOW TO UPDATE APPRAISALS (will run rubocop_gradual's autocorrect afterward):
#   bin/rake appraisal:update

# Appraisal entries are maintenance helpers only.
# They do not replace the main local sibling-development flow.
appraise "unlocked_deps" do
  eval_gemfile "modular/coverage.gemfile"
  eval_gemfile "modular/documentation.gemfile"
  eval_gemfile "modular/optional.gemfile"
  eval_gemfile "modular/rspec.gemfile"
  eval_gemfile "modular/style.gemfile"
  eval_gemfile "modular/x_std_libs.gemfile"
end

appraise "head" do
  eval_gemfile "modular/rspec.gemfile"
  eval_gemfile "modular/x_std_libs.gemfile"
end

appraise "current" do
  eval_gemfile "modular/rspec.gemfile"
  eval_gemfile "modular/x_std_libs.gemfile"
end

# Test current Rubies against head versions of runtime dependencies
appraise "dep-heads" do
  eval_gemfile "modular/rspec.gemfile"
  eval_gemfile "modular/runtime_heads.gemfile"
end

appraise "ruby-3-2" do
  eval_gemfile "modular/rspec.gemfile"
  eval_gemfile "modular/x_std_libs/r3/libs.gemfile"
end

appraise "ruby-3-3" do
  eval_gemfile "modular/rspec.gemfile"
  eval_gemfile "modular/x_std_libs/r3/libs.gemfile"
end

# Only run security audit on the latest version of Ruby
appraise "audit" do
  eval_gemfile "modular/x_std_libs.gemfile"
end

# Only run coverage on the latest version of Ruby
appraise "coverage" do
  eval_gemfile "modular/coverage.gemfile"
  eval_gemfile "modular/optional.gemfile"
  eval_gemfile "modular/rspec.gemfile"
  eval_gemfile "modular/x_std_libs.gemfile"
end

# Only run linter on the latest version of Ruby (but, in support of oldest supported Ruby version)
appraise "style" do
  eval_gemfile "modular/style.gemfile"
  eval_gemfile "modular/x_std_libs.gemfile"
end
