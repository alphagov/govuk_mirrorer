
require 'govuk_mirrorer/configurer'
require 'govuk_mirrorer/crawler'
require 'govuk_mirrorer/indexer'
require 'govuk_mirrorer/statsd'
require 'govuk_mirrorer/version'

module GovukMirrorer
  def self.run
    crawler = Crawler.new(Configurer.run(ARGV))
    crawler.crawl
  end
end
