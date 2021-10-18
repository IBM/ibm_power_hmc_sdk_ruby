# frozen_string_literal: true

# Module for IBM HMC Rest API Client
module IbmPowerHmc
  class Error < StandardError; end

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
    def initialize(host:, password:, username: "hscroot", port: 12_443, validate_ssl: true)
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
      doc.add_element("LogonRequest", "schemaVersion" => "V1_1_0")
      doc.root.add_namespace("http://www.ibm.com/xmlns/systems/power/firmware/web/mc/2012_10/")
      doc.root.add_element("UserID").text = @username
      doc.root.add_element("Password").text = @password

      @api_session_token = ""
      response = request(:put, method_url, headers, doc.to_s)
      doc = REXML::Document.new(response.body)
      elem = doc.elements["LogonResponse/X-API-Session"]
      raise Error, "LogonResponse/X-API-Session not found" if elem.nil?

      @api_session_token = elem.text
    end

    ##
    # @!method logoff
    # Close the session.
    def logoff
      # Don't want to trigger automatic logon here!
      return if @api_session_token.nil?

      method_url = "/rest/api/web/Logon"
      begin
        request(:delete, method_url)
      rescue
        # Ignore exceptions as this is best effort attempt to log off.
      end
      @api_session_token = nil
    end

    ##
    # @!method management_console
    # Retrieve information about the management console.
    # @return [IbmPowerHmc::ManagementConsole] The management console.
    def management_console
      method_url = "/rest/api/uom/ManagementConsole"
      response = request(:get, method_url)
      # This request returns a feed with a single entry.
      FeedParser.new(response.body).objects(:ManagementConsole).first
    end

    ##
    # @!method managed_systems(search = {})
    # Retrieve the list of systems managed by the HMC.
    # @param search [Hash] The optional property name and value to match.
    # @return [Array<IbmPowerHmc::ManagedSystem>] The list of managed systems.
    def managed_systems(search = {})
      method_url = "/rest/api/uom/ManagedSystem"
      search.each { |key, value| method_url += "/search/(#{key}==#{value})" }
      response = request(:get, method_url)
      FeedParser.new(response.body).objects(:ManagedSystem)
    end

    ##
    # @!method managed_system(lpar_uuid, sys_uuid = nil, group_name = nil)
    # Retrieve information about a managed system.
    # @param sys_uuid [String] The UUID of the managed system.
    # @param group_name [String] The extended group attributes.
    # @return [IbmPowerHmc::ManagedSystem] The managed system.
    def managed_system(sys_uuid, group_name = nil)
      method_url = "/rest/api/uom/ManagedSystem/#{sys_uuid}"
      method_url += "?group=#{group_name}" unless group_name.nil?

      response = request(:get, method_url)
      Parser.new(response.body).object(:ManagedSystem)
    end

    ##
    # @!method lpars(sys_uuid = nil, search = {})
    # Retrieve the list of logical partitions managed by the HMC.
    # @param sys_uuid [String] The UUID of the managed system.
    # @param search [Hash] The optional property name and value to match.
    # @return [Array<IbmPowerHmc::LogicalPartition>] The list of logical partitions.
    def lpars(sys_uuid = nil, search = {})
      if sys_uuid.nil?
        method_url = "/rest/api/uom/LogicalPartition"
        search.each { |key, value| method_url += "/search/(#{key}==#{value})" }
      else
        method_url = "/rest/api/uom/ManagedSystem/#{sys_uuid}/LogicalPartition"
      end
      response = request(:get, method_url)
      FeedParser.new(response.body).objects(:LogicalPartition)
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
      Parser.new(response.body).object(:LogicalPartition)
    end

    ##
    # @!method lpar_quick_property(lpar_uuid, property_name)
    # Retrieve a quick property of a logical partition.
    # @param lpar_uuid [String] The UUID of the logical partition.
    # @param property_name [String] The quick property name.
    # @return [String] The quick property value.
    def lpar_quick_property(lpar_uuid, property_name)
      method_url = "/rest/api/uom/LogicalPartition/#{lpar_uuid}/quick/#{property_name}"

      response = request(:get, method_url)
      response.body[1..-2]
    end

    ##
    # @!method rename_lpar(lpar_uuid, newname)
    # Rename a logical partition.
    # @param lpar_uuid [String] The UUID of the logical partition.
    # @param newname [String] The new name of the logical partition.
    def rename_lpar(lpar_uuid, newname)
      method_url = "/rest/api/uom/LogicalPartition/#{lpar_uuid}"
      headers = {
        :content_type => "application/vnd.ibm.powervm.uom+xml; type=LogicalPartition",
      }
      modify_object(method_url, headers) do |lpar|
        lpar.xml.elements["PartitionName"].text = newname
      end
    end

    ##
    # @!method vioses(sys_uuid = nil, search = {})
    # Retrieve the list of virtual I/O servers managed by the HMC.
    # @param sys_uuid [String] The UUID of the managed system.
    # @param search [Hash] The optional property name and value to match.
    # @return [Array<IbmPowerHmc::VirtualIOServer>] The list of virtual I/O servers.
    def vioses(sys_uuid = nil, search = {})
      if sys_uuid.nil?
        method_url = "/rest/api/uom/VirtualIOServer"
        search.each { |key, value| method_url += "/search/(#{key}==#{value})" }
      else
        method_url = "/rest/api/uom/ManagedSystem/#{sys_uuid}/VirtualIOServer"
      end
      response = request(:get, method_url)
      FeedParser.new(response.body).objects(:VirtualIOServer)
    end

    ##
    # @!method vios(vios_uuid, sys_uuid = nil, group_name = nil)
    # Retrieve information about a virtual I/O server.
    # @param vios_uuid [String] The UUID of the virtual I/O server.
    # @param sys_uuid [String] The UUID of the managed system.
    # @param group_name [String] The extended group attributes.
    # @return [IbmPowerHmc::VirtualIOServer] The virtual I/O server.
    def vios(vios_uuid, sys_uuid = nil, group_name = nil)
      if sys_uuid.nil?
        method_url = "/rest/api/uom/VirtualIOServer/#{vios_uuid}"
      else
        method_url = "/rest/api/uom/ManagedSystem/#{sys_uuid}/VirtualIOServer/#{vios_uuid}"
      end
      method_url += "?group=#{group_name}" unless group_name.nil?

      response = request(:get, method_url)
      Parser.new(response.body).object(:VirtualIOServer)
    end

    ##
    # @!method poweron_lpar(lpar_uuid, params = {}, sync = true)
    # Power on a logical partition.
    # @param lpar_uuid [String] The UUID of the logical partition.
    # @param params [Hash] Job parameters.
    # @param sync [Boolean] Start the job and wait for its completion.
    # @return [IbmPowerHmc::HmcJob] The HMC job.
    def poweron_lpar(lpar_uuid, params = {}, sync: true)
      method_url = "/rest/api/uom/LogicalPartition/#{lpar_uuid}/do/PowerOn"

      job = HmcJob.new(self, method_url, "PowerOn", "LogicalPartition", params)
      job.run if sync
      job
    end

    ##
    # @!method poweroff_lpar(lpar_uuid, params = {}, sync = true)
    # Power off a logical partition.
    # @param lpar_uuid [String] The UUID of the logical partition.
    # @param params [Hash] Job parameters.
    # @param sync [Boolean] Start the job and wait for its completion.
    # @return [IbmPowerHmc::HmcJob] The HMC job.
    def poweroff_lpar(lpar_uuid, params = {}, sync: true)
      method_url = "/rest/api/uom/LogicalPartition/#{lpar_uuid}/do/PowerOff"

      job = HmcJob.new(self, method_url, "PowerOff", "LogicalPartition", params)
      job.run if sync
      job
    end

    ##
    # @!method poweron_vios(vios_uuid, params = {}, sync = true)
    # Power on a virtual I/O server.
    # @param vios_uuid [String] The UUID of the virtual I/O server.
    # @param params [Hash] Job parameters.
    # @param sync [Boolean] Start the job and wait for its completion.
    # @return [IbmPowerHmc::HmcJob] The HMC job.
    def poweron_vios(vios_uuid, params = {}, sync: true)
      method_url = "/rest/api/uom/VirtualIOServer/#{vios_uuid}/do/PowerOn"

      job = HmcJob.new(self, method_url, "PowerOn", "VirtualIOServer", params)
      job.run if sync
      job
    end

    ##
    # @!method poweroff_vios(vios_uuid, params = {}, sync = true)
    # Power off a virtual I/O server.
    # @param vios_uuid [String] The UUID of the virtual I/O server.
    # @param params [Hash] Job parameters.
    # @param sync [Boolean] Start the job and wait for its completion.
    # @return [IbmPowerHmc::HmcJob] The HMC job.
    def poweroff_vios(vios_uuid, params = {}, sync: true)
      method_url = "/rest/api/uom/VirtualIOServer/#{vios_uuid}/do/PowerOff"

      job = HmcJob.new(self, method_url, "PowerOff", "VirtualIOServer", params)
      job.run if sync
      job
    end

    ##
    # @!method poweron_managed_system(sys_uuid, params = {}, sync = true)
    # Power on a managed system.
    # @param sys_uuid [String] The UUID of the managed system.
    # @param params [Hash] Job parameters.
    # @param sync [Boolean] Start the job and wait for its completion.
    # @return [IbmPowerHmc::HmcJob] The HMC job.
    def poweron_managed_system(sys_uuid, params = {}, sync: true)
      method_url = "/rest/api/uom/ManagedSystem/#{sys_uuid}/do/PowerOn"

      job = HmcJob.new(self, method_url, "PowerOn", "ManagedSystem", params)
      job.run if sync
      job
    end

    ##
    # @!method poweroff_managed_system(sys_uuid, params = {}, sync = true)
    # Power off a managed system.
    # @param sys_uuid [String] The UUID of the managed system.
    # @param params [Hash] Job parameters.
    # @param sync [Boolean] Start the job and wait for its completion.
    # @return [IbmPowerHmc::HmcJob] The HMC job.
    def poweroff_managed_system(sys_uuid, params = {}, sync: true)
      method_url = "/rest/api/uom/ManagedSystem/#{sys_uuid}/do/PowerOff"

      job = HmcJob.new(self, method_url, "PowerOff", "ManagedSystem", params)
      job.run if sync
      job
    end

    ##
    # @!method remove_connection(hmc_uuid, sys_uuid, sync = true)
    # Remove a managed system from the management console.
    # @param hmc_uuid [String] The UUID of the management console.
    # @param sys_uuid [String] The UUID of the managed system.
    # @param sync [Boolean] Start the job and wait for its completion.
    # @return [IbmPowerHmc::HmcJob] The HMC job.
    def remove_connection(hmc_uuid, sys_uuid, sync: true)
      method_url = "/rest/api/uom/ManagementConsole/#{hmc_uuid}/ManagedSystem/#{sys_uuid}/do/RemoveConnection"

      job = HmcJob.new(self, method_url, "RemoveConnection", "ManagedSystem")
      job.run if sync
      job
    end

    ##
    # @!method cli_run(hmc_uuid, cmd, sync = true)
    # Run a CLI command on the HMC as a job.
    # @param hmc_uuid [String] The UUID of the management console.
    # @param cmd [String] The command to run.
    # @param sync [Boolean] Start the job and wait for its completion.
    # @return [IbmPowerHmc::HmcJob] The HMC job.
    def cli_run(hmc_uuid, cmd, sync: true)
      method_url = "/rest/api/uom/ManagementConsole/#{hmc_uuid}/do/CLIRunner"

      params = {
        "cmd" => cmd,
        "acknowledgeThisAPIMayGoAwayInTheFuture" => "true",
      }
      job = HmcJob.new(self, method_url, "CLIRunner", "ManagementConsole", params)
      job.run if sync
      job
    end

    ##
    # @!method virtual_switches(sys_uuid)
    # Retrieve the list of virtual switchs from a specified managed system
    # @param sys_uuid [string] The UUID of the managed system
    # @return [Array<IbmPowerHmc::VirtualSwitch] The list of virtual switch.
    def virtual_switches(sys_uuid)
      method_url = "/rest/api/uom/ManagedSystem/#{sys_uuid}/VirtualSwitch"
      response = request(:get, method_url)
      FeedParser.new(response.body).objects(:VirtualSwitch)
    end

    ##
    # @!method virtual_switch(vswitch_uuid, sys_uuid = nil, group_name = nil)
    # @param vswitch_uuid [string] The UUID of the virtual switch
    # @param  sys_uuid [String] The UUID of the managed system.
    # @param group_name [String] The extended group attributes.
    # @return [IbmPowerHmc::VirtualSwitch] The virtual switch.
    def virtual_switch(vswitch_uuid, sys_uuid, group_name = nil)
      method_url = "/rest/api/uom/ManagedSystem/#{sys_uuid}/VirtualSwitch/#{vswitch_uuid}"

      method_url += "?group=#{group_name}" unless group_name.nil?

      response = request(:get, method_url)
      doc = REXML::Document.new(response.body)
      entry = doc.elements["entry"]
      VirtualSwitch.new(entry)
    end

    ##
    # @!method next_events(wait = true)
    # Retrieve a list of events that occured since last call.
    # @param wait [Boolean] If no event is available, block until new events occur.
    # @return [Array<IbmPowerHmc::Event>] The list of events.
    def next_events(wait: true)
      method_url = "/rest/api/uom/Event"

      response = nil
      loop do
        response = request(:get, method_url)
        # No need to sleep as the HMC already waits a bit before returning 204
        break if response.code != 204 || !wait
      end
      FeedParser.new(response.body).objects(:Event)
    end

    ##
    # @!method schema(type)
    # Retrieve the XML schema file for a given object type.
    # @param type [String] The object type (e.g. "LogicalPartition", "inc/Types")
    # @return [REXML::Document] The XML schema file.
    def schema(type)
      method_url = "/rest/api/web/schema/#{type}.xsd"
      response = request(:get, method_url)
      REXML::Document.new(response.body)
    end

    class HttpError < Error
      attr_reader :status, :uri, :reason, :message, :original_exception

      ##
      # @!method initialize(err)
      # Create a new HttpError exception.
      # @param err [RestClient::Exception] The REST client exception.
      def initialize(err)
        super
        @original_exception = err
        @status = err.http_code
        @message = err.message

        # Try to parse body as an HttpErrorResponse
        unless err.response.nil?
          resp = Parser.new(err.response.body).object(:HttpErrorResponse)
          unless resp.nil?
            @uri = resp.uri
            @reason = resp.reason
            @message = resp.message
          end
        end
      end

      def to_s
        "msg=\"#{@message}\" status=\"#{@status}\" reason=\"#{@reason}\" uri=#{@uri}"
      end
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
      reauth = false
      # Check for relative URLs
      url = "https://#{@hostname}#{url}" if url.start_with?("/")
      begin
        headers = headers.merge("X-API-Session" => @api_session_token)
        RestClient::Request.execute(
          :method => method,
          :url => url,
          :verify_ssl => @verify_ssl,
          :payload => payload,
          :headers => headers
        )
      rescue RestClient::Exception => e
        # Do not retry on failed logon attempts
        if e.http_code == 401 && @api_session_token != "" && !reauth
          # Try to reauth
          reauth = true
          logon
          retry
        end
        raise HttpError.new(e), "REST request failed"
      end
    end

    private

    def modify_object(method_url, headers = {}, attempts = 5)
      while attempts > 0
        response = request(:get, method_url)
        obj = Parser.new(response.body).object

        yield obj

        # Use ETag to ensure object has not changed.
        headers = headers.merge("If-Match" => obj.etag)
        begin
          request(:post, method_url, headers, obj.xml.to_s)
          break
        rescue HttpError => e
          attempts -= 1
          # Will get 412 ("Precondition Failed" if ETag mismatches)
          raise if e.status != 412 || attempts == 0
        end
      end
    end
  end
end
