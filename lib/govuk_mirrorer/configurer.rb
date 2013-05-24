module GovukMirrorer
  class Configurer
    class NoRootUrlSpecifiedError < Exception ; end

    def self.run(args)
      require 'optparse'
      options = {
        :site_root => ENV['MIRRORER_SITE_ROOT']
      }
      OptionParser.new do |o|
        o.banner = "Usage: govuk_mirrorer [options]"

        o.on('--site-root URL',
             "Base URL to mirror from",
             "  falls back to MIRRORER_SITE_ROOT env variable") {|root| options[:site_root] = root }
        o.on('--logfile FILE', "Enable logging to a file") { |file| options[:logfile] = file }
        o.on('--loglevel LEVEL', 'DEBUG/INFO/WARN/ERROR, it defaults to INFO') do |level|
          options[:log_level] = level
        end
        o.on('-v', '--verbose', 'sets loglevel to DEBUG') { |level| options[:log_level] = 'DEBUG' }
        o.on('-h', '--help') { puts o; exit }
        o.parse!(args)
      end

      # Error if site_root nil or blank
      raise NoRootUrlSpecifiedError if options[:site_root].nil? or options[:site_root] =~ /\A\s*\z/

      options
    end
  end
end
