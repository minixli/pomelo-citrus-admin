# Author:: MinixLi (gmail: MinixLi1986)
# Homepage:: http://citrus.inspawn.com
# Date:: 9 July 2014

module CitrusAdmin
  # MonitorAgent
  #
  #
  class MonitorAgent
    include Protocol
    include Utils::EventEmitter

    # Create a new monitor agent
    #
    # @param [Hash] args Options
    #
    # @option args [Object]  :console_service
    # @option args [String]  :server_id
    # @option args [String]  :server_type
    # @option args [Object]  :server_info
    def initialize args={}
      @console_service = args[:console_service]
      @server_id = args[:server_id]
      @server_type = args[:server_type]
      @server_info = args[:server_info]
      @req_id = 1
      @callbacks = {}
      @state = :state_inited
    end

    # Register and connect to master server
    #
    # @param [Integer] port
    # @param [String]  host
    def connect port, host, &block
      if @state != :state_inited
        return
      end
      begin
        @ws = WebSocket::EventMachine::Client.connect :uri => 'ws://' + host + ':' + port.to_s
        @ws.onopen {
          @state = :state_connected
          event = 'register'
          msg = {
            :type => 'monitor',
            :server_id => @server_id,
            :server_type => @server_type,
            :server_info => @server_info,
            :pid => Process.pid
          }
          @console_service.auth_server.call(msg, @console_service.env) { |token|
            msg[:token] = token
            @ws.send [event, msg].to_json
          }
        }
        @ws.onmessage { |msg, type|
          begin
            event, msg = parse msg
            case event
            when 'register'
              process_register_msg msg, &block
            when 'monitor'
              process_monitor_msg msg
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
          else
            emit 'error', err
          end
        }
      rescue => err
        block_given? and yield err
      end
    end

    # Close the monitor agent
    def close
      return if @state == :state_closed
      @state = :state_closed
      @ws.close
    end

    # Request master server with callback
    #
    # @param [String] module_id
    # @param [Object] msg
    def request module_id, msg, block
      if @state != :state_registered
        return
      end
      req_id = @req_id
      @req_id += 1
      @callbacks[req_id] = block
      @ws.send ['monitor', compose_request(req_id, module_id, msg)].to_json
    end

    # Notify master server without callback
    #
    # @param [String] module_id
    # @param [Object] msg
    def notify module_id, msg
      if @state != :state_registered
        return
      end
      @ws.send ['monitor', compose_request(nil, module_id, msg)].to_json
    end

    private

    # Process register message
    #
    # @param [Object] msg
    #
    # @private
    def process_register_msg msg, &block
      if msg && msg[:code] == PRO_OK
        @state = :state_registered
        block_given? and yield
      else
        emit 'close'
      end
    end

    # Process monitor message
    #
    # @param [Object] msg
    #
    # @private
    def process_monitor_msg msg, &block
      return unless @state == :state_registered
      if msg[:command]
        # command from master server
        @console_service.command(msg[:command], msg[:module_id], msg[:body]) { |err, res|
          # notify should not have a callback
        }
      else
        if resp_id = msg[:resp_id]
          # response from master server
          if !callback = @callbacks[resp_id]
            return
          end
          @callbacks.delete resp_id
          callback.call msg[:err], msg[:body]
          return
        end
        # request from master server
        @console_service.execute(msg[:module_id], 'monitor_handler', msg[:body]) { |err, res|
          if is_request? msg
            @ws.send ['monitor', compose_response(msg, err, res)].to_json
          else
             # notify should not have a callback
          end
        }
      end
    end
  end
end
