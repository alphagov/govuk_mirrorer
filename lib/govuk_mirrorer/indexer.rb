require 'json'
require 'mechanize'

module GovukMirrorer
  class Indexer
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
end
