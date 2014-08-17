# Author:: MinixLi (gmail: MinixLi1986)
# Homepage:: http://citrus.inspawn.com
# Date:: 13 July 2014

require File.expand_path('../spec_helper', __FILE__)

describe 'agent' do

  master_host = '127.0.0.1'
  master_port = 3333

  MockConsoleService = Class.new {
    include RSpec::Matchers

    attr_reader :env, :auth_server

    def initialize
      @env = nil
      @auth_server = Proc.new { |msg, env, &block|
        block.call 'ok'
      }
    end
  }

  it 'should emit an error when listening on a port in use' do
    error_count = 0
    port = 80

    master = MasterAgent.new
    master.on('error') { |err|
      expect(err).to be
      error_count += 1
    }

    EM.run {
      master.listen port
      expect(error_count).to eql 1

      EM.add_timer(0.1) {
        EM.stop_event_loop
      }
    }
  end

  it 'should emit an error when connecting to an invalid address' do
    error_count = 0
    host = 'localhost'
    port = -80

    monitor = MonitorAgent.new

    EM.run {
      monitor.connect(port, host) { |err|
        expect(err).to be
        error_count += 1
      }

      EM.add_timer(0.1) {
        expect(error_count).to eql 1
        EM.stop_event_loop
      }
    }
  end

  it 'should send the request from master to the right monitor and get the response from callback by request' do
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

    master = MasterAgent.new :console_service => MockConsoleService.new

    monitor_console1 = MockConsoleService.new
    monitor_console2 = MockConsoleService.new

    monitor_console1.define_singleton_method :execute, proc{ |module_id, method, msg, &block|
      req1_count += 1
      expect(module_id).to eql module_id1
      block.call nil, msg
    }
    monitor_console2.define_singleton_method :execute, proc{ |module_id, method, msg, &block|
      req2_count += 1
      expect(module_id).to eql module_id2
      block.call nil, msg
    }

    monitor1 = MonitorAgent.new({
     :console_service => monitor_console1,
     :server_id => monitor_id1,
     :server_type => monitor_type1
    })
    monitor2 = MonitorAgent.new({
     :console_service => monitor_console2,
     :server_id => monitor_id2,
     :server_type => monitor_type2
    })

    EM.run {
      master.listen master_port

      monitor1.connect(master_port, master_host) { |err|
        expect(err).to be_nil
        master.request monitor_id1, module_id1, msg1, proc{ |err, resp|
          resp1_count += 1
          expect(err).to be_nil
          expect(resp).to eql msg1
        }
      }
      monitor2.connect(master_port, master_host) { |err|
        expect(err).to be_nil
        master.request monitor_id2, module_id2, msg2, proc{ |err, resp|
          resp2_count += 1
          expect(err).to be_nil
          expect(resp).to eql msg2
        }
      }

      EM.add_timer(0.1) {
        expect(req1_count).to eql 1
        expect(req2_count).to eql 1
        expect(resp1_count).to eql 1
        expect(resp2_count).to eql 1
        EM.stop_event_loop
      }
    }
  end

  it 'should send back an error to master if monitor callback with an error' do
    monitor_id = 'connector-server-1'
    monitor_type = 'connector'
    module_id = 'module-1'
    msg = { msg => 'message to monitor' }
    err_msg = 'some error message from monitor'

    req_count = 0
    resp_count = 0

    master = MasterAgent.new :console_service => MockConsoleService.new

    monitor_console = MockConsoleService.new
    monitor_console.define_singleton_method :execute, proc{ |inner_module_id, method, msg, &block|
      req_count += 1
      expect(inner_module_id).to eql module_id
      block.call Exception.new err_msg
    }

    monitor = MonitorAgent.new({
     :console_service => monitor_console,
     :server_id => monitor_id,
     :server_type => monitor_type
    })

    EM.run {
      master.listen master_port

      monitor.connect(master_port, master_host) { |err|
        expect(err).to be_nil
        master.request monitor_id, module_id, msg, proc{ |err, resp|
          resp_count += 1
          expect(err).to be
          expect(err[:msg]).to eql err_msg
          expect(resp).to be_nil
        }
      }

      EM.add_timer(0.1) {
        expect(req_count).to eql 1
        expect(resp_count).to eql 1
        EM.stop_event_loop
      }
    }
  end

  it 'should send the message from master to the right monitor by notify' do
    monitor_id1 = 'connector-server-1'
    monitor_id2 = 'area-server-1'
    monitor_type1 = 'connector'
    monitor_type2 = 'area'
    module_id1 = 'module-1'
    module_id2 = 'module-2'
    msg1 = { :msg => 'message to monitor1' }
    msg2 = { :msg => 'message to server1' }

    req1_count = 0
    req2_count = 0

    master = MasterAgent.new :console_service => MockConsoleService.new

    monitor_console1 = MockConsoleService.new
    monitor_console2 = MockConsoleService.new

    monitor_console1.define_singleton_method :execute, proc{ |module_id, method, msg, &block|
      req1_count += 1
      expect(module_id).to eql module_id1
    }
    monitor_console2.define_singleton_method :execute, proc{ |module_id, method, msg, &block|
      req2_count += 1
      expect(module_id).to eql module_id2
    }

    monitor1 = MonitorAgent.new({
     :console_service => monitor_console1,
     :server_id => monitor_id1,
     :server_type => monitor_type1
    })
    monitor2 = MonitorAgent.new({
     :console_service => monitor_console2,
     :server_id => monitor_id2,
     :server_type => monitor_type2
    })

    EM.run {
      master.listen master_port

      monitor1.connect(master_port, master_host) { |err|
        expect(err).to be_nil
        master.notify monitor_id1, module_id1, msg1
      }
      monitor2.connect(master_port, master_host) { |err|
        expect(err).to be_nil
        master.notify monitor_id2, module_id2, msg2
      }

      EM.add_timer(0.1) {
        expect(req1_count).to eql 1
        expect(req2_count).to eql 1
        EM.stop_event_loop
      }
    }
  end

  it 'should send the message from master to the right monitor by notify_by_server_type' do
    monitor_id1 = 'connector-server-1'
    monitor_id2 = 'connector-server-2'
    monitor_id3 = 'area-server-1'
    monitor_type1 = 'connector'
    monitor_type2 = 'area'
    module_id1 = 'module-1'
    module_id2 = 'module-2'
    msg1 = { :msg => 'message to monitor_type1' }
    msg2 = { :msg => 'message to monitor_type2' }

    req1_count = 0
    req2_count = 0
    req3_count = 0
    req_type1_count = 0
    req_type2_count = 0

    master = MasterAgent.new :console_service => MockConsoleService.new

    monitor_console1 = MockConsoleService.new
    monitor_console2 = MockConsoleService.new
    monitor_console3 = MockConsoleService.new

    monitor_console1.define_singleton_method :execute, proc{ |module_id, method, msg, &block|
      req1_count += 1
      req_type1_count += 1
      expect(module_id).to eql module_id1
      expect(msg).to eql msg1
    }
    monitor_console2.define_singleton_method :execute, proc{ |module_id, method, msg, &block|
      req2_count += 1
      req_type1_count += 1
      expect(module_id).to eql module_id1
      expect(msg).to eql msg1
    }
    monitor_console3.define_singleton_method :execute, proc{ |module_id, method, msg, &block|
      req3_count += 1
      req_type2_count += 1
      expect(module_id).to eql module_id2
      expect(msg).to eql msg2
    }

    monitor1 = MonitorAgent.new({
     :console_service => monitor_console1,
     :server_id => monitor_id1,
     :server_type => monitor_type1
    })
    monitor2 = MonitorAgent.new({
     :console_service => monitor_console2,
     :server_id => monitor_id2,
     :server_type => monitor_type1
    })
    monitor3 = MonitorAgent.new({
     :console_service => monitor_console3,
     :server_id => monitor_id3,
     :server_type => monitor_type2
    })

    EM.run {
      master.listen master_port

      monitor1.connect(master_port, master_host) { |err|
        expect(err).to be_nil
      }
      monitor2.connect(master_port, master_host) { |err|
        expect(err).to be_nil
      }
      monitor3.connect(master_port, master_host) { |err|
        expect(err).to be_nil
      }

      EM.add_timer(0.1) {
        master.notify_by_server_type monitor_type1, module_id1, msg1
        master.notify_by_server_type monitor_type2, module_id2, msg2
      }

      EM.add_timer(0.2) {
        expect(req1_count).to eql 1
        expect(req2_count).to eql 1
        expect(req3_count).to eql 1
        expect(req_type1_count).to eql 2
        expect(req_type2_count).to eql 1
        EM.stop_event_loop
      }
    }
  end

  it 'should send the message from master to all the monitors by broadcast_notify' do
    monitor_id1 = 'connector-server-1'
    monitor_id2 = 'area-server-1'
    monitor_type1 = 'connector'
    monitor_type2 = 'area'
    org_module_id = 'module-1'
    org_msg = { :msg => 'message to all' }

    req1_count = 0
    req2_count = 0

    master = MasterAgent.new :console_service => MockConsoleService.new

    monitor_console1 = MockConsoleService.new
    monitor_console2 = MockConsoleService.new

    monitor_console1.define_singleton_method :execute, proc{ |module_id, method, msg, &block|
      req1_count += 1
      expect(module_id).to eql org_module_id
      expect(msg).to eql org_msg
    }
    monitor_console2.define_singleton_method :execute, proc{ |module_id, method, msg, &block|
      req2_count += 1
      expect(module_id).to eql org_module_id
      expect(msg).to eql org_msg
    }

    monitor1 = MonitorAgent.new({
     :console_service => monitor_console1,
     :server_id => monitor_id1,
     :server_type => monitor_type1
    })
    monitor2 = MonitorAgent.new({
     :console_service => monitor_console2,
     :server_id => monitor_id2,
     :server_type => monitor_type1
    })

    EM.run {
      master.listen master_port

      monitor1.connect(master_port, master_host) { |err|
        expect(err).to be_nil
      }
      monitor2.connect(master_port, master_host) { |err|
        expect(err).to be_nil
      }

      EM.add_timer(0.1) {
        master.broadcast_notify org_module_id, org_msg
      }

      EM.add_timer(0.2) {
        expect(req1_count).to eql 1
        expect(req2_count).to eql 1
        EM.stop_event_loop
      }
    }
  end

  it 'should push the message from monitor to master by notify' do
    monitor_id = 'connector-server-1'
    monitor_type = 'connector'
    org_module_id = 'module-1'
    org_msg = 'message to master'

    req_count = 0

    master_console = MockConsoleService.new
    master_console.define_singleton_method :execute, proc{ |module_id, method, msg, &block|
      req_count += 1
      expect(module_id).to eql org_module_id
      expect(msg).to eql org_msg
    }

    master = MasterAgent.new :console_service => master_console
    monitor = MonitorAgent.new({
     :console_service => MockConsoleService.new,
     :server_id => monitor_id,
     :server_type => monitor_type
    })

    EM.run {
      master.listen master_port

      monitor.connect(master_port, master_host) { |err|
        expect(err).to be_nil
        monitor.notify org_module_id, org_msg
      }

      EM.add_timer(0.1) {
        expect(req_count).to eql 1
        EM.stop_event_loop
      }
    }
  end
end
