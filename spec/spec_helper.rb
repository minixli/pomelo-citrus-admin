# Author:: MinixLi (gmail: MinixLi1986)
# Homepage:: http://citrus.inspawn.com
# Date:: 13 July 2014

require File.expand_path('../../lib/citrus-admin', __FILE__)

ConsoleService = CitrusAdmin::ConsoleService
MasterAgent    = CitrusAdmin::MasterAgent
MonitorAgent   = CitrusAdmin::MonitorAgent

RSpec.configure { |config|
  config.mock_with(:rspec) { |c|
    c.syntax = [:should, :expect]
  }
  config.expect_with(:rspec) { |c|
    c.syntax = [:should, :expect]
  }
}
