# frozen_string_literal: true

module IbmPowerHmc
  # Serviceable Event
  class ServiceableEvent < AbstractRest
    ATTRS = {
      :prob_uuid => "problemUuid",
      :hostname => "reportingConsoleNode/hostName",
      :number => "problemNumber",
      :hw_record => "problemManagementHardwareRecord",
      :description => "shortDescription",
      :state => "problemState",
      :approval_state => "ApprovalState",
      :refcode => "referenceCode",
      :refcode_ext => "referenceCodeExtension",
      :refcode_sys => "systemReferenceCode",
      :call_home => "callHomeEnabled",
      :dup_count => "duplicateCount",
      :severity => "eventSeverity",
      :notif_type => "notificationType",
      :notif_status => "notificationStatus",
      :post_action => "postAction",
      :symptom => "symptomString",
      :lpar_id => "partitionId",
      :lpar_name => "partitionName",
      :lpar_hostname => "partitionHostName",
      :lpar_ostype => "partitionOSType",
      :syslog_id => "sysLogId",
      :total_events => "totalEvents"
    }.freeze

    def reporting_mtms
      mtms("reportingManagedSystemNode")
    end

    def failing_mtms
      mtms("failingManagedSystemNode")
    end

    def time
      timestamp("primaryTimestamp")
    end

    def created_time
      timestamp("createdTimestamp")
    end

    def first_reported_time
      timestamp("firstReportedTimestamp")
    end

    def last_reported_time
      timestamp("lastReportedTimestamp")
    end

    def frus
      collection_of("fieldReplaceableUnits", "FieldReplaceableUnit")
    end

    def ext_files
      collection_of("extendedErrorData", "ExtendedFileData")
    end

    private

    def mtms(prefix)
      machtype = singleton("#{prefix}/managedTypeModelSerial/MachineType")
      model = singleton("#{prefix}/managedTypeModelSerial/Model")
      serial = singleton("#{prefix}/managedTypeModelSerial/SerialNumber")
      "#{machtype}-#{model}*#{serial}"
    end
  end

  class FieldReplaceableUnit < AbstractNonRest
    ATTRS = {
      :part_number => "partNumber",
      :fru_class => "class",
      :description => "fieldReplaceableUnitDescription",
      :location => "locationCode",
      :serial => "SerialNumber",
      :ccin => "ccin"
    }.freeze
  end

  class ExtendedFileData < AbstractNonRest
    ATTRS = {
      :filename    => "fileName",
      :description => "description",
      :zipfilename => "zipFileName"
    }.freeze
  end
end
