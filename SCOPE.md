# terraform-aws-inspector2 — SCOPE

Composite **security enablement** module for Amazon Inspector v2 vulnerability
scanning. It owns account/organization-level Inspector activation — which
resource types are scanned, which accounts are members, which account is the
Organizations delegated administrator, and what the org-wide auto-enable
policy is for new accounts — plus optional suppression filters. There is
**no long-lived data-plane resource** here (no bucket, no instance, no
cluster): every resource in this module is a control-plane *configuration
toggle* against the regional Inspector2 service, which is why the outputs
look different from a typical composite (see `## Emits`).

- **Module type:** Composite (security/compliance essentials — consumes no
  sibling module for its core function; optionally wires an existing
  Organizations structure)
- **Primary resource (keystone):** `aws_inspector2_enabler.this` — created
  under a guarded `for_each` keyed `"this"` and toggled by `enable_scanning`
  (default `true`), so the module can also be invoked purely for
  delegated-admin or org-configuration work from an account where scanning is
  not enabled in the same call. Addressed as `aws_inspector2_enabler.this["this"]`.

> **Correction vs. initial brief:** the starting brief assumed Organizations-wide
> delegated-admin registration might be folded into `aws_inspector2_organization_configuration`.
> It is not — it is a **separate, dedicated resource**, `aws_inspector2_delegated_admin_account`,
> confirmed live in `hashicorp/aws` v6.53.0. It has been added to in-scope resources below.
> The brief's seed IAM action list was also incomplete (missing the delegated-admin and
> Organizations-side actions) and has been corrected below.

## In-scope resources

The module manages the following (allow-list):

- `aws_inspector2_enabler` — keystone; enables scanning for a set of
  `account_ids` × `resource_types` (`EC2`, `ECR`, `LAMBDA`, `LAMBDA_CODE`,
  `CODE_REPOSITORY`; both are `set(string)`). Must be created in the account
  that is either the Organization's Administrator (management) account or the
  Inspector delegated administrator account. Guarded by `var.enable_scanning`
  (default `true`); when `false` the enabler is not created and the module runs
  only its other (delegated-admin / org-config / member / filter) resources.
  `LAMBDA_CODE` requires `LAMBDA` — enforced by a plan-time `validation {}`.
- `aws_inspector2_delegated_admin_account` — registers a member account as
  the Organization's Inspector delegated administrator. **This is the
  Organizations-wide registration mechanism** requested in the brief — it is
  its own resource, not an argument on `aws_inspector2_organization_configuration`.
  Created from the Organizations **management** account.
- `aws_inspector2_organization_configuration` — sets the auto-enable policy
  (`auto_enable { ec2, ecr, code_repository, lambda, lambda_code }`) applied
  to **new** member accounts as they join the organization. Must be created
  from the Inspector **delegated administrator** account (not the management
  account) — the provider enforces this at apply time.
- `aws_inspector2_member_association` — associates an existing member account
  to the calling account's Inspector instance (used for the non-Organizations,
  manual invitation-style membership path). Rendered as a `for_each` child
  collection keyed by a caller-supplied stable string (typically the member
  account id or a friendly alias).
- `aws_inspector2_filter` — optional suppression/noise-reduction filter
  (`action = "SUPPRESS"` or `"NONE"`) scoped by `filter_criteria`. Included
  in-scope because it is the **only** Inspector2 resource that exposes
  `tags`, `tags_all`, and a real `arn` — see `## Provider gotchas`. Rendered
  as a `for_each` child collection keyed by filter name.

## Out-of-scope resources (consumed by reference)

Referenced by `id`/`arn`, never created here:

- **AWS Organization itself** — `aws_organizations_organization` /
  `aws_organizations_account` live in `terraform-aws-organizations` (Phase 7).
  This module assumes an Organization already exists when the delegated-admin
  or org-configuration resources are used; it does not create or manage OUs,
  member accounts, or the `EnableAWSServiceAccess` trusted-access toggle for
  `inspector2.amazonaws.com` (that toggle is a one-time Organizations-level
  action typically performed alongside — but outside — this module; see
  `## AWS Prerequisites`).
- **Security Hub / GuardDuty integration** — Inspector findings surfaced in
  Security Hub are configured in `terraform-aws-security-hub`, not here.
- **Finding remediation** (SSM Patch Manager, EventBridge rules reacting to
  findings) — owned by `terraform-aws-ssm` / `terraform-aws-eventbridge` (Phase 4).
- **CMK for finding export encryption** — Inspector2 findings themselves are
  not stored in a caller-managed encrypted resource by this module; if
  findings are exported (e.g. via EventBridge → S3/Kinesis), the destination's
  own module owns its encryption story.

## Consumes

None required for the core single-account enablement path — **self-contained**,
matching the brief. The Organizations-wide path optionally consumes an
existing account id (not a full module output) for delegated-admin
designation:

| Input | Type | Source |
|---|---|---|
| `delegated_admin_account_id` | `string` (account id) | Typically a member account id already known to the caller, or `data.aws_organizations_organization`/`data.aws_caller_identity` in the root module — **not** a `terraform-aws-organizations` module output today, since that module is Phase 7 and not yet built |
| `member_account_ids` (map keys) | `string` (account ids) | Caller-supplied list of existing member/child account ids |

## Required IAM permissions

Least-privilege actions the Terraform identity needs. Split by resource
because the delegated-admin and org-configuration paths run from **different
accounts** (management vs. delegated administrator) and pull in
`organizations:*` actions alongside `inspector2:*`.

| Action | Required for |
|---|---|
| `inspector2:Enable`, `inspector2:Disable`, `inspector2:BatchGetAccountStatus`, `inspector2:DescribeOrganizationConfiguration` | `aws_inspector2_enabler` lifecycle/read |
| `inspector2:EnableDelegatedAdminAccount`, `inspector2:DisableDelegatedAdminAccount`, `inspector2:GetDelegatedAdminAccount`, `inspector2:ListDelegatedAdminAccounts` | `aws_inspector2_delegated_admin_account` lifecycle/read |
| `organizations:EnableAWSServiceAccess`, `organizations:RegisterDelegatedAdministrator`, `organizations:DeregisterDelegatedAdministrator`, `organizations:ListDelegatedAdministrators`, `organizations:ListAWSServiceAccessForOrganization`, `organizations:DescribeOrganizationalUnit`, `organizations:DescribeAccount`, `organizations:DescribeOrganization` | Delegated-admin registration is an Organizations-service action, not purely an Inspector action — run from the **management account** |
| `inspector2:UpdateOrganizationConfiguration`, `inspector2:DescribeOrganizationConfiguration` | `aws_inspector2_organization_configuration` — run from the **delegated administrator account** |
| `inspector2:AssociateMember`, `inspector2:DisassociateMember`, `inspector2:GetMember`, `inspector2:ListMembers` | `aws_inspector2_member_association` |
| `inspector2:CreateFilter`, `inspector2:DeleteFilter`, `inspector2:UpdateFilter`, `inspector2:ListFilters`, `inspector2:TagResource`, `inspector2:UntagResource`, `inspector2:ListTagsForResource` | `aws_inspector2_filter` (the one resource here with real tagging) |

> **Correction vs. initial brief:** `inspector2:TagResource` alone is
> insufficient and, more importantly, is only meaningful for
> `aws_inspector2_filter` — the enabler, delegated-admin, org-configuration,
> and member-association resources accept **no tags argument** in the
> provider schema (verified against `hashicorp/aws` v6.53.0), so
> `TagResource`/`UntagResource` only apply to filters.

## AWS Prerequisites

- **Amazon Inspector is Regional.** `aws_inspector2_enabler` and every other
  resource in this module act on the Region set by the provider (or the
  optional per-resource `region` argument added in AWS provider v6 for
  multi-region flexibility — see `## Provider gotchas`). There is no
  `terraform-aws-*` global Inspector2 module; a caller enabling multiple Regions
  invokes this module once per Region (directly or via a provider alias).
- **Delegated administrator is a singleton per Organization, but per-Region
  in enforcement.** An Organization can have only one Inspector delegated
  administrator account, and it must be designated **in every Region** where
  Inspector will be used org-wide. `aws_inspector2_delegated_admin_account`
  must be re-applied per Region (via provider alias) for full multi-Region
  org coverage.
- **`organizations:EnableAWSServiceAccess` for `inspector2.amazonaws.com`**
  must be granted before `aws_inspector2_delegated_admin_account` succeeds.
  This module's `aws_inspector2_delegated_admin_account` resource triggers
  this as part of its create (see the AWS-documented permission set), but the
  caller's Organizations management account must already have **all features
  enabled** (not just consolidated billing) — a one-time, one-way
  Organizations setting outside this module's control.
- **`aws_inspector2_organization_configuration` must run from the delegated
  administrator account**, not the management account — order-of-operations
  matters: `aws_inspector2_delegated_admin_account` (management account) must
  exist before `aws_inspector2_organization_configuration` (delegated admin
  account) can be applied. If both are used from a single module call, the
  caller must pass two provider configurations (`providers = { aws =
  aws.management, aws.delegated_admin = aws.delegated_admin }`) — this module
  intentionally does not hardcode that split; see `## Design decisions`.
- **No service-linked role** is created by Inspector2 itself; ECR/EC2/Lambda
  scanning relies on existing service permissions already present for those
  services (e.g. ECR repository read for image layer scanning).
- **Quota:** delegated administrator supports up to 10,000 member accounts;
  beyond that (up to 50,000 with an org-wide policy) some accounts are
  scanned but not visible in the Inspector console/API for the delegated
  admin. Lambda code scanning (`lambda_code = true`) requires standard Lambda
  scanning (`lambda = true`) to also be enabled — enforced by a `validation {}`
  block in this module, matching a provider-documented cross-field constraint.

## Emits

Because every in-scope resource except `aws_inspector2_filter` exposes **no
ARN and no meaningful standalone id** (`aws_inspector2_enabler`'s Terraform
`id` is a synthetic `account_ids-resource_types` composite string, not an AWS
identifier that other services can reference), this module's outputs are
shaped around **state**, not cross-resource wiring:

| Output | Description | Consumed by |
|---|---|---|
| `id` | Synthetic composite id of `aws_inspector2_enabler.this["this"]` (`[account_ids]-[resource_types]`, provider-generated) — informational only, not an AWS ARN/id other modules reference. `try(..., null)` — `null` when `enable_scanning = false` | Audit/state inspection only |
| `enabled_account_ids` | The `account_ids` set passed to the enabler (`null` when `enable_scanning = false`) | Compliance reporting |
| `enabled_resource_types` | The `resource_types` set passed to the enabler (`EC2`/`ECR`/`LAMBDA`/`LAMBDA_CODE`/`CODE_REPOSITORY`; `null` when `enable_scanning = false`) | Compliance reporting, Security Hub cross-check |
| `delegated_admin_account_id` | Account id registered as Inspector delegated admin (`try(..., null)` if not used) | Audit; other security modules (`terraform-aws-guardduty`, `terraform-aws-security-hub`) that also need to know the org's delegated security admin |
| `delegated_admin_relationship_status` | `relationship_status` from `aws_inspector2_delegated_admin_account` (`try(..., null)`) | Drift/health monitoring |
| `organization_auto_enable` | Object mirroring the applied `auto_enable` block (`try(..., null)`) | Compliance reporting |
| `organization_max_account_limit_reached` | `max_account_limit_reached` computed attribute (`try(..., null)`) | Alerting when org approaches the 10,000-account ceiling |
| `member_association_ids` | Map of member key → `aws_inspector2_member_association.this[key].id` | Audit/state inspection |
| `member_association_account_ids` | Map of member key → associated member `account_id` | Audit/state inspection |
| `member_association_statuses` | Map of member key → `relationship_status` | Membership health monitoring |
| `filter_ids` / `filter_arns` | Map of filter name → `id`/`arn` for `aws_inspector2_filter.this[key]` — the **only** genuine ARNs this module emits | `terraform-aws-eventbridge` or other modules referencing suppression filters by ARN |
| `filter_tags_all` | Map of filter name → computed `tags_all` | Governance/audit (filters only — no other resource here supports tags) |

## Provider gotchas

- **No `arn`, no `tags` on the enabler, delegated-admin, org-configuration, or
  member-association resources.** This breaks the usual "every module emits
  `id` + `arn`" and "tags flow to every taggable resource" non-negotiables
  from this module suite's conventions **because the underlying resources do not support them** —
  documented here as a deliberate, verified exception rather than an
  oversight. `aws_inspector2_filter` is the sole exception and gets full
  `tags`/`tags_all`/`arn` treatment.
- **`aws_inspector2_enabler` id is synthetic and order-dependent.** Its
  import id format is `[account_id1]:[account_id2]:...-[resource_type1]:[resource_type2]:...`
  with account ids sorted ascending and resource types sorted alphabetically.
  Changing the *set* of `account_ids` or `resource_types` changes this
  synthetic id but updates in place (does not force-new the underlying
  scanning state) — Terraform still needs to reconcile membership even though
  the resource is not literally recreated.
- **`aws_inspector2_enabler` must run from the org admin or delegated admin
  account** to enable scanning for other member accounts; running it from a
  standalone account only works for `account_ids = [self]`.
- **`aws_inspector2_organization_configuration` requires the caller to already
  be the delegated administrator.** Applying it from the management account
  (before delegation) fails at the API level, not at plan time — this is an
  eventual-consistency / ordering trap, not a schema-validated constraint.
  Sequence `aws_inspector2_delegated_admin_account` before this resource with
  an explicit `depends_on` even though there is no direct attribute
  reference between them.
- **`lambda_code = true` requires `lambda = true`** in the same `auto_enable`
  block — an AWS-documented cross-field constraint the provider does not
  validate at plan time; enforced here via a `validation {}` block.
- **Destroy behavior removes future auto-enablement, not existing findings.**
  Destroying `aws_inspector2_organization_configuration` stops new member
  accounts from being auto-enabled; it does **not** retroactively disable
  Inspector for accounts already scanning, and does not delete historical
  findings. Destroying `aws_inspector2_enabler` disables scanning for the
  listed accounts/resource types going forward; findings already generated
  persist in the Inspector console/API per its own retention, independent of
  this module's state.
- **Removing the delegated administrator does not deactivate member
  accounts.** Per AWS documentation, member accounts become standalone
  accounts with their existing scan settings intact — destroying
  `aws_inspector2_delegated_admin_account` is not equivalent to disabling
  Inspector everywhere.
- **No `us-east-1` global-resource requirement** — Inspector2 is a purely
  Regional service throughout; there is no CloudFront/WAFv2/ACM-style global
  coupling here.
- **`region` argument (v6+):** every resource in this module accepts the
  optional per-resource `region` argument added across the provider in v6 for
  enhanced multi-region support. Per this module suite's Region convention, this module
  does **not** expose a `region` variable of its own — multi-Region use is
  achieved via provider aliasing at the caller/root level, consistent with
  every other non-DR module in this library.

## Secure-by-default decisions

| Posture | Default | Opt-out |
|---|---|---|
| Scanning creation | `enable_scanning = true` — the keystone enabler is created by default; the module's core purpose is to enable scanning | `enable_scanning = false` to scope an invocation to delegated-admin / org-config / member / filter work only |
| Resource-type scope | **Explicit, caller-required list** — `resource_types` defaults to `[]` and has no wildcard-all convenience value; the caller must enumerate exactly which of `EC2`/`ECR`/`LAMBDA`/`LAMBDA_CODE`/`CODE_REPOSITORY` to scan, and it is validated non-empty when `enable_scanning = true` | There is no opt-out from specifying the list when scanning — this is the secure-by-default posture itself (least-privilege scanning scope, matching the brief's requirement) |
| Organization auto-enable scope | `ec2` and `ecr` required arguments with **no default** (caller must decide); `code_repository`, `lambda`, `lambda_code` default to `false` in this module's schema | Caller sets any `auto_enable.*` flag to `true` explicitly per their scanning strategy |
| Lambda code scanning without Lambda scanning | **Blocked by `validation {}`** — `lambda_code = true` with `lambda = false` fails plan-time validation rather than a confusing apply-time API error | Set `lambda = true` alongside `lambda_code = true` |
| Suppression filters | **None by default** (`filters = {}`) — no findings are suppressed out of the box; every suppression is an explicit, named, auditable `aws_inspector2_filter` entry | Add entries to `var.filters` |
| Member association scope | **None by default** (`member_account_ids = {}`) — no accounts are silently associated | Populate `var.member_account_ids` |

## Design decisions

- **This module intentionally does not hardcode a management-account /
  delegated-admin-account provider split.** Because
  `aws_inspector2_delegated_admin_account` must run from the Organizations
  management account and `aws_inspector2_organization_configuration` must run
  from the delegated administrator account, forcing both into one module
  invocation with one implicit provider would misrepresent how AWS actually
  enforces this boundary. Instead, both resources are declared but each is
  **individually toggleable** (`enable_delegated_admin` /
  `enable_organization_configuration` booleans), so a caller can invoke this
  module twice — once per account — each pointed at the correct provider,
  or invoke it once from a single delegated-admin account that also happens
  to be the management account in a single-account-Organization test setup.
- **`aws_inspector2_filter` is included in-scope**, breaking the
  "self-contained enablement only" framing from the brief, specifically
  because it is the only resource in the Inspector2 family with `tags` and
  `arn` — including it gives the module a genuine cross-resource-reference
  surface and a real tagging story, consistent with this module suite's universal
  tags/ARN non-negotiables, rather than leaving the module with zero taggable
  resources.
- **`aws_organizations_organization` and member-account creation are
  deliberately excluded.** They belong to `terraform-aws-organizations`
  (Phase 7, not yet built). This module accepts raw account id strings for
  `delegated_admin_account_id` and `member_account_ids` rather than blocking
  on a Phase 7 dependency that doesn't exist yet.
- **The keystone enabler is itself toggleable (`enable_scanning`, default
  `true`).** This extends the "individually toggleable switches" philosophy to
  the keystone: the management-account invocation (delegated-admin
  registration) and the delegated-admin-account invocation (org configuration)
  can each set `enable_scanning = false` so they do not force a scanning
  decision in an account where scanning is administered elsewhere. Because of
  this, the enabler is rendered with a guarded `for_each` keyed `"this"` and
  every enabler-derived output uses `try(..., null)`.
- **`aws_inspector2_filter.filter_criteria` is typed in full — all 46 finding
  fields** (34 string, 3 number, 6 date, 1 map, 1 port-range, 1 package filter,
  the last with its own 8 nested sub-filters), each `optional()` with the exact
  provider sub-block shape. For a compliance/security tool the module does not
  curate the field list down (unlike the larger Security Hub insight schema):
  arbitrarily withholding a suppression dimension from a security engineer is a
  worse tradeoff than a longer, fully-typed schema. Verified against
  `hashicorp/aws` v6.53.0.
- **No `region` variable** — consistent with every non-DR module in this
  library; multi-Region Inspector rollout is a caller-level provider-alias
  concern, documented explicitly here because Inspector's delegated-admin
  per-Region requirement makes this more likely to come up than in most
  modules.
