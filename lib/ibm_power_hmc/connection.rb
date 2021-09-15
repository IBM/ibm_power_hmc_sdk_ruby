# frozen_string_literal: true

# Module for IBM HMC Rest API Client
module IbmPowerHmc
  ##
  # HMC REST Client connection.
  class Connection
    ##
    # @!method initialize(host:, username: "hscroot", password:, port: 12_443, validate_ssl: true)
    # Create a new HMC connection.
    #
    # @param host [String] Hostname of the HMC.
    # @param username [String] User name.
    # @param password [String] Password.
    # @param port [Integer] TCP port number.
    # @param validate_ssl [Boolean] Verify SSL certificates.
    def initialize(host:, username: "hscroot", password:, port: 12_443, validate_ssl: true)
      # Damien: use URI::HTTPS
      @hostname = "#{host}:#{port}"
      @username = username
      @password = password
      @verify_ssl = validate_ssl
      @api_session_token = nil
    end

    ##
    # @!method logon
    # Establish a trusted session with the Web Services APIs.
    # @return [String] The X-API-Session token.
    def logon
      method_url = "/rest/api/web/Logon"
      headers = {
        :content_type => "application/vnd.ibm.powervm.web+xml; type=LogonRequest"
      }
      doc = REXML::Document.new("")
      doc.add_element("LogonRequest", {
                        "xmlns" => "http://www.ibm.com/xmlns/systems/power/firmware/web/mc/2012_10/",
                        "schemaVersion" => "V1_1_0"
                      })
      doc.root.add_element("UserID").text = @username
      doc.root.add_element("Password").text = @password

      # Damien: begin/rescue
      @api_session_token = ""
      response = request(:put, method_url, headers, doc.to_s)
      doc = REXML::Document.new(response.body)
      @api_session_token = doc.root.elements["X-API-Session"].text
    end

    ##
    # @!method logoff
    # Close the session.
    def logoff
      method_url = "/rest/api/web/Logon"
      request(:delete, method_url)
      @api_session_token = nil
    end

    ##
    # @!method management_console
    # Retrieve information about the management console.
    # @return [IbmPowerHmc::ManagementConsole] The management console.
    def management_console
      method_url = "/rest/api/uom/ManagementConsole"
      response = request(:get, method_url)
      doc = REXML::Document.new(response.body)
      entry = doc.root.elements["entry"]
      ManagementConsole.new(entry)
    end

    def parse_feed(doc, myclass)
      objs = []
      return objs if doc.root.nil?

      doc.each_element("feed/entry") do |entry|
        objs << myclass.new(entry)
      end
      objs
    end
    private :parse_feed

    ##
    # @!method managed_systems
    # Retrieve the list of systems managed by the HMC.
    # @return [Array<IbmPowerHmc::ManagedSystem>] The list of managed systems.
    def managed_systems
      method_url = "/rest/api/uom/ManagedSystem"
      response = request(:get, method_url)
      doc = REXML::Document.new(response.body)
      parse_feed(doc, ManagedSystem)
    end

    ##
    # @!method lpars(sys_uuid = nil)
    # Retrieve the list of logical partitions managed by the HMC.
    # @param sys_uuid [String] The UUID of the managed system.
    # @return [Array<IbmPowerHmc::LogicalPartition>] The list of logical partitions.
    def lpars(sys_uuid = nil)
      if sys_uuid.nil?
        method_url = "/rest/api/uom/LogicalPartition"
      else
        method_url = "/rest/api/uom/ManagedSystem/#{sys_uuid}/LogicalPartition"
      end
      response = request(:get, method_url)
      doc = REXML::Document.new(response.body)
      parse_feed(doc, LogicalPartition)
    end

    ##
    # @!method lpar(lpar_uuid, sys_uuid = nil, group_name = nil)
    # Retrieve information about a logical partition.
    # @param lpar_uuid [String] The UUID of the logical partition.
    # @param sys_uuid [String] The UUID of the managed system.
    # @param group_name [String] The extended group attributes.
    # @return [IbmPowerHmc::LogicalPartition] The logical partition.
    def lpar(lpar_uuid, sys_uuid = nil, group_name = nil)
      if sys_uuid.nil?
        method_url = "/rest/api/uom/LogicalPartition/#{lpar_uuid}"
      else
        method_url = "/rest/api/uom/ManagedSystem/#{sys_uuid}/LogicalPartition/#{lpar_uuid}"
      end
      method_url += "?group=#{group_name}" unless group_name.nil?

      response = request(:get, method_url)
      doc = REXML::Document.new(response.body)
      entry = doc.elements["entry"]
      LogicalPartition.new(entry)
    end

    ##
    # @!method lpar_quick_property(lpar_uuid, property_name)
    # Retrieve a quick property of a logical partition.
    # @param lpar_uuid [String] The UUID of the logical partition.
    # @return [String] The quick property value.
    def lpar_quick_property(lpar_uuid, property_name)
      method_url = "/rest/api/uom/LogicalPartition/#{lpar_uuid}/quick/#{property_name}"

      response = request(:get, method_url)
      response.body[1..-2]
    end

    ##
    # @!method vioses(sys_uuid = nil)
    # Retrieve the list of virtual I/O servers managed by the HMC.
    # @param sys_uuid [String] The UUID of the managed system.
    # @return [Array<IbmPowerHmc::VirtualIOServer>] The list of virtual I/O servers.
    def vioses(sys_uuid = nil)
      if sys_uuid.nil?
        method_url = "/rest/api/uom/VirtualIOServer"
      else
        method_url = "/rest/api/uom/ManagedSystem/#{sys_uuid}/VirtualIOServer"
      end
      begin
        response = request(:get, method_url)
      rescue
        return []
      end
      doc = REXML::Document.new(response.body)
      parse_feed(doc, VirtualIOServer)
    end

    # Damien: share the same method for VIOS and LPAR?
    def lpar_profiles(lpar_uuid)
      method_url = "/rest/api/uom/LogicalPartition/#{lpar_uuid}/LogicalPartitionProfile"
      begin
        response = request(:get, method_url)
      rescue
        return []
      end
      doc = REXML::Document.new(response.body)
      parse_feed(doc, LogicalPartitionProfile)
    end

    ##
    # @!method poweron_lpar(lpar_uuid, params = {})
    # Power on a logical partition.
    # @param lpar_uuid [String] The UUID of the logical partition.
    # @param params [Hash] Job parameters.
    def poweron_lpar(lpar_uuid, params = {})
      method_url = "/rest/api/uom/LogicalPartition/#{lpar_uuid}/do/PowerOn"

      job = HmcJob.new(self, method_url, "PowerOn", "LogicalPartition", params)
      job.start
      job.wait
      job.delete
    end

    ##
    # @!method poweroff_lpar(lpar_uuid, params = {})
    # Power off a logical partition.
    # @param lpar_uuid [String] The UUID of the logical partition.
    # @param params [Hash] Job parameters.
    def poweroff_lpar(lpar_uuid, params = {})
      method_url = "/rest/api/uom/LogicalPartition/#{lpar_uuid}/do/PowerOff"

      job = HmcJob.new(self, method_url, "PowerOff", "LogicalPartition", params)
      job.start
      job.wait
      job.delete
    end

    ##
    # @!method poweron_vios(vios_uuid, params = {})
    # Power on a virtual I/O server.
    # @param vios_uuid [String] The UUID of the virtual I/O server.
    # @param params [Hash] Job parameters.
    def poweron_vios(vios_uuid, params = {})
      method_url = "/rest/api/uom/VirtualIOServer/#{vios_uuid}/do/PowerOn"

      job = HmcJob.new(self, method_url, "PowerOn", "VirtualIOServer", params)
      job.start
      job.wait
      job.delete
    end

    ##
    # @!method poweron_vios(vios_uuid, params = {})
    # Power off a virtual I/O server.
    # @param vios_uuid [String] The UUID of the virtual I/O server.
    # @param params [Hash] Job parameters.
    def poweroff_vios(vios_uuid, params = {})
      method_url = "/rest/api/uom/VirtualIOServer/#{vios_uuid}/do/PowerOff"

      job = HmcJob.new(self, method_url, "PowerOff", "VirtualIOServer", params)
      job.start
      job.wait
      job.delete
    end

    ##
    # @!method poweron_managed_system(sys_uuid, params = {})
    # Power on a managed system.
    # @param sys_uuid [String] The UUID of the managed system.
    # @param params [Hash] Job parameters.
    def poweron_managed_system(sys_uuid, params = {})
      method_url = "/rest/api/uom/ManagedSystem/#{sys_uuid}/do/PowerOn"

      job = HmcJob.new(self, method_url, "PowerOn", "ManagedSystem", params)
      job.start
      job.wait
      job.delete
    end

    ##
    # @!method poweroff_managed_system(sys_uuid, params = {})
    # Power off a managed system.
    # @param sys_uuid [String] The UUID of the managed system.
    # @param params [Hash] Job parameters.
    def poweroff_managed_system(sys_uuid, params = {})
      method_url = "/rest/api/uom/ManagedSystem/#{sys_uuid}/do/PowerOff"

      job = HmcJob.new(self, method_url, "PowerOff", "ManagedSystem", params)
      job.start
      job.wait
      job.delete
    end

    ##
    # @!method next_events
    # Retrieve a list of events that occured since last call.
    # If no event is available, blocks until new events occur.
    # @return [Array<IbmPowerHmc::Event>] The list of events.
    def next_events
      method_url = "/rest/api/uom/Event"

      events = []
      loop do
        response = request(:get, method_url)
        next if response.code == 204

        doc = REXML::Document.new(response.body)
        doc.root.each_element("entry") do |entry|
          events << Event.new(entry)
        end
        break
      end
      events
    end

    ##
    # @!method request(method, url, headers = {}, payload = nil)
    # Perform a REST API request.
    # @param method [String] The HTTP method.
    # @param url [String] The method URL.
    # @param headers [Hash] HTTP headers.
    # @param payload [String] HTTP request payload.
    # @return [RestClient::Response] The response from the HMC.
    def request(method, url, headers = {}, payload = nil)
      logon if @api_session_token.nil?

      headers = headers.merge({"X-API-Session" => @api_session_token})
      # Damien: use URI module and prepare in initialize?
      response = RestClient::Request.execute(
        :method => method,
        :url => "https://" + @hostname + url,
        :verify_ssl => @verify_ssl,
        :payload => payload,
        :headers => headers
      )
      if response.code == 403
        # Damien: if token expires, reauth?
        @api_session_token = nil
        logon
        # Damien: retry TBD
      end
      response
    end
  end
end
