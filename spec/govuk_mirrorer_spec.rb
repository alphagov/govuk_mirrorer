require 'spec_helper'

describe GovukIndexer do
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
      i = GovukIndexer.new(default_root)
      i.all_start_urls.should include("http://www.test.gov.uk/foo")
      i.all_start_urls.should include("http://www.test.gov.uk/vat")
      i.all_start_urls.should_not include("http://www.test.gov.uk/bar/baz")
      i.all_start_urls.should_not include("http://www.test.gov.uk/somewhere")

      i.blacklist_paths.should include("/bar/baz")
      i.blacklist_paths.should include("/somewhere")
      i.blacklist_paths.should_not include("/foo")
      i.blacklist_paths.should_not include("/vat")
    end

    it "should add hardcoded whitelist items to the start_urls, even if their format would be blacklisted" do
      WebMock.stub_request(:get, default_api_endpoint).
        to_return(:body => {
          "_response_info" => {"status" => "ok"},
          "total" => 4,
          "results" => [
            {"format" => "custom-application", "web_url" => "http://www.test.gov.uk/bank-holidays"},
            {"format" => "place", "web_url" => "http://www.test.gov.uk/somewhere"},
          ]
        }.to_json)
      i = GovukIndexer.new(default_root)
      i.all_start_urls.should include("http://www.test.gov.uk/bank-holidays")
      i.all_start_urls.should_not include("http://www.test.gov.uk/somewhere")

      i.blacklist_paths.should include("/somewhere")
      i.blacklist_paths.should_not include("/bank-holidays")
    end

    it "should add the hardcoded items to the start_urls" do
      WebMock.stub_request(:get, "https://www.gov.uk/api/artefacts.json").
        to_return(:body => no_artefacts)
      i = GovukIndexer.new("https://www.gov.uk")

      i.all_start_urls.should include("https://www.gov.uk/")
      i.all_start_urls.should include("https://www.gov.uk/designprinciples")
      i.all_start_urls.should include("https://www.gov.uk/designprinciples/styleguide")
      i.all_start_urls.should include("https://www.gov.uk/designprinciples/performanceframework")
    end

    it "should add the hardcoded items to the blacklist" do
      WebMock.stub_request(:get, default_api_endpoint).
        to_return(:body => no_artefacts)
      i = GovukIndexer.new(default_root)

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
        GovukIndexer.any_instance.should_receive(:sleep).with(1) # Actually on kernel, but setting the expectation here works

        i = GovukIndexer.new(default_root)

        i.all_start_urls.should include("http://www.test.gov.uk/foo")
        i.all_start_urls.should include("http://www.test.gov.uk/vat")
      end

      it "should only retry once" do
        WebMock.stub_request(:get, default_api_endpoint).
          to_return(:status => [502, "Gateway Timeout"]).
          to_return(:status => [502, "Gateway Timeout"])

        GovukIndexer.any_instance.stub(:sleep) # Make tests fast
        lambda do
          GovukIndexer.new(default_root)
        end.should raise_error(Mechanize::ResponseCodeError)
      end
    end
  end

  describe "blacklisted_url?" do
    before :each do
      WebMock.stub_request(:get, "http://www.foo.com/api/artefacts.json").
        to_return(:body => no_artefacts)
      @indexer = GovukIndexer.new("http://www.foo.com")

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

describe GovukMirrorer do
  before :each do
    GovukIndexer.any_instance.stub(:process_artefacts)
    GovukMirrorer.any_instance.stub(:logger).and_return(Logger.new("/dev/null"))
  end

  it 'should have a version number' do
    GovukMirrorer::VERSION.should_not be_nil
  end

  describe "initializing" do

    it "should set the request interval to 0 if not set" do
      m = GovukMirrorer.new
      m.request_interval.should == 0
    end

    it "should handle all urls returned from the indexer" do
      GovukIndexer.any_instance.stub(:all_start_urls).and_return(%w(
        https://www.example.com/
        https://www.example.com/designprinciples
        https://www.example.com/designprinciples/styleguide
        https://www.example.com/designprinciples/performanceframework
      ))
      m = GovukMirrorer.new
      m.urls.should == %w(
        https://www.example.com/
        https://www.example.com/designprinciples
        https://www.example.com/designprinciples/styleguide
        https://www.example.com/designprinciples/performanceframework
      )
    end
  end

  describe "crawl" do
    before :each do
      GovukIndexer.any_instance.stub(:all_start_urls).and_return(%w(
        https://www.example.com/1
        https://www.example.com/2
      ))

      @m = GovukMirrorer.new
      @m.stub(:process_govuk_page)
      @m.send(:agent).stub(:get).and_return("default")
    end

    it "should fetch each page and pass it to the handler" do
      @m.send(:agent).should_receive(:get).with("https://www.example.com/1").ordered.and_return("page_1")
      @m.should_receive(:process_govuk_page).with("page_1", {}).ordered

      @m.send(:agent).should_receive(:get).with("https://www.example.com/2").ordered.and_return("page_2")
      @m.should_receive(:process_govuk_page).with("page_2", {}).ordered

      @m.crawl
    end

    describe "handling errors" do
      it "should call add_log_warning with the relevant details" do
        error = StandardError.new("Boom")
        @m.send(:agent).should_receive(:get).with("https://www.example.com/1").and_raise(error)
        @m.should_receive(:add_log_warning).with(:url => "https://www.example.com/1", :handler => :process_govuk_page, :error => error, :data => {})

        @m.crawl
      end

      it "should continue with the next URL" do
        @m.send(:agent).stub(:get).with("https://www.example.com/1").and_raise("Boom")
        @m.send(:agent).should_receive(:get).with("https://www.example.com/2").and_return("something")

        @m.crawl
      end

      context "error handling" do
        [
          [429, "Too Many Requests"],
          [500, "Internal Server Error"],
          [503, "Boom"],
        ].each do |resp_code, resp_reason|
          context "#{resp_code} #{resp_reason}" do
            it "should sleep for a second, and then retry" do
              error = Mechanize::ResponseCodeError.new(stub("Page", :code => resp_code), resp_reason)
              @m.send(:agent).should_receive(:get).with("https://www.example.com/1").ordered.and_raise(error)
              @m.send(:agent).should_receive(:get).with("https://www.example.com/1").ordered.and_return("page_1")

              @m.should_not_receive(:add_log_warning)
              @m.should_receive(:sleep).with(1) # Actually on kernel, but setting the expectation here works
              @m.should_receive(:process_govuk_page).with("page_1", {})

              @m.crawl
            end

            it "should only retry once" do
              error = Mechanize::ResponseCodeError.new(stub("Page", :code => resp_code), resp_reason)
              @m.send(:agent).should_receive(:get).with("https://www.example.com/1").twice.and_raise(error)

              @m.should_receive(:sleep).with(1) # Actually on kernel, but setting the expectation here works
              @m.should_receive(:add_log_warning).with(:url => "https://www.example.com/1", :handler => :process_govuk_page, :error => error, :data => {}).once

              @m.crawl
            end
          end
        end
      end
    end
  end

  describe "process_govuk_page" do
    before :each do
      @m = GovukMirrorer.new({:site_root => "https://site-under-test"})
      @m.stub(:save_to_disk)
      @m.stub(:extract_and_handle_links)
      @page = stub("Page", :uri => URI.parse("https://site-under-test/something"))
    end

    it "should save the page to disk" do
      @m.should_receive(:save_to_disk).with(@page)
      @m.process_govuk_page(@page)
    end

    it "should extract any links in the page" do
      @m.should_receive(:extract_and_handle_links).with(@page)
      @m.process_govuk_page(@page)
    end

    it "should do nothing if the page is a non gov.uk page" do
      @page.stub(:uri).and_return(URI.parse("https://somewhere.else.com/foo"))
      @m.should_not_receive(:save_to_disk)
      @m.should_not_receive(:extract_and_handle_links)

      @m.process_govuk_page(@page)
    end
  end

  describe "extract_and_handle_links" do
    before :each do
      @m = GovukMirrorer.new
      @m.stub(:process_link)
    end

    it "should extract all <a>, <link> and <script> links from an html page" do
      WebMock.stub_request(:get, "http://www.example.com/foo").
        to_return(
          :headers => {"Content-Type" => "text/html; charset=utf-8"},
          :body => <<-EOT
<!DOCTYPE html>
<html lang="en" class="">
<head>
<link href="https://example.com/static/application.css" media="screen" rel="stylesheet" type="text/css">
<script defer src="https://example.com/static/application.js" type="text/javascript"></script>
<link rel="shortcut icon" href="https://example.com/static/favicon.ico" type="image/x-icon">
<script id="ga-params" type="text/javascript">
  var _gaq = _gaq || [];
  _gaq.push(['_setAccount', 'UA-26179049-1']);
  _gaq.push(['_setAllowLinker', true]);
</script>
</head>
<body class="mainstream">
  <a href="/" title="Go to the gov.uk homepage" id="logo">
    <img src="https://example.com/static/gov.uk_logo.png" alt="GOV.UK Logo">
  </a>
<p>HM Revenue &amp; Customs lists the <a href="http://www.hmrc.gov.uk/vat/forms-rates/rates/goods-services.htm">rates of VAT</a> on different goods and services.</p>
  </body>
</html>
          EOT
        )
      page = Mechanize.new.get("http://www.example.com/foo")

      @m.should_receive(:process_link).with(page, "https://example.com/static/application.css")
      @m.should_receive(:process_link).with(page, "https://example.com/static/application.js")
      @m.should_receive(:process_link).with(page, "https://example.com/static/favicon.ico")
      @m.should_receive(:process_link).with(page, "/")
      @m.should_receive(:process_link).with(page, "https://example.com/static/gov.uk_logo.png")
      @m.should_receive(:process_link).with(page, "http://www.hmrc.gov.uk/vat/forms-rates/rates/goods-services.htm")
      @m.should_receive(:process_link).never # None except for the ones above

      @m.extract_and_handle_links(page)
    end

    it "should not attempt to extract links from non-html pages" do
      WebMock.stub_request(:get, "http://www.example.com/foo.xml").
        to_return(
          :headers => {"Content-Type" => "application/xml; charset=utf-8"},
          :body => %(<?xml version="1.0" encoding="UTF-8"?>\n<foo></foo>))
      page = Mechanize.new.get("http://www.example.com/foo.xml")

      @m.should_not_receive(:process_link)
      page.should_not_receive(:search)

      @m.extract_and_handle_links(page)
    end
  end

  describe "rules for deciding if a URL should be mirrored" do
    before :each do
      @m = GovukMirrorer.new
      @m.stub(:spidey_handle)

      @page = stub("Page", :uri => URI.parse("https://www.gov.uk/foo/bar"))
    end

    it "should convert relative links to full links" do
      @m.should_receive(:spidey_handle).with("https://www.gov.uk/baz", :process_govuk_page, :referrer => "https://www.gov.uk/foo/bar")
      @m.process_link(@page, "/baz")

      @m.should_receive(:spidey_handle).with("https://www.gov.uk/foo/baz", :process_govuk_page, :referrer => "https://www.gov.uk/foo/bar")
      @m.process_link(@page, "baz")
    end

    it "should convert www.gov.uk http links to https" do
      @m.should_receive(:spidey_handle).with("https://www.gov.uk/something", :process_govuk_page, :referrer => "https://www.gov.uk/foo/bar")
      @m.process_link(@page, "http://www.gov.uk/something")
    end

    it "should pass through https www.gov.uk links" do
      @m.should_receive(:spidey_handle).with("https://www.gov.uk/something", :process_govuk_page, :referrer => "https://www.gov.uk/foo/bar")
      @m.process_link(@page, "https://www.gov.uk/something")
    end

    it "should reject any urls with query params" do
      @m.should_not_receive(:spidey_handle).with("https://www.gov.uk/something?foo=bar&baz=foo", :process_govuk_page, :referrer => "https://www.gov.uk/foo/bar")
      @m.process_link(@page, "https://www.gov.uk/something?foo=bar&baz=foo")
    end

    it "should remove any fragments (anchors) from the link" do
      @m.should_receive(:spidey_handle).with("https://www.gov.uk/something", :process_govuk_page, :referrer => "https://www.gov.uk/foo/bar")
      @m.process_link(@page, "https://www.gov.uk/something#foo")
    end

    it "should ignore non www.gov.uk links" do
      @m.should_not_receive(:spidey_handle)

      @m.process_link(@page, "https://direct.gov.uk/something")
      @m.process_link(@page, "http://transactionalservices.alphagov.co.uk/department/dfid?orderBy=nameOfService&direction=desc&format=csv")
    end

    it "should ignore mailto links" do
      @m.should_not_receive(:spidey_handle)

      @m.process_link(@page, "mailto:me@example.com")
      @m.process_link(@page, "mailto:someone@www.gov.uk")
    end
  end
end

describe GovukMirrorConfigurer do
  it "should fail if MIRRORER_SITE_ROOT is not set" do
    lambda do
      GovukMirrorConfigurer.run
    end.should raise_error(GovukMirrorConfigurer::NoRootUrlSpecifiedError)
  end

  it "should place the site root into the options bucket even though it sucks" do
    ENV["MIRRORER_SITE_ROOT"] = "sausage"
    GovukMirrorConfigurer.run.should include(:site_root => "sausage" )
  end
end
