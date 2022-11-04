# frozen_string_literal: true

module IbmPowerHmc
  # Job Request
  class JobRequest < AbstractRest
    def operation
      singleton("RequestedOperation/OperationName")
    end

    def operation=(operation)
      elem = xml.elements["RequestedOperation"]
      elem = xml.add_element("RequestedOperation", "schemaVersion" => "V1_1_0") if elem.nil?
      elem.add_element("OperationName").text = operation
    end

    def group
      singleton("RequestedOperation/GroupName")
    end

    def group=(group)
      elem = xml.elements["RequestedOperation"]
      elem = xml.add_element("RequestedOperation", "schemaVersion" => "V1_1_0") if elem.nil?
      elem.add_element("GroupName").text = group
    end

    def params
      params = {}
      xml.each_element("JobParameters/JobParameter") do |jobparam|
        name = jobparam.elements["ParameterName"]&.text&.strip
        value = jobparam.elements["ParameterValue"]&.text&.strip
        params[name] = value unless name.nil?
      end
      params
    end

    def params=(params)
      jobparams = xml.add_element("JobParameters", "schemaVersion" => "V1_1_0")
      params.each do |key, value|
        jobparam = jobparams.add_element("JobParameter", "schemaVersion" => "V1_1_0")
        jobparam.add_element("ParameterName").text = key
        jobparam.add_element("ParameterValue").text = value
      end
    end
  end

  # Job Response
  class JobResponse < AbstractRest
    ATTRS = {
      :id => "JobID",
      :status => "Status",
      :message => "ResponseException/Message",
      :target_uuid => "TargetUuid",
      :linear_progress => "Progress/LinearProgress"
    }.freeze

    def url
      singleton("RequestURL", "href")
    end

    def request
      elem = xml.elements["JobRequestInstance"]
      JobRequest.new(elem) unless elem.nil?
    end

    def started_at
      timestamp("TimeStarted")
    end

    def completed_at
      timestamp("TimeCompleted")
    end

    def results
      results = {}
      xml.each_element("Results/JobParameter") do |jobparam|
        name = jobparam.elements["ParameterName"]&.text&.strip
        value = jobparam.elements["ParameterValue"]&.text&.strip
        results[name] = value unless name.nil?
      end
      results
    end
  end
end
