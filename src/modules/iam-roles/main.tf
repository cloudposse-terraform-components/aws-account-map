
data "awsutils_caller_identity" "current" {
  count = local.dynamic_terraform_role_enabled ? 1 : 0
  # Avoid conflict with caller's provider which is using this module's output to assume a role.
  provider = awsutils.iam-roles
}

module "always" {
  source  = "cloudposse/label/null"
  version = "0.25.0"

  # account_map must always be enabled, even for components that are disabled
  enabled = true

  context = module.this.context
}

module "account_map" {
  source  = "cloudposse/stack-config/yaml//modules/remote-state"
  version = "1.8.0"

  component   = "account-map"
  privileged  = var.privileged
  tenant      = var.overridable_global_tenant_name
  environment = var.overridable_global_environment_name
  stage       = var.overridable_global_stage_name

  context = module.always.context
}

locals {
  profiles_enabled = coalesce(var.profiles_enabled, local.account_map.profiles_enabled)

  dynamic_terraform_role_enabled = try(local.account_map.terraform_dynamic_role_enabled, false)

  account_map       = module.account_map.outputs
  account_name      = lookup(module.always.descriptors, "account_name", module.always.stage)
  root_account_name = local.account_map.root_account_account_name

  current_user_role_arn = coalesce(one(data.awsutils_caller_identity.current[*].eks_role_arn), one(data.awsutils_caller_identity.current[*].arn), "disabled")

  current_user_account = one(data.awsutils_caller_identity.current[*].account_id)

  # If the user's current role is an SSO role, extract the permission set from the role ARN.
  # Use the combination of account ID and Permission Set Name to determine the Terraform role to assume.
  # Note that `awsutils_caller_identity` has already converted the ARN to the format `arn:<aws-partition>:iam::<account_id>:role/<role_name>`.
  permission_set = try(format("%s:%s", regex("^arn:[^:]+:iam::([0-9]{12}):role/AWSReservedSSO_([^_]+)_", local.current_user_role_arn)...), null)

  terraform_access_map = try(local.account_map.terraform_access_map[coalesce(local.permission_set, local.current_user_role_arn)], {})

  is_root_user   = local.current_user_account == local.account_map.full_account_map[local.root_account_name]
  is_target_user = local.current_user_account == local.account_map.full_account_map[local.account_name]

  account_org_role_arns = { for name, id in local.account_map.full_account_map : name =>
    name == local.root_account_name ? null : format(
      "arn:%s:iam::%s:role/OrganizationAccountAccessRole", local.account_map.aws_partition, id
    )
  }

  static_terraform_roles = local.account_map.terraform_roles

  dynamic_terraform_role_maps = local.dynamic_terraform_role_enabled ? {
    for account_name in local.account_map.all_accounts : account_name => {
      apply = format(local.account_map.iam_role_arn_templates[account_name], local.account_map.terraform_role_name_map["apply"])
      plan  = format(local.account_map.iam_role_arn_templates[account_name], local.account_map.terraform_role_name_map["plan"])
      # For user without explicit permissions:
      #   If the current user is a user in the `root` account, assume the `OrganizationAccountAccessRole` role in the target account.
      #   If the current user is a user in the target account, do not assume a role at all, let them do what their role allows.
      #   Otherwise, force them into the static Terraform role for the target account,
      #   to prevent users from accidentally running Terraform in the wrong account.
      none = local.is_root_user ? local.account_org_role_arns[account_name] : (
        # null means use current user's role
        local.is_target_user ? null : local.static_terraform_roles[account_name]
      )
    }
  } : {}

  dynamic_terraform_role_types = local.dynamic_terraform_role_enabled ? { for account_name in local.account_map.all_accounts :
    account_name => try(local.terraform_access_map[account_name], "none")
  } : {}

  dynamic_terraform_roles = local.dynamic_terraform_role_enabled ? { for account_name in local.account_map.all_accounts :
    account_name => local.dynamic_terraform_role_maps[account_name][local.dynamic_terraform_role_types[account_name]]
  } : {}

  final_terraform_role_arns = { for account_name in local.account_map.all_accounts : account_name =>
    local.dynamic_terraform_role_enabled ? local.dynamic_terraform_roles[account_name] : local.static_terraform_roles[account_name]
  }
}
