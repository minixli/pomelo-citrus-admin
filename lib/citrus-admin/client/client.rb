# Author:: MinixLi (gmail: MinixLi1986)
# Homepage:: http://citrus.inspawn.com
# Date:: 12 July 2014

module CitrusAdmin
  # Client
  #
  #
  class Client
    include Protocol
    include Utils::EventEmitter

    # Create a new client
    #
    # @param [Hash] args Options
    #
    # @option args [String]  :username
    # @option args [String]  :password
    # @option args [Boolean] :md5
    def initialize args={}
      @client_id = ''
      @req_id = 1
      @callbacks = {}
      @state = :state_inited
      @username = args[:username] || ''
      @password = args[:password] || ''
      @md5 = args[:md5] || false
    end

    # Connect to master server
    #
    # @param [String] client_id
    # @param [String] host
    # @param [String] port
    def connect client_id, host, port, &block
      @client_id = client_id
      @ws = WebSocket::EventMachine::Client.connect :uri => 'ws://' + host + ':' + port.to_s
      @ws.onopen {
        @state = :state_connected
        @password = Utils.md5 @password if @md5
        @ws.send ['register', {
          :type => 'client',
          :client_id => @client_id,
          :username => @username,
          :password => @password,
          :md5 => @md5
        }].to_json
      }
      @ws.onmessage { |msg, type|
        begin
          event, msg = parse msg
          case event
          when 'register'
            process_register_msg msg, &block
          when 'client'
            process_client_msg msg
          else
          end
        rescue => err
        end
      }
      @ws.onclose { |code, reason|
        @state = :state_closed
        emit 'close'
      }
      @ws.onerror { |err|
        if @state == :state_inited
          block_given? and yield err
        end
        emit 'error', err
      }
    end

    # Request master server with callback
    #
    # @param [String] module_id
    # @param [Object] msg
    def request module_id, msg, &block
      req_id = @req_id
      @req_id += 1
      @callbacks[req_id] = block
      msg[:client_id] = @client_id
      msg[:username] = @username
      @ws.send ['client', compose_request(req_id, module_id, msg)].to_json
    end

    # Notify master server without callback
    #
    # @param [String] module_id
    # @param [Object] msg
    def notify module_id, msg
      msg[:client_id] = @client_id
      msg[:username] = @username
      @ws.send ['client', compose_request(nil, module_id, msg)].to_json
    end

    # Command
    #
    # @param [String] command
    # @param [String] module_id
    # @param [Object] msg
    def command command, module_id, msg, &block
      req_id = @req_id
      @req_id += 1
      @callbacks[req_id] = block
      msg[:client_id] = @client_id
      msg[:username] = @username
      @ws.send ['client', compose_command(req_id, command, module_id, msg)].to_json
    end

    private

    # Process register message
    #
    # @param [Object] msg
    #
    # @private
    def process_register_msg msg, &block
      if msg[:code] != PRO_OK
        block_given? and yield msg[:msg]
        return
      end
      @state = :state_registered
      block_given? and yield
    end

    # Process client message
    #
    # @param [Object] msg
    #
    # @private
    def process_client_msg msg
      if resp_id = msg[:resp_id]
        callback = @callbacks[resp_id]
        @callbacks.delete resp_id
        callback.call msg[:err], msg[:body]
      elsif module_id = msg[:module_id]
        emit module_id, msg
      end
    end
  end
end
