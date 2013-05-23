require 'spidey'
require 'mechanize'
require 'syslogger'

module GovukMirrorer
  class Crawler < Spidey::AbstractSpider
    USER_AGENT = "GOV.UK Mirrorer/0.1"
    DEFAULT_SITE_ROOT = 'https://www.gov.uk'
    RETRY_RESP_CODES = [429, (500..599).to_a].flatten

    def initialize(attrs = {})
      attrs[:request_interval] ||= 0
      super
      setup_agent
      @http_errors = {}

      # Syslog settings
      # programname: govuk_mirrorer
      # options: Syslog::LOG_PID | Syslog::LOG_CONS
      # facility: local3
      # Syslog::LOG_PID - adds the process number to the message (just after the program name)
      # Syslog::LOG_CONS - writes the message on the console if an error occurs when sending the message
      @logger = Syslogger.new('govuk_mirrorer', Syslog::LOG_PID | Syslog::LOG_CONS, Syslog::LOG_LOCAL3)

      if attrs[:log_level]
        @logger.level = Logger.const_get(attrs[:log_level].upcase)
      else
        @logger.level = Logger::INFO
      end

      @site_root = attrs[:site_root] || DEFAULT_SITE_ROOT

      @indexer = GovukMirrorer::Indexer.new(@site_root)
      @indexer.all_start_urls.each do |url|
        @logger.debug "Adding start url #{url}"
        handle url, :process_govuk_page
      end
    end

    def site_hostname
      URI.parse(@site_root).host
    end

    attr_accessor :logger

    def crawl(options = {})
      each_url do |url, handler, default_data|
        retried = false
        begin
          page = agent.get(url)
          logger.debug "Handling #{url.inspect}"
          send handler, page, default_data
        rescue => ex
          if ex.is_a?(Mechanize::ResponseCodeError) and RETRY_RESP_CODES.include?(ex.response_code.to_i) and ! retried
            retried = true
            sleep 1
            retry
          end
          add_log_warning url: url, handler: handler, error: ex, data: default_data
        end
      end
      logger.info "Completed crawling the site"
    end

    def process_govuk_page(page, data = {})
      unless page.uri.host == site_hostname
        msg = "Ended up on non #{site_hostname} page #{page.uri.to_s}"
        msg << " from #{agent.history[-2].uri.to_s}" if agent.history[-2]
        logger.warn msg
        return
      end
      save_to_disk(page)
      extract_and_handle_links(page)
    end

    def extract_and_handle_links(page)
      if page.is_a?(Mechanize::Page)
        page.search("//a[@href]").each do |elem|
          process_link(page, elem["href"])
        end
        page.search("//img[@src]").each do |elem|
          process_link(page, elem["src"])
        end
        page.search("//link[@href]").each do |elem|
          process_link(page, elem["href"])
        end
        page.search("//script[@src]").each do |elem|
          process_link(page, elem["src"])
        end
      end
    end

    def process_link(page, href)
      uri = URI.parse(href)
      if uri.scheme.nil? # relative link
        uri = URI.join(page.uri.to_s, href)
      elsif uri.host == site_hostname
        logger.warn "Link to non https #{href} from #{page.uri.to_s}" unless uri.scheme == "https"
        uri.scheme = 'https'
      else
        logger.debug "Ignoring non #{site_hostname} link #{href} on #{page.uri.to_s}"
        return
      end
      uri.fragment = nil # prevent duplicate url's being missed
      maybe_handle uri.to_s, :process_govuk_page, :referrer => page.uri.to_s
    rescue URI::Error => ex
      logger.warn "#{ex.class} parsing url #{href} on page #{page.uri.to_s}"
    end

    def maybe_handle(url, handler, data = {})
      logger.debug "Evaluating link #{url}"
      if @urls.include?(url)
        logger.debug "Skipping seen url #{url}"
        return
      end
      if @http_errors.has_key?(url)
        logger.debug "Skipping previous erroring url #{url}"
        return
      end
      if @indexer.blacklisted_url?(url)
        logger.debug "Skipping blacklisted url #{url}"
        return
      end
      if url.include? '?'
        logger.debug "Skipping querystringed url #{url}"
        return
      end
      logger.debug "Adding url #{url} from #{data[:referrer]}"
      spidey_handle url, handler, data
    end

    def spidey_handle (url, handler, data)
      handle url, handler, data
    end

    protected

    def add_log_warning(attrs)
      msg = "Error #{attrs[:error].inspect} for #{attrs[:url]}, data: #{attrs[:data].inspect}"
      msg << "\n#{attrs[:error].backtrace.join("\n")}" unless attrs[:error].is_a?(Mechanize::Error)
      logger.warn msg.to_s
      @http_errors[attrs[:url]] = attrs[:error]
    end

    private

    # Saves to a file in ./hostname/path
    # adds .html for html files
    def save_to_disk(page)
      path = page.extract_filename(true)
      logger.debug "Saving #{page.uri.to_s} to #{path}"
      FileUtils.mkdir_p(File.dirname(path))
      File.open(path, 'wb') do |f|
        f.write page.body
      end
    end

    def setup_agent
      agent.user_agent = USER_AGENT
      agent.request_headers["X-Govuk-Mirrorer"] = "1"
      # Force Mechanize to use Net::HTTP which we've monkey-patched above
      agent.agent.http.reuse_ssl_sessions = false
    end
  end
end
