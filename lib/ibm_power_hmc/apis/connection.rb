# frozen_string_literal: true

# Module for IBM HMC Rest API Client
module IbmPowerHmc
  WEB_XMLNS = "http://www.ibm.com/xmlns/systems/power/firmware/web/mc/2012_10/"
  UOM_XMLNS = "http://www.ibm.com/xmlns/systems/power/firmware/uom/mc/2012_10/"

  class Error < StandardError; end

  ##
  # HMC REST Client connection.
  class Connection
    ##
    # @!method initialize(host:, password:, username: "hscroot", port: 12_443, validate_ssl: true, timeout: 60)
    # Create a new HMC connection.
    #
    # @param host [String] Hostname of the HMC.
    # @param password [String] Password.
    # @param username [String] User name.
    # @param port [Integer] TCP port number.
    # @param validate_ssl [Boolean] Verify SSL certificates.
    # @param timeout [Integer] The default HTTP timeout in seconds.
    def initialize(host:, password:, username: "hscroot", port: 12_443, validate_ssl: true, timeout: 60)
      @hostname = "#{host}:#{port}"
      @username = username
      @password = password
      @verify_ssl = validate_ssl
      @api_session_token = nil
      @timeout = timeout
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
      doc.root.add_namespace(WEB_XMLNS)
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
    # @!method usertask(uuid = true)
    # Retrieve details of an event of type "user task".
    # @param uuid [String] UUID of user task.
    # @return [Hash] Hash of user task attributes.
    def usertask(uuid)
      method_url = "/rest/api/ui/UserTask/#{uuid}"
      response = request(:get, method_url)
      j = JSON.parse(response.body)
      if j['status'].eql?("Completed")
        case j['key']
        when "TEMPLATE_PARTITION_SAVE", "TEMPLATE_PARTITION_SAVE_AS", "TEMPLATE_PARTITION_CAPTURE"
          j['template_uuid'] = templates_summary.find { |t| t.name.eql?(j['labelParams'].first) }&.uuid
        end
      end
      j
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

        # Try to parse body as an HttpErrorResponse.
        unless err.response.nil?
          begin
            resp = Parser.new(err.response.body).object(:HttpErrorResponse)
            @uri = resp.uri
            @reason = resp.reason
            @message = resp.message
          rescue
            # not an XML body
          end
        end
      end

      def to_s
        %(msg="#{@message}" status="#{@status}" reason="#{@reason}" uri=#{@uri})
      end
    end

    class HttpNotFound < HttpError; end

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
          :headers => headers,
          :timeout => @timeout
        )
      rescue RestClient::Exception => e
        raise HttpNotFound.new(e), "Not found" if e.http_code == 404

        # Do not retry on failed logon attempts.
        if e.http_code == 401 && @api_session_token != "" && !reauth
          # Try to reauth.
          reauth = true
          logon
          retry
        end
        raise HttpError.new(e), "REST request failed"
      end
    end

    # @!method modify_object(headers = {}, attempts = 5)
    # Post an IbmPowerHmc::AbstractRest object iteratively using ETag.
    # @param headers [Hash] HTTP headers.
    # @param attempts [Integer] Maximum number of retries.
    # @yieldreturn [IbmPowerHmc::AbstractRest] The object to modify.
    def modify_object(headers = {}, attempts = 5, &block)
      modify_object_url(nil, headers, attempts, &block)
    end

    private

    def modify_object_url(method_url = nil, headers = {}, attempts = 5)
      while attempts > 0
        obj = yield
        raise "object has no href" if method_url.nil? && (!obj.kind_of?(AbstractRest) || obj.href.nil?)

        # Use ETag to ensure object has not changed.
        headers = headers.merge("If-Match" => obj.etag, :content_type => obj.content_type)
        begin
          request(:post, method_url.nil? ? obj.href.to_s : method_url, headers, obj.xml.to_s)
          break
        rescue HttpError => e
          attempts -= 1
          # Will get 412 ("Precondition Failed") if ETag mismatches.
          raise if e.status != 412 || attempts == 0
        end
      end
    end
  end
end
