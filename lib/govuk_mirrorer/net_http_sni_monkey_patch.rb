require 'net/http'

# Copied from ruby stdlib, with a single line addition to support SNI
# This can be removed once we've upgraded to ruby 1.9.3
# 1.9.2_p290 version: https://github.com/ruby/ruby/blob/v1_9_2_290/lib/net/http.rb#L642
# 1.9.3 version:      https://github.com/ruby/ruby/blob/ruby_1_9_3/lib/net/http.rb#L760

if "1.9.2" == RUBY_VERSION

  module Net

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
