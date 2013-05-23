module GovukMirrorer
  class Configurer
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
end
