# Author:: MinixLi (gmail: MinixLi1986)
# Homepage:: http://citrus.inspawn.com
# Date:: 8 July 2014

require 'citrus-admin/master_agent'
require 'citrus-admin/monitor_agent'

module CitrusAdmin
  # ConsoleService
  #
  #
  class ConsoleService
    include Protocol
    include Utils; include Utils::EventEmitter

    attr_reader :env, :master, :agent, :auth_user, :auth_server

    # Create a new console service
    #
    # @param [Hash] args Options
    #
    # @option args [Boolean] :master
    # @option args [String]  :host
    # @option args [Integer] :port
    # @option args [String]  :server_id
    # @option args [String]  :server_type
    # @option args [Object]  :server_info
    # @option args [#call]   :auth_user
    # @option args [#call]   :auth_server
    def initialize args={}
      @env = args[:env]
      @master = args[:master]
      @port = args[:port]
      @console_modules = {}
      @commands = {
        :list => methods(:list_command),
        :enable => methods(:enable_command),
        :disable => methods(:disable_command)
      }
      if @master
        @auth_user = args[:auth_user] || method(:df_auth_user)
        @auth_server = args[:auth_server] || method(:df_auth_server_master)
        args[:console_service] = self
        @agent = MasterAgent.new args
      else
        @host = args[:host]
        @server_id = args[:server_id]
        @server_type = args[:server_type]
        @auth_server = args[:auth_server] || method(:df_auth_server_monitor)
        @agent = MonitorAgent.new({
          :console_service => self,
          :server_id => @server_id,
          :server_type => @server_type,
          :server_info => args[:server_info]
        })
      end
    end

    # Start master agent or monitor agent
    def start &block
      if @master
        @agent.listen(@port) { |err|
          if err
            block_given? and yield err
            return
          end

          @agent.on('register') { |*args| emit 'register', *args }
          @agent.on('disconnect') { |*args| emit 'disconnect', *args }
          @agent.on('reconnect') { |*args| emit 'reconnect', *args }

          EM.next_tick {
            block_given? and yield
          }
        }
      else
        @agent.connect @port, @host, &block
      end
      @console_modules.each { |module_id, console_module|
        enable_module module_id
      }
    end

    # Stop master agent or monitor agent
    def stop
      @console_modules.each { |module_id, console_module|
        disable_module module_id
      }
      @agent.close
    end

    # Register console module
    #
    # @param [String] module_id
    # @param [Object] module_entity
    def register module_id, module_entity
      console_module = {
        :module_id => module_id,
        :module_entity => module_entity,
        :enable => false
      }

      if type = module_entity.type
        if @master && type == 'pull' || !@master && type == 'push'
          delay = module_entity.delay
          interval = module_entity.interval
          console_module[:delay] = delay ? (delay > 0 ? delay : 0) : 0
          console_module[:interval] = interval ? (interval > 0 ? interval : 0) : 1
          console_module[:schedule] = true
        end
      end

      @console_modules[module_id] = console_module
    end

    # Enable console module
    #
    # @param [String] module_id
    def enable_module module_id
      console_module = @console_modules[module_id]
      if console_module && !console_module[:enable]
        console_module[:enable] = true
        if console_module[:schedule]
          add_to_scheduler console_module
        end
        return true
      end
      return false
    end

    # Disable console module
    #
    # @param [String] module_id
    def disable_module module_id
      console_module = @console_modules[module_id]
      if console_module && console_module[:enable]
        console_module[:enable] = false
        if console_module[:schedule] && console_module[:job_id]
          remove_from_scheduler console_module
        end
        return true
      end
      return false
    end

    # Execute console module's handler (monitor_handler, master_handler, client_handler)
    #
    # @param [String] module_id
    # @param [String] method
    # @param [Object] msg
    def execute module_id, method, msg, &block
      if !block_given?
        raise ArgumentError 'expected a code block'
      end

      console_module = @console_modules[module_id]
      if !console_module
        yield 'unknown module id: ' + module_id
        return
      end
      if !console_module[:enable]
        yield 'module ' + module_id + ' is disabled'
        return
      end
      module_entity = console_module[:module_entity]
      if !module_entity
        yield 'module ' + module_id + ' does not exist'
        return
      end
      if !module_entity.respond_to? method
        yield 'module ' + module_id + ' does not have such method: ' + method
        return
      end
      acl_msg = acl_control 'execute', method, module_id, msg
      if acl_msg != 0 && acl_msg != 1
        yield Exception.new acl_msg
        return
      end
      module_entity.send method, @agent, msg, &block
    end

    # Execute command
    #
    # @param [String] command
    # @param [String] module_id
    # @param [Object] msg
    def command command, module_id, msg, &block
      if !block_given?
        raise ArgumentError 'expected a code block'
      end

      method = @commands[command.to_sym]
      if !method
        yield 'unknown command: ' + command
        return
      end
      if !method.respond_to? :call
        yield 'unknown command: ' + command
        return
      end

      acl_msg = acl_control 'command', nil, module_id, msg
      if acl_msg != 0 && acl_msg != 1
        yield Exception.new acl_msg
        return
      end

      method.call module_id, msg, &block
    end

    private

    # Add console module to scheduler
    #
    # @param [Object] console_module
    #
    # @private
    def add_to_scheduler console_module
      args = [
        # job_cb
        method(:schedule_job_cb),
        # job_cb_args
        { :console_module => console_module },
        # trigger_args
        {
          :start_time => Time.now.to_f + console_module[:delay],
          :interval => console_module[:interval]
        }
      ]
      console_module[:job_id] = CitrusScheduler.schedule_job *args
    end

    # Remove console module from scheduler
    #
    # @param [Object] console_module
    #
    # @private
    def remove_from_scheduler console_module
      CitrusScheduler.cancel_job console_module[:job_id]
      console_module[:job_id] = nil
    end

    # Schedule job callback
    #
    # @param [Hash] args Options
    #
    # @option args [Object] :console_module
    #
    # @private
    def schedule_job_cb args={}
      console_module = args[:console_module]
      return if !console_module || !console_module[:enable]

      module_entity = console_module[:module_entity]
      return if !module_entity

      if @master
        module_entity.master_handler(@agent, nil) { |err| }
      else
        module_entity.monitor_handler(@agent, nil) { |err| }
      end
    end

    # List console modules
    #
    # @param [String] module_id
    # @param [Object] msg
    #
    # @private
    def list_command module_id, msg, &block
      block.call nil, @console_modules.select { |module_id, console_module|
        !(module_id =~ /^__\w+__$/)
      }
    end

    # Enable console module
    #
    # @param [String] module_id
    # @param [Object] msg
    #
    # @private
    def enable_command module_id, msg, &block
      if !block_given?
        raise ArgumentError 'expected a code block'
      end
      if !@console_modules[module_id]
        yield nil, PRO_FAIL
        return
      end
      enable_module module_id
      if @master
        @agent.broadcast_command 'enable', module_id, msg
      end
      yield nil, PRO_OK
    end

    # Disable console module
    #
    # @param [String] module_id
    # @param [Object] msg
    #
    # @private
    def disable_command module_id, msg, &block
      if !block_given?
        raise ArgumentError 'expected a code block'
      end
      if !@console_modules[module_id]
        yield nil, PRO_FAIL
        return
      end
      disable_module module_id
      if @master
        @agent.broadcast_command 'disable', module_id, msg
      end
      yield nil, PRO_OK
    end

    # ACL control
    #
    # @param [String] action
    # @param [String] method
    # @param [String] module_id
    # @param [Object] msg
    #
    # @private
    def acl_control action, method, module_id, msg
      if action == 'execute'
        if method != 'client_handler' || module_id != '__console__'
          return 0
        end
        signal = msg[:signal]
        if !signal || !(['stop', 'add', 'kill'].include? signal)
          return 0
        end
      end
      if !client_id = msg[:client_id]
        return 'unknown client id'
      end
      client = @agent.get_client_by_id client_id
      if client && client[:user_info] && client[:user_info][:level]
        level = client[:user_info][:level]
        if level > 1
          return 'command permission denied'
        end
      else
        return 'unknown client info'
      end
      return 1
    end

    # Create master console service
    #
    # @param [Hash] args Options
    #
    # @option args [Integer] :port
    def self.create_master_console args={}
      args[:master] = true
      ConsoleService.new args
    end

    # Create monitor console service
    #
    # @param [Hash] args Options
    #
    # @option args [String]  :host
    # @option args [Integer] :port
    # @option args [String]  :server_id
    # @option args [String]  :server_type
    # @option args [Object]  :server_info
    def self.create_monitor_console args={}
      ConsoleService.new args
    end
  end
end
