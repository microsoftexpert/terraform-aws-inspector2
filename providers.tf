terraform {
 required_version = ">= 1.12.0"

 required_providers {
 aws = {
 source = "hashicorp/aws"
 version = ">= 6.0, < 7.0"
 }
 }
}

# No provider "aws" {} block is declared inside this module.
#
# Amazon Inspector v2 is a REGIONAL, control-plane service: the enabler,
# delegated-administrator registration, organization configuration, member
# associations, and suppression filters are all created in the Region of the
# inherited provider. The caller configures region, credentials, default_tags,
# and assume_role at the root module / pipeline level and this module inherits
# that provider.
#
# Inspector is enabled once per account per Region. To cover multiple Regions,
# instantiate this module once per Region using provider aliases passed via
# `providers = { aws = aws.<region_alias> }`.
#
# CROSS-ACCOUNT NOTE: aws_inspector2_delegated_admin_account must be applied
# from the Organizations MANAGEMENT account, while
# aws_inspector2_organization_configuration must be applied from the Inspector
# DELEGATED ADMINISTRATOR account. This module intentionally does NOT hardcode
# that two-provider split (no configuration_aliases): each resource is
# individually toggleable so the caller invokes the module against the correct
# provider for the account it is operating on. See SCOPE.md § Design decisions.
