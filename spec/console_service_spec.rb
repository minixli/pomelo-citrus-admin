# Author:: MinixLi (gmail: MinixLi1986)
# Homepage:: http://citrus.inspawn.com
# Date:: 15 July 2014

require File.expand_path('../spec_helper', __FILE__)

describe ConsoleService do

  master_host = '127.0.0.1'
  master_port = 3333

  it "should send the request to the right monitor's console module and get the response from callback" do
    monitor_id1 = 'connector-server-1'
    monitor_id2 = 'area-server-1'
    monitor_type1 = 'connector'
    monitor_type2 = 'area'
    module_id1 = 'module-1'
    module_id2 = 'module-2'
    msg1 = { :msg => 'message to monitor1' }
    msg2 = { :msg => 'message to monitor2' }

    req1_count = 0
    req2_count = 0
    resp1_count = 0
    resp2_count = 0

    master_console = ConsoleService.create_master_console({
      :port => master_port
    })

    monitor_console1 = ConsoleService.create_monitor_console({
      :host => master_host,
      :port => master_port,
      :server_id => monitor_id1,
      :server_type => monitor_type1
    })
    monitor_console2 = ConsoleService.create_monitor_console({
      :host => master_host,
      :port => master_port,
      :server_id => monitor_id2,
      :server_type => monitor_type2
    })

    module_entity1 = Object.new
    class << module_entity1
      include RSpec::Matchers
      attr_accessor :type
    end
    module_entity2 = Object.new
    class << module_entity2
      include RSpec::Matchers
      attr_accessor :type
    end

    module_entity1.define_singleton_method :monitor_handler, proc{ |agent, msg, &block|
      req1_count += 1
      expect(msg).to be
      expect(msg).to eql msg1
      block.call nil, msg
    }
    module_entity2.define_singleton_method :monitor_handler, proc{ |agent, msg, &block|
      req2_count += 1
      expect(msg).to be
      expect(msg).to eql msg2
      block.call nil, msg
    }

    monitor_console1.register module_id1, module_entity1
    monitor_console2.register module_id2, module_entity2

    EM.run {
      master_console.start { |err|
        expect(err).to be_nil
      }

      EM.add_timer(0.1) {
        monitor_console1.start { |err|
          expect(err).to be_nil
          master_console.agent.request monitor_id1, module_id1, msg1, proc{ |err, resp|
            resp1_count += 1
            expect(err).to be_nil
            expect(resp).to be
            expect(resp).to eql msg1
          }
        }
        monitor_console2.start { |err|
          expect(err).to be_nil
          master_console.agent.request monitor_id2, module_id2, msg2, proc{ |err, resp|
            resp2_count += 1
            expect(err).to be_nil
            expect(resp).to be
            expect(resp).to eql msg2
          }
        }
      }

      EM.add_timer(0.2) {
        expect(req1_count).to eql 1
        expect(req2_count).to eql 1
        expect(resp1_count).to eql 1
        expect(resp2_count).to eql 1
        EM.stop_event_loop
      }
    }
  end

  it "should send the message from monitor to the right master's console module" do
    monitor_id = 'connector-server-1'
    monitor_type = 'connector'
    module_id = 'module-1'
    org_msg = { :msg => 'message to master' }

    req_count = 0

    master_console = ConsoleService.create_master_console({
      :port => master_port
    })

    module_entity1 = Object.new
    class << module_entity1
      include RSpec::Matchers
      attr_accessor :type
    end

    module_entity1.define_singleton_method :master_handler, proc{ |agent, msg, &block|
      req_count += 1
      expect(msg).to be
      expect(msg).to eql org_msg
    }

    master_console.register module_id, module_entity1

    monitor_console = ConsoleService.create_monitor_console({
      :host => master_host,
      :port => master_port,
      :server_id => monitor_id,
      :server_type => monitor_type
    })

    EM.run {
      master_console.start { |err|
        expect(err).to be_nil
      }

      EM.add_timer(0.1) {
        monitor_console.start { |err|
          expect(err).to be_nil
          monitor_console.agent.notify module_id, org_msg
        }
      }

      EM.add_timer(0.2) {
        expect(req_count).to eql 1
        EM.stop_event_loop
      }
    }
  end

  it 'should fail if the module is disabled' do
    monitor_id = 'connector-server-1'
    monitor_type = 'connector'
    module_id = 'module-1'
    org_msg = { :msg => 'message to someone' }

    module_entity1 = Object.new
    class << module_entity1
      include RSpec::Matchers
      attr_accessor :type
    end
    module_entity2 = Object.new
    class << module_entity2
      include RSpec::Matchers
      attr_accessor :type
    end

    module_entity1.define_singleton_method :master_handler, proc{ |agent, msg, &block|
      # should not arrive here
      expect(true).to eql false
    }

    module_entity2.define_singleton_method :monitor_handler, proc{ |agent, msg, &block|
      # should not arrive here
      expect(true).to eql false
    }

    master_console = ConsoleService.create_master_console({
      :port => master_port
    })
    monitor_console = ConsoleService.create_monitor_console({
      :host => master_host,
      :port => master_port,
      :server_id => monitor_id,
      :server_type => monitor_type
    })

    master_console.register module_id, module_entity1
    monitor_console.register module_id, module_entity1

    EM.run {
      master_console.start { |err|
        expect(err).to be_nil
      }

      EM.add_timer(0.1) {
        monitor_console.start { |err|
          expect(err).to be_nil
          master_console.disable_module module_id
          monitor_console.disable_module module_id
          master_console.agent.notify monitor_id, module_id, org_msg
          monitor_console.agent.notify module_id, org_msg
        }
      }

      EM.add_timer(0.2) {
        EM.stop_event_loop
      }
    }
  end

  it 'should fail if the monitor does not exist' do
    monitor_id = 'connector-server-1'
    module_id = 'module-1'
    org_msg = { :msg => 'message to someone' }

    master_console = ConsoleService.create_master_console({
      :port => master_port
    })

    EM.run {
      master_console.start { |err|
        expect(err).to be_nil
      }

      EM.add_timer(0.1) {
        master_console.agent.request monitor_id, module_id, org_msg, proc{ |err, resp|
          expect(err).to be
          expect(resp).to be_nil
        }
      }

      EM.add_timer(0.2) {
        EM.stop_event_loop
      }
    }
  end
end
