# frozen_string_literal: true

# Module for IBM HMC Rest API Client
module IbmPowerHmc
  # HMC Job for long running operations
  class HmcJob
    def initialize(hc, method_url, operation, group, params)
      @hc = hc
      @method_url = method_url
      @operation = operation
      @group = group
      @params = params
    end

    def start
      headers = {
        content_type: "application/vnd.ibm.powervm.web+xml; type=JobRequest"
      }
      doc = REXML::Document.new("")
      doc.add_element("JobRequest:JobRequest", {
                        "xmlns:JobRequest" => "http://www.ibm.com/xmlns/systems/power/firmware/web/mc/2012_10/",
                        "xmlns" => "http://www.ibm.com/xmlns/systems/power/firmware/web/mc/2012_10/",
                        "schemaVersion" => "V1_1_0"
                      })
      op = doc.root.add_element("RequestedOperation", { "schemaVersion" => "V1_1_0" })
      op.add_element("OperationName").text = @operation
      op.add_element("GroupName").text = @group
      # Damien: ProgressType?
      jobparams = doc.root.add_element("JobParameters", { "schemaVersion" => "V1_1_0" })
      @params.each do |key, value|
        jobparam = jobparams.add_element("JobParameter", { "schemaVersion" => "V1_1_0" })
        jobparam.add_element("ParameterName").text = key
        jobparam.add_element("ParameterValue").text = value
      end
      response = @hc.request(:put, @method_url, headers, doc.to_s)
      doc = REXML::Document.new(response.body)
      info = doc.root.elements["content/JobResponse:JobResponse"]
      @id = info.elements["JobID"].text
    end

    def status
      # Damien: check id is defined
      method_url = "/rest/api/uom/jobs/#{@id}"
      headers = {
        content_type: "application/vnd.ibm.powervm.web+xml; type=JobRequest"
      }
      response = @hc.request(:get, method_url, headers)
      doc = REXML::Document.new(response.body)
      info = doc.root.elements["content/JobResponse:JobResponse"]
      status = info.elements["Status"].text
      # Damien: also retrieve "ResponseException/Message"
      status
    end

    def wait(timeout = 120, poll_interval = 30)
      endtime = Time.now + timeout
      while Time.now < endtime do
        status = self.status
        break if status != "RUNNING" # Damien: and != "STARTING"?
        sleep(poll_interval)
      end
    end

    def delete
      # Damien: check id is defined
      method_url = "/rest/api/uom/jobs/#{@id}"
      @hc.request(:delete, method_url)
      # Returns HTTP 204 if ok
    end
  end
end
