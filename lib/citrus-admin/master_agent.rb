# Author:: MinixLi (gmail: MinixLi1986)
# Homepage:: http://citrus.inspawn.com
# Date:: 12 July 2014

module CitrusAdmin
  # MasterAgent
  #
  #
  class MasterAgent
    include Protocol
    include Utils::EventEmitter

    # Create a new master agent
    #
    # @param [Hash] args Options
    #
    # @option args [Object] :console_service
    # @option args [Array]  :white_list
    def initialize args={}
      @console_service = args[:console_service]
      @servers = {}
      @servers_map = {}
      @slaves_map = {}
      @clients = {}
      @req_id = 1
      @callbacks = {}
      @wss = {}
      @white_list = args[:white_list]
      @state = :state_inited
    end

    # Listen to a port and handle register and request
    #
    # @param [Integer] port
    def listen port, &block
      if @state != :state_inited
        return
      end
      @state = :state_started
      begin
        @server = WebSocket::EventMachine::Server.start(:host => '0.0.0.0', :port => port.to_s) { |ws|
          ws_context = {
            # 'monitor' or 'client'
            :type => nil,
            # for monitor connection
            :server_id => nil, :server_type => nil, :server_info => nil,
            # for client connection
            :client_id => nil,
            # for both connection
            :username => nil, :registered => false
          }
          ws.onopen {
            @wss[ws.signature] = ws
            peer_port, peer_host = Socket.unpack_sockaddr_in ws.get_peername
            emit 'connection', { :id => ws.signature, :ip => peer_host }
          }
          ws.onmessage { |msg, type|
            begin
              event, msg = parse msg
              case event
              when 'register'
                process_register_msg ws, ws_context, msg
              when 'monitor'
                process_msg_from_monitor ws, ws_context, msg
              when 'client'
                process_msg_from_client ws, ws_context, msg
              else
              end
            rescue => err
            end
          }
          ws.onclose {
            @wss.delete ws.signature
            if ws_context[:registered]
              case ws_context[:type]
              when 'monitor'
                remove_monitor_connection(ws_context[:server_id],
                  ws_context[:server_type], ws_context[:server_info])
              when 'client'
                remove_client_connection ws_context[:client_id]
              else
              end
              emit 'disconnect', ws_context
            end
          }
          ws.onerror { |err|
            emit 'err', err
          }
        }
        block_given? && yield
      rescue => err
        emit 'error', err
      end
      on('connection') { |obj| ip_filter obj }
    end

    # Close the agent
    def close
      return unless @state == :state_started
      @state = :state_closed
      EM.stop_server @server
    end

    # Get client by id
    #
    # @param [String] client_id
    def get_client_by_id client_id
      @clients[client_id]
    end

    # Request by server id
    #
    # @param [String] server_id
    # @param [String] module_id
    # @param [Object] msg
    # @param [#call]  block
    def request server_id, module_id, msg, block
      return if @state != :state_started
      if !server = @servers[server_id]
        block.call Exception.new 'unknown server id: ' + server_id
        return
      end
      req_id = @req_id
      @req_id += 1
      @callbacks[req_id] = block
      send_msg_to_monitor server[:ws], req_id, module_id, msg
    end

    # Request by server
    #
    # @param [String] server_id
    # @param [Object] server_info
    # @param [String] module_id
    # @param [Object] msg
    # @param [#call]  block
    def request_by_server server_id, server_info, module_id, msg, block
      return if @state != :state_started
      if !server = @servers[server_id]
        block.call Exception.new 'unknown server id: ' + server_id
        return
      end
      req_id = @req_id
      @req_id += 1
      @callbacks[req_id] = block
      if Utils.compare_server server[:server_info], server_info
        send_msg_to_monitor server[:ws], req_id, module_id, msg
      else
        @slaves_map[server_id].each { |server|
          if Utils.compare_server server[:server_info], server_info
            send_msg_to_monitor server[:ws], req_id, module_id, msg
            break
          end
        }
      end
    end

    # Notify server by server id
    #
    # @param [String] server_id
    # @param [String] module_id
    # @param [Object] msg
    def notify server_id, module_id, msg
      return if @state != :state_started
      if !server = @servers[server_id]
        return false
      end
      send_msg_to_monitor server[:ws], nil, module_id, msg
      return true
    end

    # Notify server by server
    #
    # @param [String] server_id
    # @param [Object] server_info
    # @param [String] module_id
    # @param [Object] msg
    def notify_by_server server_id, server_info, module_id, msg
      return if @state != :state_started
      if !server = @servers[server_id]
        return false
      end
      if Utils.compare_server server[:server_info], server_info
        send_msg_to_monitor server[:ws], nil, module_id, msg
      else
        @slaves_map[server_id].each { |server|
          if Utils.compare_server server[:server_info], server_info
            send_msg_to_monitor server[:ws], nil, module_id, msg
            break
          end
        }
      end
      return true
    end

    # Notify by server type
    #
    # @param [String] server_type
    # @param [String] module_id
    # @param [Object] msg
    def notify_by_server_type server_type, module_id, msg
      return if @state != :state_started
      servers = @servers_map[server_type]
      if !servers || servers.empty?
        return false
      end
      broadcast_notify_msg servers, module_id, msg
      return true
    end

    # Notify to slaves
    #
    # @param [String] server_id
    # @param [String] module_id
    # @param [Object] msg
    def notify_to_slaves server_id, module_id, msg
      return if @state != :state_started
      servers = @slaves_map[server_id]
      if !servers || servers.empty?
        return false
      end
      broadcast_notify_msg servers, module_id, msg
      return true
    end

    # Broadcast notify
    #
    # @param [String] module_id
    # @param [Object] msg
    def broadcast_notify module_id, msg
      return if @state != :state_started
      broadcast_notify_msg @servers.values, module_id, msg
    end

    # Broadcast command
    #
    # @param [String] command
    # @param [String] module_id
    # @param [Object] msg
    def broadcast_command command, module_id, msg
      return if @state != :state_started
      broadcast_command_msg @servers.values, command, module_id, msg
    end

    # Notify client
    #
    # @param [String] client_id
    # @param [String] module_id
    # @param [Object] msg
    def notify_client client_id, module_id, msg
      return if @state != :state_started
      if !client = @clients[client_id]
        return
      end
      send_msg_to_client client[:ws], nil, module_id, msg
    end

    private

    # Process register message
    #
    # @param [Object] ws
    # @param [Object] ws_context
    # @param [Object] msg
    #
    # @private
    def process_register_msg ws, ws_context, msg
      return unless msg && msg[:type]
      case msg[:type]
      when 'monitor'
        return unless msg[:server_id]
        ws_context[:type] = msg[:type]
        ws_context[:server_id] = msg[:server_id]
        ws_context[:server_type] = msg[:server_type]
        ws_context[:server_info] = msg[:server_info]
        do_auth_server(msg, ws) { |err|
          if err
            ws.close
            return
          end
          ws_context[:registered] = true
        }
      when 'client'
        ws_context[:type] = msg[:type]
        do_auth_user(msg, ws) { |err|
          if err
            ws.close
            return
          end
          ws_context[:username] = msg[:username]
          ws_context[:registered] = true
        }
      else
        ws.send ['register', {
          :code => PRO_FAIL,
          :msg => 'unknown auth type'
        }].to_json
        ws.close
      end
    end

    # Process message from monitor
    #
    # @param [Object] ws
    # @param [Object] ws_context
    # @param [Object] msg
    #
    # @private
    def process_msg_from_monitor ws, ws_context, msg
      if !ws_context[:registered]
        ws.close
        return
      end
      if ws_context[:type] != 'monitor'
        return
      end
      if resp_id = msg[:resp_id]
        # response from monitor
        callback = @callbacks[resp_id]
        if !callback
          return
        end
        @callbacks.delete resp_id
        callback.call msg[:err], msg[:body]
        return
      end
      # request or notify from monitor
      @console_service.execute(msg[:module_id], :master_handler, msg[:body]) { |err, res|
        if is_request? msg
          if resp = compose_response(msg, err, res)
            ws.send ['monitor', resp].to_json
          end
        else
          # notify should not have a callback
        end
      }
    end

    # Process message from client
    #
    # @param [Object] ws
    # @param [Object] ws_context
    # @param [Object] msg
    #
    # @private
    def process_msg_from_client ws, ws_context, msg
      if !ws_context[:registered]
        ws.close
        return
      end
      if ws_context[:type] != 'client'
        return
      end
      if msg[:command]
        # a command from client
        @console_service.command(msg[:command], msg[:module_id], msg[:body]) { |err, res|
          if is_request? msg
            if resp = compose_response(msg, err, res)
              ws.send ['client', resp].to_json
            end
          else
            # notify should not have a callback
          end
        }
      else
        # a request or a notify from client
        @console_service.execute(msg[:module_id], :client_handler, msg[:body]) { |err, res|
          if is_request? msg
            if resp = compose_response(msg, err, res)
              ws.send ['client', resp].to_json
            end
          else
            # notify should not have a callback
          end
        }
      end
    end

    # Add server connection
    #
    # @param [String]  server_id
    # @param [String]  server_type
    # @param [Object]  server_info
    # @param [Integer] pid
    # @param [Obejct]  ws
    #
    # @private
    def add_monitor_connection server_id, server_type, server_info, pid, ws
      server = {
        :server_id => server_id,
        :server_type => server_type,
        :server_info => server_info,
        :pid => pid,
        :ws => ws
      }
      if !@servers[server_id]
        @servers[server_id] = server
        @servers_map[server_type] ||= []
        @servers_map[server_type] << server
      else
        @slaves_map[server_id] ||= []
        @slaves_map[server_id] << server
      end
      server
    end

    # Add client connection
    #
    # @param [String] client_id
    # @param [Object] user
    # @param [Object] ws
    #
    # @private
    def add_client_connection client_id, user, ws
      client = {
        :client_id => client_id,
        :user_info => user,
        :ws => ws
      }
      @clients[client_id] = client
      client
    end

    # Remove monitor connection
    #
    # @param [String] server_id
    # @param [String] server_type
    # @param [Object] server_info
    #
    # @private
    def remove_monitor_connection server_id, server_type, server_info
      # if Utils.compare_server @servers[server_id][:server_info], server_info
      #   @servers.delete server_id
      #   if @servers_map[server_type]
      #     @servers_map[server_type].delete_if { |server|
      #       server[:server_id] == server_id
      #     }
      #     if @servers_map[server_type].empty?
      #       @servers_map.delete server_type
      #     end
      #   end
      # else
      #   if @slaves_map[server_id]
      #     @slaves_map[server_id].delete_if { |server|
      #       Utils.compare_server server[:server_info], server_info
      #     }
      #     if @slaves_map[server_id].empty?
      #       @slaves_map.delete server_id
      #     end
      #   end
      # end
    end

    # Remove client connection
    #
    # @param [String] client_id
    #
    # @private
    def remove_client_connection client_id
      @clients.delete ws_context[:client_id]
    end

    # Send message to monitor
    #
    # @param [Object]  ws
    # @param [Integer] req_id
    # @param [String]  module_id
    # @param [Object]  msg
    #
    # @private
    def send_msg_to_monitor ws, req_id, module_id, msg
      msg = compose_request req_id, module_id, msg
      ws.send ['monitor', msg].to_json
    end

    # Send message to client
    #
    # @param [Object]  ws
    # @param [Integer] req_id
    # @param [String]  module_id
    # @param [Object]  msg
    #
    # @private
    def send_msg_to_client ws, req_id, module_id, msg
      msg = compose_request req_id, module_id, msg
      ws.send ['client', msg].to_json
    end

    # Broadcast notify message
    #
    # @param [Array]  servers
    # @param [String] module_id
    # @param [Object] msg
    #
    # @private
    def broadcast_notify_msg servers, module_id, msg
      msg = compose_request nil, module_id, msg
      servers.each { |server|
        server[:ws].send ['monitor', msg].to_json
      }
    end

    # Broadcast command message
    #
    # @param [Array]  servers
    # @param [String] command
    # @param [String] module_id
    # @param [Object] msg
    #
    # @private
    def broadcast_command_msg servers, command, module_id, msg
      msg = compose_command nil, command, module_id, msg
      servers.each { |server|
        server[:ws].send ['monitor', msg].to_json
      }
    end

    # Do auth server
    #
    # @param [Object] msg
    # @param [Object] ws
    #
    # @private
    def do_auth_server msg, ws, &block
      if !block_given?
        raise ArgumentError 'expected a code block'
      end
      @console_service.auth_server.call(msg, @console_service.env) { |res|
        if res != 'ok'
          ws.send ['register', {
            :code => PRO_FAIL,
            :msg => 'server auth failed'
          }].to_json
          yield Exception.new 'server auth failed'
          return
        end
        add_monitor_connection msg[:server_id], msg[:server_type], msg[:server_info], msg[:pid], ws
        ws.send ['register', {
          :code => PRO_OK,
          :msg => 'ok'
        }].to_json

        if msg[:server_info]
          msg[:server_info][:pid] = msg[:pid]
          emit 'register', msg[:server_info]
        end

        yield nil
      }
    end

    # Do auth user
    #
    # @param [Object] msg
    # @param [Object] ws
    #
    # @private
    def do_auth_user msg, ws, &block
      if !block_given?
        raise ArgumentError 'expected a code block'
      end
      if !client_id = msg[:client_id]
        yield Exception.new 'client should have a client id'
        return
      end
      if !username = msg[:username]
        ws.send ['register', {
          :code => PRO_FAIL,
          :msg => 'client should auth with username'
        }].to_json
        yield Exception.new 'client should auth with username'
        return
      end
      @console_service.auth_user.call(msg, @console_service.env) { |user|
        if !user
          ws.send ['register', {
            :code => PRO_FAIL,
            :msg => 'client auth failed'
          }].to_json
          yield Exception.new 'client auth failed'
          return
        end
        if @clients[client_id]
          ws.send ['register', {
            :code => PRO_FAIL,
            :msg => 'client id has already been registered'
          }].to_json
          yield Exception.new 'client id has already been registered'
          return
        end
        add_client_connection client_id, user, ws
        ws.send ['register', {
          :code => PRO_OK,
          :msg => 'ok'
        }].to_json
        yield nil
      }
    end

    # ip filter
    #
    # @param [Object] obj
    #
    # @private
    def ip_filter obj
    end
  end
end
