# frozen_string_literal: true

require 'time'
require 'uri'

module IbmPowerHmc
  ##
  # Generic parser for HMC XML responses.
  class Parser
    def initialize(body)
      @doc = REXML::Document.new(body)
    end

    ##
    # @!method entry
    # Return the first entry element in the response.
    # @return [REXML::Element, nil] The first entry element.
    def entry
      @doc.elements["entry"]
    end

    ##
    # @!method object(filter_type = nil)
    # Parse the first entry element into an object.
    # @param filter_type [String] Entry type must match the specified type.
    # @return [IbmPowerHmc::AbstractRest, nil] The parsed object.
    def object(filter_type = nil)
      self.class.to_obj(entry, filter_type)
    end

    def self.to_obj(entry, filter_type = nil)
      return if entry.nil?

      content = entry.elements["content"]
      return if content.nil?

      type = content.attributes["type"]
      return if type.nil?

      type = type.split("=").last
      return unless filter_type.nil? || filter_type.to_s == type

      Module.const_get("IbmPowerHmc::#{type}").new(entry)
    end
  end

  ##
  # Parser for HMC feeds.
  # A feed encapsulates a list of entries like this:
  # <feed>
  #   <entry>
  #     <!-- entry #1 -->
  #   </entry>
  #   <entry>
  #     <!-- entry #2 -->
  #   </entry>
  #   ...
  # </feed>
  class FeedParser < Parser
    def entries
      objs = []
      @doc.each_element("feed/entry") do |entry|
        objs << yield(entry)
      end
      objs
    end

    ##
    # @!method objects(filter_type = nil)
    # Parse feed entries into objects.
    # @param filter_type [String] Filter entries based on content type.
    # @return [Array<IbmPowerHmc::AbstractRest>] The list of objects.
    def objects(filter_type = nil)
      entries do |entry|
        self.class.to_obj(entry, filter_type)
      end.compact
    end
  end

  private_constant :Parser
  private_constant :FeedParser

  ##
  # HMC generic XML entry.
  # Encapsulate data for a single object.
  # The XML looks like this:
  # <entry>
  #   <id>uuid</id>
  #   <published>timestamp</published>
  #   <etag:etag>ETag</etag:etag>
  #   <content type="type">
  #     <!-- actual content here -->
  #   </content>
  # </entry>
  #
  # @abstract
  # @attr_reader [String] uuid The UUID of the object contained in the entry.
  # @attr_reader [Time] published The time at which the entry was published.
  # @attr_reader [String] etag The entity tag of the entry.
  # @attr_reader [String] content_type The content type of the object contained in the entry.
  # @attr_reader [REXML::Document] xml The XML document representing this object.
  class AbstractRest
    ATTRS = {}.freeze
    attr_reader :uuid, :published, :etag, :content_type, :xml

    def initialize(doc)
      @uuid = doc.elements["id"]&.text
      @published = Time.xmlschema(doc.elements["published"]&.text)
      @etag = doc.elements["etag:etag"]&.text&.strip
      content = doc.elements["content"]
      @content_type = content.attributes["type"]
      @xml = content.elements.first
      define_attrs(self.class::ATTRS)
    end

    ##
    # @!method define_attr(varname, xpath)
    # Define an instance variable using the text of an XML element as value.
    # @param varname [String] The name of the instance variable.
    # @param xpath [String] The XPath of the XML element containing the text.
    def define_attr(varname, xpath)
      value = text_element(xpath)
      self.class.__send__(:attr_reader, varname)
      instance_variable_set("@#{varname}", value)
    end

    ##
    # @!method define_attrs(hash)
    # Define instance variables using the texts of XML elements as values.
    # @param hash [Hash] The name of the instance variables and the XPaths
    #   of the XML elements containing the values.
    def define_attrs(hash)
      hash.each do |key, value|
        define_attr(key, value)
      end
    end

    ##
    # @!method text_element(xpath)
    # Get the text of an XML element.
    # @param xpath [String] The XPath of the XML element.
    # @return [String, nil] The text of the XML element or nil.
    # @example lpar.text_element("PartitionProcessorConfiguration/MaximumVirtualProcessors").to_i
    def text_element(xpath)
      xml.elements[xpath]&.text&.strip
    end

    def extract_uuid_from_href(href)
      URI(href).path.split('/').last
    end
  end

  # HMC information
  class ManagementConsole < AbstractRest
    ATTRS = {
      :name => "ManagementConsoleName",
      :build_level => "VersionInfo/BuildLevel",
      :version => "BaseVersion"
    }.freeze

    def managed_systems_uuids
      xml.get_elements("ManagedSystems/link").map do |link|
        extract_uuid_from_href(link.attributes["href"])
      end.compact
    end
  end

  # Managed System information
  class ManagedSystem < AbstractRest
    ATTRS = {
      :name => "SystemName",
      :state => "State",
      :hostname => "Hostname",
      :ipaddr => "PrimaryIPAddress",
      :fwversion => "SystemFirmware",
      :memory => "AssociatedSystemMemoryConfiguration/InstalledSystemMemory",
      :avail_mem => "AssociatedSystemMemoryConfiguration/CurrentAvailableSystemMemory",
      :cpus => "AssociatedSystemProcessorConfiguration/InstalledSystemProcessorUnits",
      :avail_cpus => "AssociatedSystemProcessorConfiguration/CurrentAvailableSystemProcessorUnits",
      :mtype => "MachineTypeModelAndSerialNumber/MachineType",
      :model => "MachineTypeModelAndSerialNumber/Model",
      :serial => "MachineTypeModelAndSerialNumber/SerialNumber"
    }.freeze

    def lpars_uuids
      xml.get_elements("AssociatedLogicalPartitions/link").map do |link|
        extract_uuid_from_href(link.attributes["href"])
      end.compact
    end

    def vioses_uuids
      xml.get_elements("AssociatedVirtualIOServers/link").map do |link|
        extract_uuid_from_href(link.attributes["href"])
      end.compact
    end
  end

  # Common class for LPAR and VIOS
  class BasePartition < AbstractRest
    ATTRS = {
      :name => "PartitionName",
      :id => "PartitionID",
      :state => "PartitionState",
      :type => "PartitionType",
      :memory => "PartitionMemoryConfiguration/CurrentMemory",
      :dedicated => "PartitionProcessorConfiguration/HasDedicatedProcessors",
      :rmc_state => "ResourceMonitoringControlState",
      :rmc_ipaddr => "ResourceMonitoringIPAddress",
      :os => "OperatingSystemVersion",
      :ref_code => "ReferenceCode"
    }.freeze

    def sys_uuid
      sys_href = xml.elements["AssociatedManagedSystem"].attributes["href"]
      extract_uuid_from_href(sys_href)
    end
  end

  # Logical Partition information
  class LogicalPartition < BasePartition
  end

  # VIOS information
  class VirtualIOServer < BasePartition
  end

  # Virtual Switch information
  class VirtualSwitch < AbstractRest
    attr_reader :sys_uuid

    ATTRS = {
      :id   => "SwitchID",
      :mode => "SwitchMode",
      :name => "SwitchName"
    }.freeze

    def initialize(doc)
      super(doc)
      sys_href = doc.elements["link[@rel='SELF']"].attributes["href"]
      @sys_uuid = URI(sys_href).path.split('/')[-3]
    end
  end

  # HMC Event
  class Event < AbstractRest
    ATTRS = {
      :id     => "EventID",
      :type   => "EventType",
      :data   => "EventData",
      :detail => "EventDetail"
    }.freeze
  end

  # Error response from HMC
  class HttpErrorResponse < AbstractRest
    ATTRS = {
      :status  => "HTTPStatus",
      :uri     => "RequestURI",
      :reason  => "ReasonCode",
      :message => "Message"
    }.freeze
  end

  # Job Response
  class JobResponse < AbstractRest
    ATTRS = {
      :id      => "JobID",
      :status  => "Status",
      :message => "ResponseException/Message"
    }.freeze

    def results
      results = {}
      xml.each_element("Results/JobParameter") do |result|
        name = result.elements["ParameterName"]&.text&.strip
        value = result.elements["ParameterValue"]&.text&.strip
        results[name] = value unless name.nil?
      end
      results
    end
  end
end
