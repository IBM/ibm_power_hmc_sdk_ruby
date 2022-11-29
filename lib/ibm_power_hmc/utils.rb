# frozen_string_literal: true

module IbmPowerHmc
  class Connection
    ##
    # @!method lpar_delete_vios_mappings
    # Delete VIOS VSCSI and VFC mappings associated to a given logical partition.
    # @param lpar_uuid [String] The logical partition UUID.
    def lpar_delete_vios_mappings(lpar_uuid)
      vscsi_client_adapter(lpar_uuid).concat(vfc_client_adapter(lpar_uuid)).group_by(&:vios_uuid).each do |vios_uuid, adapters|
        modify_object do
          vios(vios_uuid, nil, "ViosSCSIMapping,ViosFCMapping").tap do |vios|
            adapters.collect(&:server).each do |server|
              case server
              when VirtualSCSIServerAdapter
                vios.vscsi_mapping_delete!(server.location)
              when VirtualFibreChannelServerAdapter
                vios.vfc_mapping_delete!(server.location)
              end
            end
          end
        end
      end
    end
  end
end
