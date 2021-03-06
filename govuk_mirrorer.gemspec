# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'govuk_mirrorer/version'

Gem::Specification.new do |spec|
  spec.name          = "govuk_mirrorer"
  spec.version       = GovukMirrorer::VERSION
  spec.authors       = ["Alex Tomlins"]
  spec.email         = ["alex.tomlins@digital.cabinet-office.gov.uk"]
  spec.summary       = %q{Tool to generate a static version of GOV.UK}
  spec.description   = spec.summary
  spec.homepage      = ""
  spec.license       = "MIT"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_dependency "spidey", "0.0.4"
  spec.add_dependency "mechanize", "2.5.1"
  spec.add_dependency "syslogger", "1.4.2"
  spec.add_dependency "gds-api-adapters", "8.4.0"
  spec.add_dependency "statsd-ruby", "1.2.1"

  spec.add_development_dependency "bundler", "~> 1.1"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "rspec"
  spec.add_development_dependency "webmock"
  spec.add_development_dependency "gem_publisher", "1.2.0"
end
