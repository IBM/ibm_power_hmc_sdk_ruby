require_relative 'lib/ibm_power_hmc/version'

Gem::Specification.new do |spec|
  spec.name          = "ibm_power_hmc"
  spec.version       = IbmPowerHmc::VERSION
  spec.authors       = ["IBM Power"]

  spec.summary       = %q{IBM Power HMC Ruby gem.}
  spec.description   = %q{A Ruby gem for interacting with the IBM Hardware Management Console (HMC).}
  spec.homepage      = "http://github.com/IBM/ibm_power_hmc_sdk_ruby"
  spec.license       = "Apache-2.0"
  spec.required_ruby_version = Gem::Requirement.new(">= 2.3.0")

  spec.metadata["allowed_push_host"] = "https://rubygems.org"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.metadata["source_code_uri"]}/blob/master/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files         = Dir.chdir(File.expand_path('..', __FILE__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_runtime_dependency "rest-client", "~> 2.1"

  spec.add_development_dependency "manageiq-style", "~> 1.3"
  spec.add_development_dependency "rake", "~> 12.0"
end
