require "govuk_mirrorer/version"
#!/usr/bin/env ruby

require 'net/http'

# Copied from ruby stdlib, with a single line addition to support SNI
# This can be removed once we've upgraded to ruby 1.9.3
# 1.9.2_p290 version: https://github.com/ruby/ruby/blob/v1_9_2_290/lib/net/http.rb#L642
# 1.9.3 version:      https://github.com/ruby/ruby/blob/ruby_1_9_3/lib/net/http.rb#L760

module Net

  if "1.9.2" == RUBY_VERSION

    HTTP.class_eval do
      def connect
        D "opening connection to #{conn_address()}..."
        s = timeout(@open_timeout) { TCPSocket.open(conn_address(), conn_port()) }
        D "opened"

        if use_ssl?
          ssl_parameters = Hash.new
          iv_list = instance_variables
          SSL_ATTRIBUTES.each do |name|
            ivname = "@#{name}".intern
            if iv_list.include?(ivname) and
               value = instance_variable_get(ivname)
              ssl_parameters[name] = value
            end
          end
          @ssl_context = OpenSSL::SSL::SSLContext.new
          @ssl_context.set_params(ssl_parameters)
          s = OpenSSL::SSL::SSLSocket.new(s, @ssl_context)
          s.sync_close = true
        end

        @socket = BufferedIO.new(s)
        @socket.read_timeout = @read_timeout
        @socket.debug_output = @debug_output
        if use_ssl?
          begin
            if proxy?
              @socket.writeline sprintf('CONNECT %s:%s HTTP/%s',
                                        @address, @port, HTTPVersion)
              @socket.writeline "Host: #{@address}:#{@port}"
              if proxy_user
                credential = ["#{proxy_user}:#{proxy_pass}"].pack('m')
                credential.delete!("\r\n")
                @socket.writeline "Proxy-Authorization: Basic #{credential}"
              end
              @socket.writeline ''
              HTTPResponse.read_new(@socket).value
            end

            # This is the only line that's different from the ruby method
            # Server Name Indication (SNI) RFC 3546
            s.hostname = @address if s.respond_to? :hostname=

            timeout(@open_timeout) { s.connect }
            if @ssl_context.verify_mode != OpenSSL::SSL::VERIFY_NONE
              s.post_connection_check(@address)
            end
          rescue => exception
            D "Conn close because of connect error #{exception}"
            @socket.close if @socket and not @socket.closed?
            raise exception
          end
        end
        on_connect
      end
    end

  end
end

require 'rubygems'
require 'mechanize'
require 'json'
require 'spidey'
require 'syslogger'

class GovukIndexer
  FORMATS_TO_503 = %w(
    local_transaction
    smart-answer
    custom-application
    place
    licence
  ).freeze

  ADDITIONAL_START_PATHS = %w(
    /
    /designprinciples
    /designprinciples/styleguide
    /designprinciples/performanceframework
  ).freeze

  # Calendars currently register as custom-application
  WHITELIST_PATHS = %w(
    /bank-holidays
    /when-do-the-clocks-change
  ).freeze

  ADDITIONAL_BLACKLIST_PATHS = %w(
    /trade-tariff
    /licence-finder
    /business-finance-support-finder
    /government/uploads
    /apply-for-a-licence
    /search
  ).freeze

  def initialize(root)
    @root = root
    @api_endpoint = @root + '/api/artefacts.json'
    @all_start_urls = ADDITIONAL_START_PATHS.map{ |x| @root + x}
    @blacklist_paths = ADDITIONAL_BLACKLIST_PATHS.dup
    process_artefacts
  end

  attr_reader :all_start_urls, :blacklist_paths

  def blacklisted_url?(url)
    path = URI.parse(url).path
    return false if path.nil? # e.g. mailto: links...
    url_segments = path.sub(%r{\A/}, '').split('/')
    @blacklist_paths.any? do |blacklist_path|
      bl_segments = blacklist_path.sub(%r{\A/}, '').split('/')
      url_segments[0..(bl_segments.length - 1)] == bl_segments
    end
  end

  private

  def process_artefacts
    artefacts.each do |artefact|
      uri = URI.parse(artefact["web_url"])
      if WHITELIST_PATHS.include?(uri.path)
        @all_start_urls << artefact["web_url"]
      elsif FORMATS_TO_503.include?(artefact["format"])
        @blacklist_paths << URI.parse(artefact["web_url"]).path
      else
        @all_start_urls << artefact["web_url"]
      end
    end
  end

  def artefacts
    retried = false
    @artefacts ||= begin
      m = Mechanize.new
      # Force Mechanize to use Net::HTTP which we've monkey-patched above
      m.agent.http.reuse_ssl_sessions = false
      page = m.get(@api_endpoint)
      JSON.parse(page.body)["results"]
    rescue Mechanize::ResponseCodeError => ex
      if ! retried
        retried = true
        sleep 1
        retry
      end
      raise
    end
  end
end

class GovukMirrorer < Spidey::AbstractSpider
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

    @indexer = GovukIndexer.new(@site_root)
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

class GovukMirrorConfigurer
  class NoRootUrlSpecifiedError < Exception ; end

  def self.run
    require 'optparse'
    options = {}
    OptionParser.new do |o|
      o.banner = "Usage: govuk_mirrorer [options]"

      o.on('--logfile FILE') { |file| options[:logfile] = file }
      o.on('--loglevel LEVEL', 'DEBUG/INFO/WARN/ERROR, it defaults to INFO') do |level|
        options[:log_level] = level
      end
      o.on('-v', '--verbose', 'makes loglevel as DEBUG') { |level| options[:log_level] = 'DEBUG' }
      o.on('-h', '--help') { puts o; exit }
      o.parse!
    end

    if ENV['MIRRORER_SITE_ROOT'].nil?
      raise NoRootUrlSpecifiedError
    end
    options[:site_root] = ENV['MIRRORER_SITE_ROOT']
    options
  end
end

if $0 == __FILE__
  mirrorer = GovukMirrorer.new(GovukMirrorConfigurer.run)
  mirrorer.crawl
end
