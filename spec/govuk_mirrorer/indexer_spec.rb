require 'spec_helper'

describe GovukMirrorer::Indexer do
  let(:no_artefacts) { %({"_response_info":{"status":"ok"},"total":0,"results":[]}) }
  let(:default_root) { "http://giraffe.example" }
  let(:default_api_endpoint) { "http://giraffe.example/api/artefacts.json" }

  before :each do
  end

  describe "construction and loading data" do
    it "should add items to start_urls or blacklist according to format" do
      WebMock.stub_request(:get, default_api_endpoint).
        to_return(:body => {
          "_response_info" => {"status" => "ok"},
          "total" => 4,
          "results" => [
            {"format" => "answer", "web_url" => "http://www.test.gov.uk/foo"},
            {"format" => "local_transaction", "web_url" => "http://www.test.gov.uk/bar/baz"},
            {"format" => "place", "web_url" => "http://www.test.gov.uk/somewhere"},
            {"format" => "guide", "web_url" => "http://www.test.gov.uk/vat"},
          ]
        }.to_json)
      i = GovukMirrorer::Indexer.new(default_root)
      i.all_start_urls.should include("http://www.test.gov.uk/foo")
      i.all_start_urls.should include("http://www.test.gov.uk/vat")
      i.all_start_urls.should_not include("http://www.test.gov.uk/bar/baz")
      i.all_start_urls.should_not include("http://www.test.gov.uk/somewhere")

      i.blacklist_paths.should include("/bar/baz")
      i.blacklist_paths.should include("/somewhere")
      i.blacklist_paths.should_not include("/foo")
      i.blacklist_paths.should_not include("/vat")
    end

    it "should support pagination in the content api" do
      WebMock.stub_request(:get, default_api_endpoint).
        to_return(
          :body => {
            "_response_info" => {"status" => "ok"},
            "total" => 4,
            "results" => [
              {"format" => "answer", "web_url" => "http://www.test.gov.uk/foo"},
              {"format" => "local_transaction", "web_url" => "http://www.test.gov.uk/bar/baz"},
              {"format" => "place", "web_url" => "http://www.test.gov.uk/somewhere"},
              {"format" => "guide", "web_url" => "http://www.test.gov.uk/vat"},
            ]
          }.to_json,
          :headers => {"Link" => "<#{default_api_endpoint}?page=2>; rel=\"next\""}
        )
      WebMock.stub_request(:get, "#{default_api_endpoint}?page=2").
        to_return(
          :body => {
            "_response_info" => {"status" => "ok"},
            "total" => 3,
            "results" => [
              {"format" => "answer", "web_url" => "http://www.test.gov.uk/foo2"},
              {"format" => "local_transaction", "web_url" => "http://www.test.gov.uk/bar/baz2"},
              {"format" => "guide", "web_url" => "http://www.test.gov.uk/vat2"},
            ]
          }.to_json
        )

      i = GovukMirrorer::Indexer.new(default_root)
      i.all_start_urls.should include("http://www.test.gov.uk/foo")
      i.all_start_urls.should include("http://www.test.gov.uk/vat")
      i.all_start_urls.should include("http://www.test.gov.uk/foo2")
      i.all_start_urls.should include("http://www.test.gov.uk/vat2")
      i.all_start_urls.should_not include("http://www.test.gov.uk/bar/baz")
      i.all_start_urls.should_not include("http://www.test.gov.uk/somewhere")
      i.all_start_urls.should_not include("http://www.test.gov.uk/bar/baz2")

      i.blacklist_paths.should include("/bar/baz")
      i.blacklist_paths.should include("/somewhere")
      i.blacklist_paths.should include("/bar/baz2")
      i.blacklist_paths.should_not include("/foo")
      i.blacklist_paths.should_not include("/vat")
      i.blacklist_paths.should_not include("/foo2")
      i.blacklist_paths.should_not include("/vat2")
    end

    it "should add hardcoded whitelist items to the start_urls, even if their format would be blacklisted" do
      WebMock.stub_request(:get, default_api_endpoint).
        to_return(:body => {
          "_response_info" => {"status" => "ok"},
          "total" => 2,
          "results" => [
            {"format" => "custom-application", "web_url" => "http://www.test.gov.uk/bank-holidays"},
            {"format" => "place", "web_url" => "http://www.test.gov.uk/somewhere"},
          ]
        }.to_json)
      i = GovukMirrorer::Indexer.new(default_root)
      i.all_start_urls.should include("http://www.test.gov.uk/bank-holidays")
      i.all_start_urls.should_not include("http://www.test.gov.uk/somewhere")

      i.blacklist_paths.should include("/somewhere")
      i.blacklist_paths.should_not include("/bank-holidays")
    end

    it "should add the hardcoded items to the start_urls" do
      WebMock.stub_request(:get, "https://www.gov.uk/api/artefacts.json").
        to_return(:body => no_artefacts)
      i = GovukMirrorer::Indexer.new("https://www.gov.uk")

      i.all_start_urls.should include("https://www.gov.uk/")
      i.all_start_urls.should include("https://www.gov.uk/designprinciples")
      i.all_start_urls.should include("https://www.gov.uk/designprinciples/styleguide")
      i.all_start_urls.should include("https://www.gov.uk/designprinciples/performanceframework")
    end

    it "should add the hardcoded items to the blacklist" do
      WebMock.stub_request(:get, default_api_endpoint).
        to_return(:body => no_artefacts)
      i = GovukMirrorer::Indexer.new(default_root)

      i.blacklist_paths.should include("/licence-finder")
      i.blacklist_paths.should include("/trade-tariff")
    end

    describe "handling errors fetching artefacts" do
      it "should sleep and retry fetching artefacts on HTTP error" do
        WebMock.stub_request(:get, default_api_endpoint).
          to_return(:status => [502, "Gateway Timeout"]).
          to_return(:body => {
            "_response_info" => {"status" => "ok"},
            "total" => 2,
            "results" => [
              {"format" => "answer", "web_url" => "http://www.test.gov.uk/foo"},
              {"format" => "guide", "web_url" => "http://www.test.gov.uk/vat"},
            ]
          }.to_json)
        GovukMirrorer::Indexer.any_instance.should_receive(:sleep).with(1) # Actually on kernel, but setting the expectation here works

        i = GovukMirrorer::Indexer.new(default_root)

        i.all_start_urls.should include("http://www.test.gov.uk/foo")
        i.all_start_urls.should include("http://www.test.gov.uk/vat")
      end

      it "should only retry once" do
        WebMock.stub_request(:get, default_api_endpoint).
          to_return(:status => [502, "Gateway Timeout"]).
          to_return(:status => [502, "Gateway Timeout"])

        GovukMirrorer::Indexer.any_instance.stub(:sleep) # Make tests fast
        lambda do
          GovukMirrorer::Indexer.new(default_root)
        end.should raise_error(GdsApi::HTTPErrorResponse)
      end
    end
  end

  describe "blacklisted_url?" do
    before :each do
      WebMock.stub_request(:get, "http://www.foo.com/api/artefacts.json").
        to_return(:body => no_artefacts)
      @indexer = GovukMirrorer::Indexer.new("http://www.foo.com")

      @indexer.instance_variable_set('@blacklist_paths', %w(
        /foo/bar
        /something
        /something-else
      ))
    end

    it "should return true if the url has a matching path" do
      @indexer.blacklisted_url?("http://www.foo.com/foo/bar").should == true
    end

    it "should return trus if the url has a matching prefix" do
      @indexer.blacklisted_url?("http://www.foo.com/something/somewhere").should == true
    end

    it "should return false if none match" do
      @indexer.blacklisted_url?("http://www.foo.com/bar").should == false
    end

    it "should return false if only a partial segment matches" do
      @indexer.blacklisted_url?("http://www.foo.com/something-other").should == false
      @indexer.blacklisted_url?("http://www.foo.com/foo/baz").should == false
      @indexer.blacklisted_url?("http://www.foo.com/foo-foo/bar").should == false
    end

    it "should cope with edge-cases passed in" do
      @indexer.blacklisted_url?("mailto:goo@example.com").should == false
      @indexer.blacklisted_url?("http://www.example.com").should == false
      @indexer.blacklisted_url?("ftp://foo:bar@ftp.example.com").should == false
    end
  end
end

