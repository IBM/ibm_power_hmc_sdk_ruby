# frozen_string_literal: true

require 'time'
require 'uri'

module IbmPowerHmc
  ##
  # Generic parser for HMC K2 XML responses.
  class Parser
    def initialize(body)
      @doc = REXML::Document.new(body)
    end

    ##
    # @!method entry
    # Return the first K2 entry element in the response.
    # @return [REXML::Element, nil] The first entry element.
    def entry
      @doc.elements["entry"]
    end

    ##
    # @!method object(filter_type = nil)
    # Parse the first K2 entry element into an object.
    # @param filter_type [String] Entry type must match the specified type.
    # @return [IbmPowerHmc::AbstractRest, nil] The parsed object.
    def object(filter_type = nil)
      self.class.to_obj(entry, filter_type)
    end

    def self.to_obj(entry, filter_type = nil)
      return if entry.nil?

      content = entry.elements["content[@type]"]
      return if content.nil?

      type = content.attributes["type"].split("=").last
      return unless filter_type.nil? || filter_type.to_s == type

      Module.const_get("IbmPowerHmc::#{type}").new(entry)
    end
  end

  ##
  # Parser for HMC K2 feeds.
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
  # HMC generic K2 non-REST object.
  # @abstract
  # @attr_reader [REXML::Document] xml The XML document representing this object.
  class AbstractNonRest
    ATTRS = {}.freeze
    attr_reader :xml

    def initialize(xml)
      @xml = xml
      self.class::ATTRS.each { |varname, xpath| define_attr(varname, xpath) }
    end

    ##
    # @!method define_attr(varname, xpath)
    # Define an instance variable using the text of an XML element as value.
    # @param varname [String] The name of the instance variable.
    # @param xpath [String] The XPath of the XML element containing the text.
    def define_attr(varname, xpath)
      value = singleton(xpath)
      self.class.__send__(:attr_reader, varname)
      instance_variable_set("@#{varname}", value)
    end
    private :define_attr

    ##
    # @!method singleton(xpath, attr = nil)
    # Get the text (or the value of a specified attribute) of an XML element.
    # @param xpath [String] The XPath of the XML element.
    # @param attr [String] The name of the attribute.
    # @return [String, nil] The text or attribute value of the XML element or nil.
    # @example lpar.singleton("PartitionProcessorConfiguration/*/MaximumVirtualProcessors").to_i
    def singleton(xpath, attr = nil)
      elem = xml.elements[xpath]
      return if elem.nil?

      attr.nil? ? elem.text&.strip : elem.attributes[attr]
    end

    def extract_uuid_from_href(href)
      URI(href).path.split('/').last
    end
  end

  ##
  # HMC generic K2 REST object.
  # Encapsulate data for a single REST object.
  # The XML looks like this:
  # <entry>
  #   <id>uuid</id>
  #   <published>timestamp</published>
  #   <link rel="SELF" href="https://..."/>
  #   <etag:etag>ETag</etag:etag>
  #   <content type="type">
  #     <!-- actual content here -->
  #   </content>
  # </entry>
  #
  # @abstract
  # @attr_reader [String] uuid The UUID of the object contained in the entry.
  # @attr_reader [Time] published The time at which the entry was published.
  # @attr_reader [URI::HTTPS] href The URL of the object itself.
  # @attr_reader [String] etag The entity tag of the entry.
  # @attr_reader [String] content_type The content type of the object contained in the entry.
  class AbstractRest < AbstractNonRest
    attr_reader :uuid, :published, :href, :etag, :content_type

    def initialize(entry)
      @uuid = entry.elements["id"]&.text
      @published = Time.xmlschema(entry.elements["published"]&.text)
      link = entry.elements["link[@rel='SELF']"]
      @href = URI(link.attributes["href"]) unless link.nil?
      @etag = entry.elements["etag:etag"]&.text&.strip
      content = entry.elements["content"]
      @content_type = content.attributes["type"]
      super(content.elements.first)
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
      sys_href = singleton("AssociatedManagedSystem", "href")
      extract_uuid_from_href(sys_href)
    end

    def net_adap_uuids
      xml.get_elements("ClientNetworkAdapters/link").map do |link|
        extract_uuid_from_href(link.attributes["href"])
      end.compact
    end

    def name=(name)
      xml.elements[ATTRS[:name]].text = name
      @name = name
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
    ATTRS = {
      :id   => "SwitchID",
      :mode => "SwitchMode",
      :name => "SwitchName"
    }.freeze

    def sys_uuid
      href.path.split('/')[-3]
    end

    def networks_uuids
      xml.get_elements("VirtualNetworks/link").map do |link|
        extract_uuid_from_href(link.attributes["href"])
      end.compact
    end
  end

  # Virtual Network information
  class VirtualNetwork < AbstractRest
    ATTRS = {
      :name       => "NetworkName",
      :vlan_id    => "NetworkVLANID",
      :vswitch_id => "VswitchID",
      :tagged     => "TaggedNetwork"
    }.freeze

    def vswitch_uuid
      href = singleton("AssociatedSwitch", "href")
      extract_uuid_from_href(href)
    end

    def lpars_uuids
      xml.get_elements("ConnectedPartitions/link").map do |link|
        extract_uuid_from_href(link.attributes["href"])
      end.compact
    end
  end

  # Virtual I/O Adapter information
  class VirtualIOAdapter < AbstractRest
    ATTRS = {
      :type     => "AdapterType", # "Server", "Client", "Unknown"
      :location => "LocationCode",
      :slot     => "VirtualSlotNumber",
      :required => "RequiredAdapter"
    }.freeze
  end

  # Virtual Ethernet Adapter information
  class VirtualEthernetAdapter < VirtualIOAdapter
    ATTRS = ATTRS.merge({
      :macaddr    => "MACAddress",
      :vswitch_id => "VirtualSwitchID",
      :vlan_id    => "PortVLANID"
    }.freeze)

    def vswitch_uuid
      href = singleton("AssociatedVirtualSwitch/link", "href")
      extract_uuid_from_href(href)
    end
  end

  # Client Network Adapter information
  class ClientNetworkAdapter < VirtualEthernetAdapter
    def networks_uuids
      xml.get_elements("VirtualNetworks/link").map do |link|
        extract_uuid_from_href(link.attributes["href"])
      end.compact
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
      xml.each_element("Results/JobParameter") do |jobparam|
        name = jobparam.elements["ParameterName"]&.text&.strip
        value = jobparam.elements["ParameterValue"]&.text&.strip
        results[name] = value unless name.nil?
      end
      results
    end
  end
end
