###############################################################################
# tf_mod_aws_inspector2 — outputs
#
# Inspector2 is a control-plane service: four of its five resources expose NO
# ARN and no meaningful standalone id (the enabler's id is a synthetic
# account_ids-resource_types composite string, not an AWS identifier other
# services reference). Outputs are therefore shaped around STATE (what is
# enabled / associated / suppressed), not cross-resource wiring. Only
# aws_inspector2_filter emits real ARNs and tags_all.
#
# All enabler / delegated-admin / org-config outputs use try(..., null) because
# each of those resources is behind a toggle and may not be created.
###############################################################################

# --- Scan enabler (keystone) -----------------------------------------------

output "id" {
 description = "Synthetic composite id of aws_inspector2_enabler.this ([account_ids]-[resource_types], provider-generated) — informational/state only, not an AWS ARN other modules reference. Null when enable_scanning is false."
 value = try(aws_inspector2_enabler.this["this"].id, null)
}

output "enabled_account_ids" {
 description = "The set of account IDs Inspector scanning was enabled for, or null when enable_scanning is false."
 value = try(aws_inspector2_enabler.this["this"].account_ids, null)
}

output "enabled_resource_types" {
 description = "The set of resource types being scanned (EC2/ECR/LAMBDA/LAMBDA_CODE/CODE_REPOSITORY), or null when enable_scanning is false."
 value = try(aws_inspector2_enabler.this["this"].resource_types, null)
}

# --- Delegated administrator -----------------------------------------------

output "delegated_admin_account_id" {
 description = "Account ID registered as the Inspector delegated administrator, or null when enable_delegated_admin is false."
 value = try(aws_inspector2_delegated_admin_account.this["this"].account_id, null)
}

output "delegated_admin_relationship_status" {
 description = "relationship_status of the delegated administrator registration (drift/health monitoring), or null when enable_delegated_admin is false."
 value = try(aws_inspector2_delegated_admin_account.this["this"].relationship_status, null)
}

# --- Organization configuration --------------------------------------------

output "organization_auto_enable" {
 description = "Object mirroring the applied auto_enable policy (ec2/ecr/code_repository/lambda/lambda_code), or null when enable_organization_configuration is false."
 value = try({
 ec2 = aws_inspector2_organization_configuration.this["this"].auto_enable[0].ec2
 ecr = aws_inspector2_organization_configuration.this["this"].auto_enable[0].ecr
 code_repository = aws_inspector2_organization_configuration.this["this"].auto_enable[0].code_repository
 lambda = aws_inspector2_organization_configuration.this["this"].auto_enable[0].lambda
 lambda_code = aws_inspector2_organization_configuration.this["this"].auto_enable[0].lambda_code
 }, null)
}

output "organization_max_account_limit_reached" {
 description = "Whether the org configuration reached the max account limit (alert when the org approaches the 10,000-account ceiling), or null when enable_organization_configuration is false."
 value = try(aws_inspector2_organization_configuration.this["this"].max_account_limit_reached, null)
}

# --- Member associations ----------------------------------------------------

output "member_association_ids" {
 description = "Map of member key => aws_inspector2_member_association id (state inspection)."
 value = { for k, v in aws_inspector2_member_association.this: k => v.id }
}

output "member_association_account_ids" {
 description = "Map of member key => associated member account ID."
 value = { for k, v in aws_inspector2_member_association.this: k => v.account_id }
}

output "member_association_statuses" {
 description = "Map of member key => relationship_status (membership health monitoring)."
 value = { for k, v in aws_inspector2_member_association.this: k => v.relationship_status }
}

# --- Suppression filters (the only resources with real ARNs / tags) ---------

output "filter_ids" {
 description = "Map of filter name => aws_inspector2_filter id."
 value = { for k, v in aws_inspector2_filter.this: k => v.id }
}

output "filter_arns" {
 description = "Map of filter name => filter ARN — the only genuine ARNs this module emits (cross-resource reference type, e.g. for tf-mod-aws-eventbridge). Format: arn:<partition>:inspector2:<region>:<account-id>:owner/<owner-id>/filter/<filter-id>."
 value = { for k, v in aws_inspector2_filter.this: k => v.arn }
}

output "filter_tags_all" {
 description = "Map of filter name => computed tags_all (merge of var.tags, per-filter tags, and provider default_tags). Filters are the ONLY taggable resource in this module — there is no module-wide tags_all."
 value = { for k, v in aws_inspector2_filter.this: k => v.tags_all }
}
