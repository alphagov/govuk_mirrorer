require 'spec_helper'

describe GovukMirrorer do

  describe "top-level run method" do
    it "should construct a new crawler with the configuration, and start it" do
      GovukMirrorer::Configurer.should_receive(:run).and_return(:a_config_hash)
      stub_crawler = stub("GovukMirrorer::Crawler")
      GovukMirrorer::Crawler.should_receive(:new).with(:a_config_hash).and_return(stub_crawler)
      stub_crawler.should_receive(:crawl)

      GovukMirrorer.run
    end
  end
end
