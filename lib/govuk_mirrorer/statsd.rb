require "statsd"

module GovukMirrorer
  def self.statsd
    host = "localhost" || ENV["STATSD_HOST"]
    port = 8125 || ENV["STATSD_PORT"]
    Statsd.new(host, port)
  end
end
