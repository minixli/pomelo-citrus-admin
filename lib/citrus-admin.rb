# Author:: MinixLi (gmail: MinixLi1986)
# Homepage:: http://citrus.inspawn.com
# Date:: 8 July 2014

$:.unshift(File.dirname(__FILE__) + '/../lib')

require 'eventmachine'
require 'json'
require 'websocket-eventmachine-client'
require 'websocket-eventmachine-server'

require 'citrus-monitor'

require 'citrus-admin/util/protocol'
require 'citrus-admin/util/utils'
require 'citrus-admin/console_service'

# Load all the console modules
Dir.glob(File.expand_path('../citrus-admin/modules/*.rb', __FILE__)).each { |filepath|
  require filepath
}
