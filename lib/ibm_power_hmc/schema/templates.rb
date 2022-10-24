# frozen_string_literal: true

module IbmPowerHmc
  class PartitionTemplateSummary < AbstractRest
    ATTRS = {
      :name => "partitionTemplateName"
    }.freeze
  end

  class PartitionTemplate < AbstractRest
    ATTRS = {
      :name         => "partitionTemplateName",
      :description  => "description",
      :lpar_name    => "logicalPartitionConfig/partitionName",
      :lpar_type    => "logicalPartitionConfig/partitionType",
      :lpar_id      => "logicalPartitionConfig/partitionId",
      :os           => "logicalPartitionConfig/osVersion",
      :memory       => "logicalPartitionConfig/memoryConfiguration/currMemory",
      :dedicated    => "logicalPartitionConfig/processorConfiguration/hasDedicatedProcessors",
      :sharing_mode => "logicalPartitionConfig/processorConfiguration/sharingMode",
      :vprocs       => "logicalPartitionConfig/processorConfiguration/sharedProcessorConfiguration/desiredVirtualProcessors",
      :proc_units   => "logicalPartitionConfig/processorConfiguration/sharedProcessorConfiguration/desiredProcessingUnits",
      :procs        => "logicalPartitionConfig/processorConfiguration/dedicatedProcessorConfiguration/desiredProcessors"
    }.freeze

    def vscsi
      REXML::XPath.match(xml, 'logicalPartitionConfig/virtualSCSIClientAdapters/VirtualSCSIClientAdapter').map do |adap|
        {
          :vios     => adap.elements['connectingPartitionName']&.text,
          :physvol  => adap.elements['associatedPhysicalVolume/PhysicalVolume/name']&.text,
        }
      end
    end

    def vscsi=(list = [])
      adaps = REXML::Element.new('virtualSCSIClientAdapters')
      adaps.add_attribute('schemaVersion', 'V1_5_0')
      list.each do |vscsi|
        adaps.add_element('VirtualSCSIClientAdapter', {'schemaVersion' => 'V1_5_0'}).tap do |v|
          v.add_element('associatedLogicalUnits', {'schemaVersion' => 'V1_5_0'})
          v.add_element('associatedPhysicalVolume', {'schemaVersion' => 'V1_5_0'}).tap do |e|
            e.add_element('PhysicalVolume', {'schemaVersion' => 'V1_5_0'}).add_element('name').text = vscsi[:physvol] if vscsi[:physvol]
          end
          v.add_element('connectingPartitionName').text = vscsi[:vios]
          v.add_element('AssociatedTargetDevices', {'schemaVersion' => 'V1_5_0'})
          v.add_element('associatedVirtualOpticalMedia', {'schemaVersion' => 'V1_5_0'})
        end
      end
      if xml.elements['logicalPartitionConfig/virtualSCSIClientAdapters']
        xml.elements['logicalPartitionConfig/virtualSCSIClientAdapters'] = adaps
      else
        xml.elements['logicalPartitionConfig'].add_element(adaps)
      end
    end

    def vfc
      REXML::XPath.match(xml, 'logicalPartitionConfig/virtualFibreChannelClientAdapters/VirtualFibreChannelClientAdapter').map do |adap|
        {
          :vios => adap.elements['connectingPartitionName']&.text,
          :port => adap.elements['portName']&.text
        }
      end
    end

    def vfc=(list = [])
      adaps = REXML::Element.new('virtualFibreChannelClientAdapters')
      adaps.add_attribute('schemaVersion', 'V1_5_0')
      list.each do |vfc|
        adaps.add_element('VirtualFibreChannelClientAdapter', {'schemaVersion' => 'V1_5_0'}).tap do |v|
          v.add_element('connectingPartitionName').text = vfc[:vios]
          v.add_element('portName').text                = vfc[:port]
        end
      end
      if xml.elements['logicalPartitionConfig/virtualFibreChannelClientAdapters']
        xml.elements['logicalPartitionConfig/virtualFibreChannelClientAdapters'] = adaps
      else
        xml.elements['logicalPartitionConfig'].add_element(adaps)
      end
    end

    def vlans
      REXML::XPath.match(xml, 'logicalPartitionConfig/clientNetworkAdapters/ClientNetworkAdapter/clientVirtualNetworks/ClientVirtualNetwork').map do |vlan|
        {
          :name    => vlan.elements['name']&.text,
          :vlan_id => vlan.elements['vlanId']&.text,
          :switch  => vlan.elements['associatedSwitchName']&.text
        }
      end
    end

    def vlans=(list = [])
      adaps = REXML::Element.new('clientNetworkAdapters')
      adaps.add_attribute('schemaVersion', 'V1_5_0')
      list.each do |vlan|
        adaps.add_element('ClientNetworkAdapter',  {'schemaVersion' => 'V1_5_0'})
             .add_element('clientVirtualNetworks', {'schemaVersion' => 'V1_5_0'})
             .add_element('ClientVirtualNetwork',  {'schemaVersion' => 'V1_5_0'})
             .tap do |v|
          v.add_element('name').text                 = vlan[:name]
          v.add_element('vlanId').text               = vlan[:vlan_id]
          v.add_element('associatedSwitchName').text = vlan[:switch]
        end
      end
      xml.elements['logicalPartitionConfig/clientNetworkAdapters'] = adaps
    end
  end
end
