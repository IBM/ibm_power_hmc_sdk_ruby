# frozen_string_literal: true

# Module for IBM HMC Rest API Client
module IbmPowerHmc
  # HMC REST Client connection
  class Connection
    def initialize(host:, username: "hscroot", password:, port: 12_443, validate_ssl: true)
      # Damien: use URI::HTTPS
      @hostname = "#{host}:#{port}"
      @username = username
      @password = password
      @verify_ssl = validate_ssl
      @api_session_token = nil
    end

    def logon
      method_url = "/rest/api/web/Logon"
      headers = {
        content_type: "application/vnd.ibm.powervm.web+xml; type=LogonRequest"
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

    def logoff
      method_url = "/rest/api/web/Logon"
      request(:delete, method_url)
      @api_session_token = nil
    end

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

    def managed_systems
      method_url = "/rest/api/uom/ManagedSystem"
      response = request(:get, method_url)
      doc = REXML::Document.new(response.body)
      parse_feed(doc, ManagedSystem)
    end

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

    def lpar_quick_property(lpar_uuid, property_name)
      method_url = "/rest/api/uom/LogicalPartition/#{lpar_uuid}/quick/#{property_name}"

      response = request(:get, method_url)
      response.body[1..-2]
    end

    def vioses(sys_uuid = nil)
      if sys_uuid.nil?
        method_url = "/rest/api/uom/VirtualIOServer"
      else
        method_url = "/rest/api/uom/ManagedSystem/#{sys_uuid}/VirtualIOServer"
      end
      begin
        response = request(:get, method_url)
      rescue StandardError
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
      rescue StandardError
        return []
      end
      doc = REXML::Document.new(response.body)
      parse_feed(doc, LogicalPartitionProfile)
    end

    def poweron_lpar(lpar_uuid, params = {})
      method_url = "/rest/api/uom/LogicalPartition/#{lpar_uuid}/do/PowerOn"

      job = HmcJob.new(self, method_url, "PowerOn", "LogicalPartition", params)
      job.start
      job.wait
      job.delete
    end

    def poweroff_lpar(lpar_uuid, params = {})
      method_url = "/rest/api/uom/LogicalPartition/#{lpar_uuid}/do/PowerOff"

      job = HmcJob.new(self, method_url, "PowerOff", "LogicalPartition", params)
      job.start
      job.wait
      job.delete
    end

    # Damien: share with poweron_lpar?
    def poweron_vios(vios_uuid, params = {})
      method_url = "/rest/api/uom/VirtualIOServer/#{vios_uuid}/do/PowerOn"

      job = HmcJob.new(self, method_url, "PowerOn", "VirtualIOServer", params)
      job.start
      job.wait
      job.delete
    end

    # Damien: share with poweroff_lpar?
    def poweroff_vios(vios_uuid, params = {})
      method_url = "/rest/api/uom/VirtualIOServer/#{vios_uuid}/do/PowerOff"

      job = HmcJob.new(self, method_url, "PowerOff", "VirtualIOServer", params)
      job.start
      job.wait
      job.delete
    end

    def poweron_managed_system(sys_uuid, params = {})
      method_url = "/rest/api/uom/ManagedSystem/#{sys_uuid}/do/PowerOn"

      job = HmcJob.new(self, method_url, "PowerOn", "ManagedSystem", params)
      job.start
      job.wait
      job.delete
    end

    def poweroff_managed_system(sys_uuid, params = {})
      method_url = "/rest/api/uom/ManagedSystem/#{sys_uuid}/do/PowerOff"

      job = HmcJob.new(self, method_url, "PowerOff", "ManagedSystem", params)
      job.start
      job.wait
      job.delete
    end

    # Blocks until new events occur.
    def next_events
      method_url = "/rest/api/uom/Event"

      events = []
      loop do
        response = request(:get, method_url)
        next if response.code == 204

        doc = REXML::Document.new(response.body)
        doc.root.each_element("entry") do |entry|
          event = Event.new(entry)
          events += [event]
        end
        break
      end
      events
    end

    def request(method, url, headers = {}, payload = nil)
      logon if @api_session_token.nil?

      headers = headers.merge({ "X-API-Session" => @api_session_token })
      # Damien: use URI module and prepare in initialize?
      response = RestClient::Request.execute(
        method: method,
        url: "https://" + @hostname + url,
        verify_ssl: @verify_ssl,
        payload: payload,
        headers: headers
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
