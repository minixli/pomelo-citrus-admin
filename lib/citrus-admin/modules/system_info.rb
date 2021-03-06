# Author:: MinixLi (gmail: MinixLi1986)
# Homepage:: http://citrus.inspawn.com
# Date:: 19 July 2014

require 'citrus-admin/modules/console_module'

module CitrusAdmin
  # ConsoleModules
  #
  #
  module ConsoleModules
    # SystemInfo
    #
    #
    class SystemInfo < ConsoleModule

      @module_id = 'system_info'

      #
      #
      # @param [Hash]   args
      # @param [Object] console_service
      def initialize args={}, console_service
      end

      # Monitor handler
      #
      #
      def monitor_handler
      end

      # Master handler
      #
      #
      def master_handler
      end

      # Client handler
      #
      #
      def client_handler
      end
    end
  end
end
