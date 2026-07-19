###############################################################################
# tf_mod_aws_inspector2 — variables
#
# Composite security-enablement module for Amazon Inspector v2. The keystone is
# the regional scan enabler (aws_inspector2_enabler.this); the other resources
# are independently toggleable control-plane configuration:
# - aws_inspector2_delegated_admin_account (enable_delegated_admin)
# - aws_inspector2_organization_configuration (enable_organization_configuration)
# - aws_inspector2_member_association (member_account_ids, for_each)
# - aws_inspector2_filter (filters, for_each)
#
# Secure-by-default is LEAST-PRIVILEGE SCOPE, not encryption: resource_types has
# NO wildcard-all convenience value (the caller must enumerate exactly which
# scan types to run); organization auto-enable defaults everything but ec2/ecr
# to false; lambda_code scanning without lambda scanning is blocked at plan
# time; and no members are associated and no findings suppressed out of the box.
#
# TAGGING NOTE: of the five Inspector2 resources, ONLY aws_inspector2_filter
# supports `tags`/`tags_all`/`arn` in the hashicorp/aws provider (verified
# against v6.53.0). var.tags is therefore wired to filters ONLY; the enabler,
# delegated-admin, org-configuration, and member-association resources accept no
# tags argument. See the tags variable and the SCOPE.md § Provider gotchas.
###############################################################################

# --- Scan enabler (keystone) -----------------------------------------------

variable "enable_scanning" {
 description = <<EOT
Whether to create the aws_inspector2_enabler (the keystone) — i.e. whether this
module invocation turns on Inspector scanning for var.account_ids in this
Region.

Defaults to true (the module's core purpose is to enable scanning). Set false
when invoking the module purely to register a delegated administrator or apply
an organization configuration from an account where you do NOT want to enable
scanning in the same call (see SCOPE.md § Design decisions — the module is a set
of individually-toggleable control-plane switches).
EOT
 type = bool
 default = true
}

variable "account_ids" {
 description = <<EOT
Set of AWS account IDs for which Inspector scanning is enabled by the keystone
aws_inspector2_enabler. May contain the calling account, the Organization's
management account, and/or one or more member accounts.

Enabling scanning for OTHER accounts requires the calling account to be the
Organization's administrator or the Inspector delegated administrator; a
standalone account can only enable itself (account_ids = [self]).

Required (non-empty) when enable_scanning = true; ignored when enable_scanning
= false. Defaults to [] so the module can be invoked for delegated-admin /
org-configuration only.
EOT
 type = set(string)
 default = []

 validation {
 condition = alltrue([for a in var.account_ids: can(regex("^[0-9]{12}$", a))])
 error_message = "Each account_ids entry must be a 12-digit AWS account ID."
 }

 validation {
 condition = !var.enable_scanning || length(var.account_ids) > 0
 error_message = "account_ids must contain at least one account ID when enable_scanning is true."
 }
}

variable "resource_types" {
 description = <<EOT
Set of resource types the enabler scans. There is deliberately NO wildcard-all
convenience value — the caller must enumerate exactly which types to scan, which
IS the secure-by-default (least-privilege scanning scope) posture for this
module. At least one item is required when enable_scanning = true.

Valid values:
 EC2 - Amazon EC2 instance (host) vulnerability scanning
 ECR - Amazon ECR container image scanning
 LAMBDA - AWS Lambda standard (dependency) scanning
 LAMBDA_CODE - AWS Lambda code scanning (REQUIRES LAMBDA to also be set)
 CODE_REPOSITORY - code repository scanning (e.g. connected GitHub/GitLab repos)

Defaults to [] so the module can be invoked for delegated-admin /
org-configuration only. The LAMBDA_CODE-requires-LAMBDA constraint is enforced
here at plan time (AWS otherwise rejects it only at apply).
EOT
 type = set(string)
 default = []

 validation {
 condition = alltrue([for t in var.resource_types: contains(["EC2", "ECR", "LAMBDA", "LAMBDA_CODE", "CODE_REPOSITORY"], t)])
 error_message = "Each resource_types entry must be one of: EC2, ECR, LAMBDA, LAMBDA_CODE, CODE_REPOSITORY."
 }

 validation {
 condition = !contains(var.resource_types, "LAMBDA_CODE") || contains(var.resource_types, "LAMBDA")
 error_message = "resource_types LAMBDA_CODE requires LAMBDA to also be enabled (Lambda code scanning depends on Lambda standard scanning)."
 }

 validation {
 condition = !var.enable_scanning || length(var.resource_types) > 0
 error_message = "resource_types must contain at least one scan type when enable_scanning is true."
 }
}

# --- Delegated administrator (Organizations management account) ------------

variable "enable_delegated_admin" {
 description = <<EOT
Whether to register delegated_admin_account_id as the Organization's Inspector
delegated administrator (aws_inspector2_delegated_admin_account).

Defaults to false. Apply this from the Organizations MANAGEMENT account only;
delegated-administrator registration is an Organizations-service action. An
Organization has exactly one Inspector delegated administrator, but it must be
designated in EVERY Region where Inspector is used org-wide (re-apply per Region
via provider aliases).
EOT
 type = bool
 default = false
}

variable "delegated_admin_account_id" {
 description = <<EOT
The 12-digit AWS account ID to register as the Inspector delegated
administrator. Typically an existing member/security account ID (supplied
directly or from data.aws_caller_identity / data.aws_organizations_organization
in the root module — not a tf-mod-aws-organizations output,).

Required when enable_delegated_admin = true; otherwise ignored. Defaults to null.
EOT
 type = string
 default = null

 validation {
 condition = var.delegated_admin_account_id == null ? true: can(regex("^[0-9]{12}$", var.delegated_admin_account_id))
 error_message = "delegated_admin_account_id must be a 12-digit AWS account ID."
 }

 validation {
 condition = !var.enable_delegated_admin || var.delegated_admin_account_id != null
 error_message = "delegated_admin_account_id is required when enable_delegated_admin is true."
 }
}

# --- Organization auto-enable configuration (delegated admin account) ------

variable "enable_organization_configuration" {
 description = <<EOT
Whether to apply the organization-wide auto-enable policy
(aws_inspector2_organization_configuration) that governs which scans are
automatically turned on for NEW member accounts as they join the Organization.

Defaults to false. Apply this from the Inspector DELEGATED ADMINISTRATOR account
only (not the management account) — the provider enforces this at apply time,
and the delegated administrator must already be registered
(aws_inspector2_delegated_admin_account) first.
EOT
 type = bool
 default = false
}

variable "organization_auto_enable" {
 description = <<EOT
The auto-enable policy for new organization member accounts, rendered as the
single required `auto_enable` block of aws_inspector2_organization_configuration.

 {
 ec2 = bool # (Required) auto-enable EC2 scans
 ecr = bool # (Required) auto-enable ECR scans
 code_repository = optional(bool, false) # auto-enable code repository scans
 lambda = optional(bool, false) # auto-enable Lambda standard scans
 lambda_code = optional(bool, false) # auto-enable Lambda code scans (REQUIRES lambda = true)
 }

Secure by default: ec2 and ecr have NO default (the caller must decide); the
rest default to false so nothing is silently auto-enabled. Required (non-null)
when enable_organization_configuration = true. The lambda_code-requires-lambda
constraint is enforced here at plan time. Defaults to null.
EOT
 type = object({
 ec2 = bool
 ecr = bool
 code_repository = optional(bool, false)
 lambda = optional(bool, false)
 lambda_code = optional(bool, false)
 })
 default = null

 validation {
 condition = var.organization_auto_enable == null ? true: (!var.organization_auto_enable.lambda_code || var.organization_auto_enable.lambda)
 error_message = "organization_auto_enable.lambda_code requires organization_auto_enable.lambda to also be true (Lambda code scanning depends on Lambda standard scanning)."
 }

 validation {
 condition = !var.enable_organization_configuration || var.organization_auto_enable != null
 error_message = "organization_auto_enable is required when enable_organization_configuration is true."
 }
}

# --- Member associations (manual, non-Organizations membership path) -------

variable "member_account_ids" {
 description = <<EOT
Map of member accounts to associate with THIS account's Inspector instance
(aws_inspector2_member_association), keyed by a stable caller string — typically
the member account ID itself or a friendly alias. Used for the manual,
invitation-style membership path (as opposed to Organizations auto-enable).

 member_account_ids = {
 "123456789012" = {} # key IS the account_id
 "audit-account" = { account_id = "444455556666" } # friendly alias key
 }

If `account_id` is omitted, the map KEY is used as the account ID (so it must be
a 12-digit account ID in that case). Defaults to {} (no accounts associated —
nothing is silently associated). Member associations are NOT taggable.
EOT
 type = map(object({
 account_id = optional(string)
 }))
 default = {}

 validation {
 condition = alltrue([for k, v in var.member_account_ids: can(regex("^[0-9]{12}$", coalesce(v.account_id, k)))])
 error_message = "Each member_account_ids entry must resolve to a 12-digit AWS account ID (from account_id, or from the map key when account_id is omitted)."
 }
}

# --- Suppression / noise-reduction filters ---------------------------------

variable "filters" {
 description = <<EOT
Map of Inspector finding filters keyed by a stable filter name (the map key is
used as the filter `name`). Each entry is one aws_inspector2_filter — the ONLY
Inspector2 resource that supports tags and an ARN.

 filters = {
 "suppress-sandbox-informational" = {
 action = "SUPPRESS" # SUPPRESS (hide matching findings) | NONE (no suppression)
 description = optional(string)
 reason = optional(string)
 filter_criteria = {
 # Every field below is an OPTIONAL list of criteria; provide at least one.
 severity = [{ comparison = "EQUALS", value = "INFORMATIONAL" }]
 resource_type = [{ comparison = "EQUALS", value = "AWS_EC2_INSTANCE" }]
 ec2_instance_vpc_id = [{ comparison = "EQUALS", value = "vpc-0abc123" }]
 }
 tags = optional(map(string), {})
 }
 }

filter_criteria fields group into shapes:
 String filter list(object({ comparison, value }))
 comparison: EQUALS | PREFIX | NOT_EQUALS
 Number filter list(object({ lower_inclusive, upper_inclusive })) (both required)
 Date filter list(object({ start_inclusive, end_inclusive })) (RFC3339; provide either/both)
 Map filter list(object({ comparison, key, value })) comparison: EQUALS | NOT_EQUALS
 Port range list(object({ begin_inclusive, end_inclusive })) (both required)
 Package list(object({...eight nested sub-filters... })) (vulnerable_packages)

Secure by default: filters = {} — NO findings are suppressed out of the box.
Every suppression is an explicit, named, auditable filter. Use action =
"SUPPRESS" only for reviewed, accepted-risk noise — never to mask genuine risk.
tags merge module-level var.tags with per-filter tags (per-filter wins).
EOT
 type = map(object({
 action = string
 description = optional(string)
 reason = optional(string)
 tags = optional(map(string), {})
 filter_criteria = object({
 # --- String filters (comparison, value) ---
 aws_account_id = optional(list(object({ comparison = string, value = string })))
 code_repository_project_name = optional(list(object({ comparison = string, value = string })))
 code_repository_provider_type = optional(list(object({ comparison = string, value = string })))
 code_vulnerability_detector_name = optional(list(object({ comparison = string, value = string })))
 code_vulnerability_detector_tags = optional(list(object({ comparison = string, value = string })))
 code_vulnerability_file_path = optional(list(object({ comparison = string, value = string })))
 component_id = optional(list(object({ comparison = string, value = string })))
 component_type = optional(list(object({ comparison = string, value = string })))
 ec2_instance_image_id = optional(list(object({ comparison = string, value = string })))
 ec2_instance_subnet_id = optional(list(object({ comparison = string, value = string })))
 ec2_instance_vpc_id = optional(list(object({ comparison = string, value = string })))
 ecr_image_architecture = optional(list(object({ comparison = string, value = string })))
 ecr_image_hash = optional(list(object({ comparison = string, value = string })))
 ecr_image_registry = optional(list(object({ comparison = string, value = string })))
 ecr_image_repository_name = optional(list(object({ comparison = string, value = string })))
 ecr_image_tags = optional(list(object({ comparison = string, value = string })))
 exploit_available = optional(list(object({ comparison = string, value = string })))
 finding_arn = optional(list(object({ comparison = string, value = string })))
 finding_status = optional(list(object({ comparison = string, value = string })))
 finding_type = optional(list(object({ comparison = string, value = string })))
 fix_available = optional(list(object({ comparison = string, value = string })))
 lambda_function_execution_role_arn = optional(list(object({ comparison = string, value = string })))
 lambda_function_layers = optional(list(object({ comparison = string, value = string })))
 lambda_function_name = optional(list(object({ comparison = string, value = string })))
 lambda_function_runtime = optional(list(object({ comparison = string, value = string })))
 network_protocol = optional(list(object({ comparison = string, value = string })))
 related_vulnerabilities = optional(list(object({ comparison = string, value = string })))
 resource_id = optional(list(object({ comparison = string, value = string })))
 resource_type = optional(list(object({ comparison = string, value = string })))
 severity = optional(list(object({ comparison = string, value = string })))
 title = optional(list(object({ comparison = string, value = string })))
 vendor_severity = optional(list(object({ comparison = string, value = string })))
 vulnerability_id = optional(list(object({ comparison = string, value = string })))
 vulnerability_source = optional(list(object({ comparison = string, value = string })))

 # --- Number filters (lower_inclusive, upper_inclusive) ---
 ecr_image_in_use_count = optional(list(object({ lower_inclusive = number, upper_inclusive = number })))
 epss_score = optional(list(object({ lower_inclusive = number, upper_inclusive = number })))
 inspector_score = optional(list(object({ lower_inclusive = number, upper_inclusive = number })))

 # --- Date filters (start_inclusive, end_inclusive; RFC3339) ---
 ecr_image_last_in_use_at = optional(list(object({ start_inclusive = optional(string), end_inclusive = optional(string) })))
 ecr_image_pushed_at = optional(list(object({ start_inclusive = optional(string), end_inclusive = optional(string) })))
 first_observed_at = optional(list(object({ start_inclusive = optional(string), end_inclusive = optional(string) })))
 lambda_function_last_modified_at = optional(list(object({ start_inclusive = optional(string), end_inclusive = optional(string) })))
 last_observed_at = optional(list(object({ start_inclusive = optional(string), end_inclusive = optional(string) })))
 updated_at = optional(list(object({ start_inclusive = optional(string), end_inclusive = optional(string) })))

 # --- Map filter (comparison, key, value) ---
 resource_tags = optional(list(object({ comparison = string, key = string, value = string })))

 # --- Port range filter (begin_inclusive, end_inclusive) ---
 port_range = optional(list(object({ begin_inclusive = number, end_inclusive = number })))

 # --- Package filter (vulnerable_packages) ---
 vulnerable_packages = optional(list(object({
 architecture = optional(list(object({ comparison = string, value = string })))
 epoch = optional(list(object({ lower_inclusive = number, upper_inclusive = number })))
 file_path = optional(list(object({ comparison = string, value = string })))
 name = optional(list(object({ comparison = string, value = string })))
 release = optional(list(object({ comparison = string, value = string })))
 source_lambda_layer_arn = optional(list(object({ comparison = string, value = string })))
 source_layer_hash = optional(list(object({ comparison = string, value = string })))
 version = optional(list(object({ comparison = string, value = string })))
 })))
 })
 }))
 default = {}

 validation {
 condition = alltrue([for f in values(var.filters): contains(["SUPPRESS", "NONE"], f.action)])
 error_message = "Each filters action must be one of: SUPPRESS, NONE."
 }
}

# --- Universal tail: tags, then timeouts -----------------------------------

variable "tags" {
 description = <<EOT
A map of tags applied to the TAGGABLE resources created by this module.

IMPORTANT: of the five Inspector2 resources, only aws_inspector2_filter accepts
a `tags` argument in the hashicorp/aws provider. var.tags is therefore applied
to FILTERS ONLY (merged with any per-filter tags, per-filter winning). The
enabler, delegated-admin, organization-configuration, and member-association
resources are not taggable and receive no tags. These filter tags merge with
provider-level default_tags; resource tags win on key conflict, and the computed
filter_tags_all output reflects the merged set per filter.
EOT
 type = map(string)
 default = {}
}

variable "timeouts" {
 description = <<EOT
Optional Terraform operation timeouts, applied to the resources in this module
that expose them:
 create/update/delete - aws_inspector2_enabler, aws_inspector2_organization_configuration
 create/delete only - aws_inspector2_delegated_admin_account, aws_inspector2_member_association

The `update` value is ignored by the two create/delete-only resources.
aws_inspector2_filter exposes no configurable timeouts. Defaults to {} (use the
provider defaults).
EOT
 type = object({
 create = optional(string)
 update = optional(string)
 delete = optional(string)
 })
 default = {}
}
