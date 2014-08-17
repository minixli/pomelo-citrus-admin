# Author:: MinixLi (gmail: MinixLi1986)
# Homepage:: http://citrus.inspawn.com
# Date:: 9 July 2014

module CitrusAdmin
  # Protocol
  #
  #
  module Protocol
    #
    #
    #
    PRO_OK = 1
    PRO_FAIL = -1

    # Componse request
    #
    # @param [Integer] req_id
    # @param [String]  module_id
    # @param [Object]  body
    def compose_request req_id, module_id, body
      if req_id
        # request message
        { :req_id => req_id, :module_id => module_id, :body => body }
      else
        # notify message
        { :module_id => module_id, :body => body }
      end
    end

    # Compose response
    #
    # @param [Object] msg
    # @param [Object] err
    # @param [Object] res
    def compose_response msg, err, res
      return nil unless msg[:req_id]
      { :resp_id => msg[:req_id], :err => clone_error(err), :body => res }
    end

    # Compose command
    #
    # @param [Integer] req_id
    # @param [String]  command
    # @param [String]  module_id
    # @param [Object]  body
    def compose_command req_id, command, module_id, body
      if req_id
        # command message
        { :req_id => req_id, :command => command, :module_id => module_id, :body => body }
      else
        { :command => command, :module_id => module_id, :body => body }
      end
    end

    # Parse message
    #
    # @param [String] msg
    def parse msg
      begin
        JSON.parse msg, { :symbolize_names => true }
      rescue => err
      end
    end

    # Determine if a message is a request
    #
    # @param [Object] msg
    def is_request? msg
      msg && msg[:req_id]
    end

    # Clone error
    #
    # @private
    def clone_error origin
      if origin.is_a? Exception
        return { :msg => origin.message, :stack => nil }
      end
      return origin
    end
  end
end
