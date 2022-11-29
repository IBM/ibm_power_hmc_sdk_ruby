# frozen_string_literal: true

module IbmPowerHmc
  class Connection
    ##
    # @!method lpar_delete_vios_mappings(lpar_uuid)
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

    ##
    # @!method template_provision(template_uuid, target_sys_uuid, changes)
    # Deploy Logical Partition from a Template (performs Check, Transform and Deploy steps in a single method).
    # @param template_uuid [String] The UUID of the Template to deploy an LPAR from.
    # @param target_sys_uuid [String] The UUID of the Managed System to deploy the LPAR on.
    # @param changes [Hash] Modifications to apply to the Template before deploying Logical Partition.
    # @return [String] The UUID of the deployed Logical Partition.
    def template_provision(template_uuid, target_sys_uuid, changes)
      draft_uuid = template_check(template_uuid, target_sys_uuid).results["TEMPLATE_UUID"]
      template_transform(draft_uuid, target_sys_uuid)
      template_modify(draft_uuid, changes)
      template_deploy(draft_uuid, target_sys_uuid).results["PartitionUuid"]
    end
  end
end
