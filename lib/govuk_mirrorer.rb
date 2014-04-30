require 'govuk_mirrorer/net_http_sni_monkey_patch'
require 'govuk_mirrorer/version'

require 'govuk_mirrorer/configurer'
require 'govuk_mirrorer/crawler'
require 'govuk_mirrorer/indexer'
require 'govuk_mirrorer/statsd'

module GovukMirrorer
  def self.run
    crawler = Crawler.new(Configurer.run(ARGV))
    crawler.crawl
  end
end
