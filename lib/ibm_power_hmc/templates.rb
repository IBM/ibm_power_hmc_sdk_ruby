# frozen_string_literal: true

module IbmPowerHmc
  class Connection
    ##
    # @!method templates_summary(draft = false)
    # Retrieve the list of partition template summaries.
    # @param draft [Boolean] Retrieve draft templates as well
    # @return [Array<IbmPowerHmc::PartitionTemplateSummary>] The list of partition template summaries.
    def templates_summary(draft = false)
      method_url = "/rest/api/templates/PartitionTemplate#{'?draft=false' unless draft}"
      response = request(:get, method_url)
      FeedParser.new(response.body).objects(:PartitionTemplateSummary)
    end

    ##
    # @!method templates(draft = false)
    # Retrieve the list of partition templates.
    # @param draft [Boolean] Retrieve draft templates as well
    # @return [Array<IbmPowerHmc::PartitionTemplate>] The list of partition templates.
    def templates(draft = false)
      method_url = "/rest/api/templates/PartitionTemplate?detail=full#{'&draft=false' unless draft}"
      response = request(:get, method_url)
      FeedParser.new(response.body).objects(:PartitionTemplate)
    end

    ##
    # @!method template(template_uuid)
    # Retrieve details for a particular partition template.
    # @param template_uuid [String] UUID of the partition template.
    # @return [IbmPowerHmc::PartitionTemplate] The partition template.
    def template(template_uuid)
      method_url = "/rest/api/templates/PartitionTemplate/#{template_uuid}"
      response = request(:get, method_url)
      Parser.new(response.body).object(:PartitionTemplate)
    end

    ##
    # @!method capture_lpar(lpar_uuid, sys_uuid, template_name, sync = true)
    # Capture partition configuration as template.
    # @param lpar_uuid [String] The UUID of the logical partition.
    # @param sys_uuid [String] The UUID of the managed system.
    # @param template_name [String] The name to be given for the new template.
    # @param sync [Boolean] Start the job and wait for its completion.
    # @return [IbmPowerHmc::HmcJob] The HMC job.
    def capture_lpar(lpar_uuid, sys_uuid, template_name, sync = true)
      # Need to include session token in payload so make sure we are logged in
      logon if @api_session_token.nil?
      method_url = "/rest/api/templates/PartitionTemplate/do/capture"
      params = {
        "TargetUuid"              => lpar_uuid,
        "NewTemplateName"         => template_name,
        "ManagedSystemUuid"       => sys_uuid,
        "K_X_API_SESSION_MEMENTO" => @api_session_token
      }
      job = HmcJob.new(self, method_url, "Capture", "PartitionTemplate", params)
      job.run if sync
      job
    end

    ##
    # @!method template_check(template_uuid, target_sys_uuid, sync = true)
    # Start Template Check job (first of three steps to deploy an LPAR from a Template).
    # @param template_uuid [String] The UUID of the Template to deploy an LPAR from.
    # @param target_sys_uuid [String] The UUID of the Managed System to deploy the LPAR on.
    # @param sync [Boolean] Start the job and wait for its completion.
    # @return [IbmPowerHmc::HmcJob] The HMC job.
    def template_check(template_uuid, target_sys_uuid, sync = true)
      # Need to include session token in payload so make sure we are logged in
      logon if @api_session_token.nil?
      method_url = "/rest/api/templates/PartitionTemplate/#{template_uuid}/do/check"
      params = {
        "TargetUuid"              => target_sys_uuid,
        "K_X_API_SESSION_MEMENTO" => @api_session_token
      }
      job = HmcJob.new(self, method_url, "Check", "PartitionTemplate", params)
      job.run if sync
      job
    end

    ##
    # @!method template_transform(draft_template_uuid, target_sys_uuid, sync = true)
    # Start Template Transform job (second of three steps to deploy an LPAR from a Template).
    # @param draft_template_uuid [String] The UUID of the Draft Template created by the Template Check job.
    # @param target_sys_uuid [String] The UUID of the Managed System to deploy the LPAR on.
    # @param sync [Boolean] Start the job and wait for its completion.
    # @return [IbmPowerHmc::HmcJob] The HMC job.
    def template_transform(draft_template_uuid, target_sys_uuid, sync = true)
      # Need to include session token in payload so make sure we are logged in
      logon if @api_session_token.nil?
      method_url = "/rest/api/templates/PartitionTemplate/#{draft_template_uuid}/do/transform"
      params = {
        "TargetUuid"              => target_sys_uuid,
        "K_X_API_SESSION_MEMENTO" => @api_session_token
      }
      job = HmcJob.new(self, method_url, "Transform", "PartitionTemplate", params)
      job.run if sync
      job
    end

    ##
    # @!method template_deploy(draft_template_uuid, target_sys_uuid, sync = true)
    # Start Template Deploy job (last of three steps to deploy an LPAR from a Template).
    # @param draft_template_uuid [String] The UUID of the Draft Template created by the Template Check job.
    # @param target_sys_uuid [String] The UUID of the Managed System to deploy the LPAR on.
    # @param sync [Boolean] Start the job and wait for its completion.
    # @return [IbmPowerHmc::HmcJob] The HMC job.
    def template_deploy(draft_template_uuid, target_sys_uuid, sync = true)
      # Need to include session token in payload so make sure we are logged in
      logon if @api_session_token.nil?
      method_url = "/rest/api/templates/PartitionTemplate/#{draft_template_uuid}/do/deploy"
      params = {
        "TargetUuid"              => target_sys_uuid,
        "TemplateUuid"            => draft_template_uuid,
        "K_X_API_SESSION_MEMENTO" => @api_session_token
      }
      job = HmcJob.new(self, method_url, "Deploy", "PartitionTemplate", params)
      job.run if sync
      job
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

    ##
    # @!method template_modify(template_uuid, changes)
    # Modify a template.
    # @param template_uuid [String] UUID of the partition template to modify.
    # @param changes [Hash] Hash of changes to make.
    def template_modify(template_uuid, changes)
      method_url = "/rest/api/templates/PartitionTemplate/#{template_uuid}"

      # Templates have no href so need to use modify_object_url.
      modify_object_url(method_url) do
        template(template_uuid).tap do |obj|
          changes.each do |key, value|
            obj.send("#{key}=", value)
          end
        end
      end
    end

    ##
    # @!method template_copy(template_uuid, new_name)
    # Copy existing template to a new one.
    # @param template_uuid [String] UUID of the partition template to copy.
    # @param new_name [String] Name of the new template.
    # @return [IbmPowerHmc::PartitionTemplate] The new partition template.
    def template_copy(template_uuid, new_name)
      method_url = "/rest/api/templates/PartitionTemplate"
      headers = {
        :content_type => "application/vnd.ibm.powervm.templates+xml;type=PartitionTemplate"
      }
      original = template(template_uuid)
      original.name = new_name
      response = request(:put, method_url, headers, original.xml.to_s)
      Parser.new(response.body).object(:PartitionTemplate)
    end
  end
end
