
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

task :default => :spec

require "gem_publisher"
desc "Publish gem to RubyGems"
task :publish_gem do |t|
  gem = GemPublisher.publish_if_updated("govuk_mirrorer.gemspec", :rubygems)
  puts "Published #{gem}" if gem
end
