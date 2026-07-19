###############################################################################
# tf_mod_aws_inspector2 — main
#
# Keystone: aws_inspector2_enabler.this (guarded by var.enable_scanning). The
# other resources are independently toggleable control-plane switches so the
# module can be invoked from whichever account owns each action (management
# account for delegated-admin, delegated-admin account for org configuration).
#
# Ordering: aws_inspector2_organization_configuration depends_on the
# delegated-admin resource so that, when both are created in a single call, the
# delegated administrator is registered before the org policy is applied (the
# provider enforces this at the API level, not at plan time — see SCOPE.md).
#
# Only aws_inspector2_filter is taggable; var.tags is wired to filters only.
###############################################################################

# --- Scan enabler (keystone) -----------------------------------------------

resource "aws_inspector2_enabler" "this" {
 for_each = var.enable_scanning ? { this = true }: {}

 account_ids = var.account_ids
 resource_types = var.resource_types

 dynamic "timeouts" {
 for_each = (try(var.timeouts.create, null) != null || try(var.timeouts.update, null) != null || try(var.timeouts.delete, null) != null) ? [var.timeouts]: []
 content {
 create = try(timeouts.value.create, null)
 update = try(timeouts.value.update, null)
 delete = try(timeouts.value.delete, null)
 }
 }
}

# --- Delegated administrator (run from the Organizations management account) -

resource "aws_inspector2_delegated_admin_account" "this" {
 for_each = var.enable_delegated_admin ? { this = var.delegated_admin_account_id }: {}

 account_id = each.value

 dynamic "timeouts" {
 for_each = (try(var.timeouts.create, null) != null || try(var.timeouts.delete, null) != null) ? [var.timeouts]: []
 content {
 create = try(timeouts.value.create, null)
 delete = try(timeouts.value.delete, null)
 }
 }
}

# --- Organization configuration (run from the delegated administrator account)

resource "aws_inspector2_organization_configuration" "this" {
 for_each = var.enable_organization_configuration ? { this = var.organization_auto_enable }: {}

 auto_enable {
 ec2 = each.value.ec2
 ecr = each.value.ecr
 code_repository = each.value.code_repository
 lambda = each.value.lambda
 lambda_code = each.value.lambda_code
 }

 dynamic "timeouts" {
 for_each = (try(var.timeouts.create, null) != null || try(var.timeouts.update, null) != null || try(var.timeouts.delete, null) != null) ? [var.timeouts]: []
 content {
 create = try(timeouts.value.create, null)
 update = try(timeouts.value.update, null)
 delete = try(timeouts.value.delete, null)
 }
 }

 # The delegated administrator must be registered before the org policy is
 # applied. No attribute reference links them (they typically run from
 # different accounts), so encode the ordering explicitly for the single-call
 # case where both are created here.
 depends_on = [aws_inspector2_delegated_admin_account.this]
}

# --- Member associations (manual, non-Organizations membership path) --------

resource "aws_inspector2_member_association" "this" {
 for_each = var.member_account_ids

 account_id = coalesce(each.value.account_id, each.key)

 dynamic "timeouts" {
 for_each = (try(var.timeouts.create, null) != null || try(var.timeouts.delete, null) != null) ? [var.timeouts]: []
 content {
 create = try(timeouts.value.create, null)
 delete = try(timeouts.value.delete, null)
 }
 }
}

# --- Suppression / noise-reduction filters ---------------------------------

resource "aws_inspector2_filter" "this" {
 for_each = var.filters

 name = each.key
 action = each.value.action
 description = try(each.value.description, null)
 reason = try(each.value.reason, null)

 filter_criteria {
 # --- String filters (comparison, value) ---
 dynamic "aws_account_id" {
 for_each = coalesce(each.value.filter_criteria.aws_account_id, [])
 content {
 comparison = aws_account_id.value.comparison
 value = aws_account_id.value.value
 }
 }
 dynamic "code_repository_project_name" {
 for_each = coalesce(each.value.filter_criteria.code_repository_project_name, [])
 content {
 comparison = code_repository_project_name.value.comparison
 value = code_repository_project_name.value.value
 }
 }
 dynamic "code_repository_provider_type" {
 for_each = coalesce(each.value.filter_criteria.code_repository_provider_type, [])
 content {
 comparison = code_repository_provider_type.value.comparison
 value = code_repository_provider_type.value.value
 }
 }
 dynamic "code_vulnerability_detector_name" {
 for_each = coalesce(each.value.filter_criteria.code_vulnerability_detector_name, [])
 content {
 comparison = code_vulnerability_detector_name.value.comparison
 value = code_vulnerability_detector_name.value.value
 }
 }
 dynamic "code_vulnerability_detector_tags" {
 for_each = coalesce(each.value.filter_criteria.code_vulnerability_detector_tags, [])
 content {
 comparison = code_vulnerability_detector_tags.value.comparison
 value = code_vulnerability_detector_tags.value.value
 }
 }
 dynamic "code_vulnerability_file_path" {
 for_each = coalesce(each.value.filter_criteria.code_vulnerability_file_path, [])
 content {
 comparison = code_vulnerability_file_path.value.comparison
 value = code_vulnerability_file_path.value.value
 }
 }
 dynamic "component_id" {
 for_each = coalesce(each.value.filter_criteria.component_id, [])
 content {
 comparison = component_id.value.comparison
 value = component_id.value.value
 }
 }
 dynamic "component_type" {
 for_each = coalesce(each.value.filter_criteria.component_type, [])
 content {
 comparison = component_type.value.comparison
 value = component_type.value.value
 }
 }
 dynamic "ec2_instance_image_id" {
 for_each = coalesce(each.value.filter_criteria.ec2_instance_image_id, [])
 content {
 comparison = ec2_instance_image_id.value.comparison
 value = ec2_instance_image_id.value.value
 }
 }
 dynamic "ec2_instance_subnet_id" {
 for_each = coalesce(each.value.filter_criteria.ec2_instance_subnet_id, [])
 content {
 comparison = ec2_instance_subnet_id.value.comparison
 value = ec2_instance_subnet_id.value.value
 }
 }
 dynamic "ec2_instance_vpc_id" {
 for_each = coalesce(each.value.filter_criteria.ec2_instance_vpc_id, [])
 content {
 comparison = ec2_instance_vpc_id.value.comparison
 value = ec2_instance_vpc_id.value.value
 }
 }
 dynamic "ecr_image_architecture" {
 for_each = coalesce(each.value.filter_criteria.ecr_image_architecture, [])
 content {
 comparison = ecr_image_architecture.value.comparison
 value = ecr_image_architecture.value.value
 }
 }
 dynamic "ecr_image_hash" {
 for_each = coalesce(each.value.filter_criteria.ecr_image_hash, [])
 content {
 comparison = ecr_image_hash.value.comparison
 value = ecr_image_hash.value.value
 }
 }
 dynamic "ecr_image_registry" {
 for_each = coalesce(each.value.filter_criteria.ecr_image_registry, [])
 content {
 comparison = ecr_image_registry.value.comparison
 value = ecr_image_registry.value.value
 }
 }
 dynamic "ecr_image_repository_name" {
 for_each = coalesce(each.value.filter_criteria.ecr_image_repository_name, [])
 content {
 comparison = ecr_image_repository_name.value.comparison
 value = ecr_image_repository_name.value.value
 }
 }
 dynamic "ecr_image_tags" {
 for_each = coalesce(each.value.filter_criteria.ecr_image_tags, [])
 content {
 comparison = ecr_image_tags.value.comparison
 value = ecr_image_tags.value.value
 }
 }
 dynamic "exploit_available" {
 for_each = coalesce(each.value.filter_criteria.exploit_available, [])
 content {
 comparison = exploit_available.value.comparison
 value = exploit_available.value.value
 }
 }
 dynamic "finding_arn" {
 for_each = coalesce(each.value.filter_criteria.finding_arn, [])
 content {
 comparison = finding_arn.value.comparison
 value = finding_arn.value.value
 }
 }
 dynamic "finding_status" {
 for_each = coalesce(each.value.filter_criteria.finding_status, [])
 content {
 comparison = finding_status.value.comparison
 value = finding_status.value.value
 }
 }
 dynamic "finding_type" {
 for_each = coalesce(each.value.filter_criteria.finding_type, [])
 content {
 comparison = finding_type.value.comparison
 value = finding_type.value.value
 }
 }
 dynamic "fix_available" {
 for_each = coalesce(each.value.filter_criteria.fix_available, [])
 content {
 comparison = fix_available.value.comparison
 value = fix_available.value.value
 }
 }
 dynamic "lambda_function_execution_role_arn" {
 for_each = coalesce(each.value.filter_criteria.lambda_function_execution_role_arn, [])
 content {
 comparison = lambda_function_execution_role_arn.value.comparison
 value = lambda_function_execution_role_arn.value.value
 }
 }
 dynamic "lambda_function_layers" {
 for_each = coalesce(each.value.filter_criteria.lambda_function_layers, [])
 content {
 comparison = lambda_function_layers.value.comparison
 value = lambda_function_layers.value.value
 }
 }
 dynamic "lambda_function_name" {
 for_each = coalesce(each.value.filter_criteria.lambda_function_name, [])
 content {
 comparison = lambda_function_name.value.comparison
 value = lambda_function_name.value.value
 }
 }
 dynamic "lambda_function_runtime" {
 for_each = coalesce(each.value.filter_criteria.lambda_function_runtime, [])
 content {
 comparison = lambda_function_runtime.value.comparison
 value = lambda_function_runtime.value.value
 }
 }
 dynamic "network_protocol" {
 for_each = coalesce(each.value.filter_criteria.network_protocol, [])
 content {
 comparison = network_protocol.value.comparison
 value = network_protocol.value.value
 }
 }
 dynamic "related_vulnerabilities" {
 for_each = coalesce(each.value.filter_criteria.related_vulnerabilities, [])
 content {
 comparison = related_vulnerabilities.value.comparison
 value = related_vulnerabilities.value.value
 }
 }
 dynamic "resource_id" {
 for_each = coalesce(each.value.filter_criteria.resource_id, [])
 content {
 comparison = resource_id.value.comparison
 value = resource_id.value.value
 }
 }
 dynamic "resource_type" {
 for_each = coalesce(each.value.filter_criteria.resource_type, [])
 content {
 comparison = resource_type.value.comparison
 value = resource_type.value.value
 }
 }
 dynamic "severity" {
 for_each = coalesce(each.value.filter_criteria.severity, [])
 content {
 comparison = severity.value.comparison
 value = severity.value.value
 }
 }
 dynamic "title" {
 for_each = coalesce(each.value.filter_criteria.title, [])
 content {
 comparison = title.value.comparison
 value = title.value.value
 }
 }
 dynamic "vendor_severity" {
 for_each = coalesce(each.value.filter_criteria.vendor_severity, [])
 content {
 comparison = vendor_severity.value.comparison
 value = vendor_severity.value.value
 }
 }
 dynamic "vulnerability_id" {
 for_each = coalesce(each.value.filter_criteria.vulnerability_id, [])
 content {
 comparison = vulnerability_id.value.comparison
 value = vulnerability_id.value.value
 }
 }
 dynamic "vulnerability_source" {
 for_each = coalesce(each.value.filter_criteria.vulnerability_source, [])
 content {
 comparison = vulnerability_source.value.comparison
 value = vulnerability_source.value.value
 }
 }

 # --- Number filters (lower_inclusive, upper_inclusive) ---
 dynamic "ecr_image_in_use_count" {
 for_each = coalesce(each.value.filter_criteria.ecr_image_in_use_count, [])
 content {
 lower_inclusive = ecr_image_in_use_count.value.lower_inclusive
 upper_inclusive = ecr_image_in_use_count.value.upper_inclusive
 }
 }
 dynamic "epss_score" {
 for_each = coalesce(each.value.filter_criteria.epss_score, [])
 content {
 lower_inclusive = epss_score.value.lower_inclusive
 upper_inclusive = epss_score.value.upper_inclusive
 }
 }
 dynamic "inspector_score" {
 for_each = coalesce(each.value.filter_criteria.inspector_score, [])
 content {
 lower_inclusive = inspector_score.value.lower_inclusive
 upper_inclusive = inspector_score.value.upper_inclusive
 }
 }

 # --- Date filters (start_inclusive, end_inclusive; RFC3339) ---
 dynamic "ecr_image_last_in_use_at" {
 for_each = coalesce(each.value.filter_criteria.ecr_image_last_in_use_at, [])
 content {
 start_inclusive = try(ecr_image_last_in_use_at.value.start_inclusive, null)
 end_inclusive = try(ecr_image_last_in_use_at.value.end_inclusive, null)
 }
 }
 dynamic "ecr_image_pushed_at" {
 for_each = coalesce(each.value.filter_criteria.ecr_image_pushed_at, [])
 content {
 start_inclusive = try(ecr_image_pushed_at.value.start_inclusive, null)
 end_inclusive = try(ecr_image_pushed_at.value.end_inclusive, null)
 }
 }
 dynamic "first_observed_at" {
 for_each = coalesce(each.value.filter_criteria.first_observed_at, [])
 content {
 start_inclusive = try(first_observed_at.value.start_inclusive, null)
 end_inclusive = try(first_observed_at.value.end_inclusive, null)
 }
 }
 dynamic "lambda_function_last_modified_at" {
 for_each = coalesce(each.value.filter_criteria.lambda_function_last_modified_at, [])
 content {
 start_inclusive = try(lambda_function_last_modified_at.value.start_inclusive, null)
 end_inclusive = try(lambda_function_last_modified_at.value.end_inclusive, null)
 }
 }
 dynamic "last_observed_at" {
 for_each = coalesce(each.value.filter_criteria.last_observed_at, [])
 content {
 start_inclusive = try(last_observed_at.value.start_inclusive, null)
 end_inclusive = try(last_observed_at.value.end_inclusive, null)
 }
 }
 dynamic "updated_at" {
 for_each = coalesce(each.value.filter_criteria.updated_at, [])
 content {
 start_inclusive = try(updated_at.value.start_inclusive, null)
 end_inclusive = try(updated_at.value.end_inclusive, null)
 }
 }

 # --- Map filter (comparison, key, value) ---
 dynamic "resource_tags" {
 for_each = coalesce(each.value.filter_criteria.resource_tags, [])
 content {
 comparison = resource_tags.value.comparison
 key = resource_tags.value.key
 value = resource_tags.value.value
 }
 }

 # --- Port range filter (begin_inclusive, end_inclusive) ---
 dynamic "port_range" {
 for_each = coalesce(each.value.filter_criteria.port_range, [])
 content {
 begin_inclusive = port_range.value.begin_inclusive
 end_inclusive = port_range.value.end_inclusive
 }
 }

 # --- Package filter (vulnerable_packages) ---
 dynamic "vulnerable_packages" {
 for_each = coalesce(each.value.filter_criteria.vulnerable_packages, [])
 content {
 dynamic "architecture" {
 for_each = coalesce(vulnerable_packages.value.architecture, [])
 content {
 comparison = architecture.value.comparison
 value = architecture.value.value
 }
 }
 dynamic "epoch" {
 for_each = coalesce(vulnerable_packages.value.epoch, [])
 content {
 lower_inclusive = epoch.value.lower_inclusive
 upper_inclusive = epoch.value.upper_inclusive
 }
 }
 dynamic "file_path" {
 for_each = coalesce(vulnerable_packages.value.file_path, [])
 content {
 comparison = file_path.value.comparison
 value = file_path.value.value
 }
 }
 dynamic "name" {
 for_each = coalesce(vulnerable_packages.value.name, [])
 content {
 comparison = name.value.comparison
 value = name.value.value
 }
 }
 dynamic "release" {
 for_each = coalesce(vulnerable_packages.value.release, [])
 content {
 comparison = release.value.comparison
 value = release.value.value
 }
 }
 dynamic "source_lambda_layer_arn" {
 for_each = coalesce(vulnerable_packages.value.source_lambda_layer_arn, [])
 content {
 comparison = source_lambda_layer_arn.value.comparison
 value = source_lambda_layer_arn.value.value
 }
 }
 dynamic "source_layer_hash" {
 for_each = coalesce(vulnerable_packages.value.source_layer_hash, [])
 content {
 comparison = source_layer_hash.value.comparison
 value = source_layer_hash.value.value
 }
 }
 dynamic "version" {
 for_each = coalesce(vulnerable_packages.value.version, [])
 content {
 comparison = version.value.comparison
 value = version.value.value
 }
 }
 }
 }
 }

 # The only Inspector2 resource that supports tags: module tags + per-filter
 # tags (per-filter wins on key conflict).
 tags = merge(var.tags, try(each.value.tags, {}))
}
