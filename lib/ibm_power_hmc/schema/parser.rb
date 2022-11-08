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

      type = content.attributes["type"].split("=")[1] || filter_type.to_s
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

    def self.marshall(attrs = {}, namespace = UOM_XMLNS, version = "V1_1_0")
      doc = REXML::Document.new("")
      doc.add_element(name.split("::").last, "schemaVersion" => version)
      doc.root.add_namespace(namespace)
      obj = new(doc.root)
      attrs.each do |varname, value|
        obj.send("#{varname}=", value)
      end
      obj
    end

    ##
    # @!method define_attr(varname, xpath)
    # Define an instance variable using the text of an XML element as value.
    # @param varname [String] The name of the instance variable.
    # @param xpath [String] The XPath of the XML element containing the text.
    def define_attr(varname, xpath)
      value = singleton(xpath)
      self.class.__send__(:attr_reader, varname)
      self.class.__send__(:define_method, "#{varname}=") do |v|
        if v.nil?
          xml.elements.delete(xpath)
        else
          create_element(xpath) if xml.elements[xpath].nil?
          xml.elements[xpath].text = v
        end
        instance_variable_set("@#{varname}", v)
      end
      instance_variable_set("@#{varname}", value)
    end
    private :define_attr

    ##
    # @!method create_element(xpath)
    # Create a new XML element.
    # @param xpath [String] The XPath of the XML element to create.
    def create_element(xpath)
      cur = xml
      xpath.split("/").each do |el|
        p = cur.elements[el]
        if p.nil?
          cur = cur.add_element(el)
        else
          cur = p
        end
      end
    end

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

    def to_s
      str = +"#{self.class.name}:\n"
      self.class::ATTRS.each do |varname, _|
        value = instance_variable_get("@#{varname}")
        value = value.nil? ? "null" : "'#{value}'"
        str << "  #{varname}: #{value}\n"
      end
      str
    end

    def uuid_from_href(href, index = -1)
      URI(href).path.split('/')[index]
    end

    def uuids_from_links(elem, index = -1)
      xml.get_elements("#{elem}/link[@href]").map do |link|
        uuid_from_href(link.attributes["href"], index)
      end.compact
    end

    def timestamp(xpath)
      # XML element containing a number of milliseconds since the Epoch.
      Time.at(0, singleton(xpath).to_i, :millisecond).utc
    end

    def collection_of(name, type)
      xml.get_elements([name, type].compact.join("/")).map do |elem|
        Module.const_get("IbmPowerHmc::#{elem.name}").new(elem)
      rescue NameError
        nil
      end.compact
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
      if entry.name != "entry"
        # We are inlined.
        super(entry)
        return
      end

      @uuid = entry.elements["id"]&.text
      @published = Time.xmlschema(entry.elements["published"]&.text)
      link = entry.elements["link[@rel='SELF']"]
      @href = URI(link.attributes["href"]) unless link.nil?
      @etag = entry.elements["etag:etag"]&.text&.strip
      content = entry.elements["content"]
      @content_type = content.attributes["type"]
      super(content.elements.first)
    end

    def to_s
      str = super
      str << "  uuid: '#{uuid}'\n" if defined?(@uuid)
      str << "  published: '#{published}'\n" if defined?(@published)
      str
    end
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
end
