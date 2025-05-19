##
## What we want at the end of all this is a map of maps so we can say:
##
##   allowed_role = authorized_users[current_user][target_account]
##
## To compute this, we have to invert the mapping we are given, and resolve collisions.
##
## What we are given is, for every account, a list of principals that are
## allowed to assume the planner role in that account, and another list of
## principals that are allowed to assume the terraform role in that account.
## What we want is principal -> account -> role, where role is apply
## if they are allowed into the terraform role, and plan otherwise.
## We do not need to include principals that are not allowed into either role.
##
## To make things both easier and more robust, instead of using the IAM Role ARN
## for people using AWS SSO Permission Sets, we will use the combination of the
## account ID and the Permission Set Name to identify the principal.

locals {
  dynamic_role_enabled = module.this.enabled && var.terraform_dynamic_role_enabled

  identity_account_id = local.account_info_map[local.account_role_map.identity].id

  # `var.terraform_role_name_map` maps some team role in the `aws-team-roles` configuration to "plan" and some other team to "apply".
  apply_role = var.terraform_role_name_map.apply
  plan_role  = var.terraform_role_name_map.plan

  # For every team-roles configuration, normalize authorized principals to a list like this:
  # { "account-name" = { "plan" = [ "principal-arn", ... ], "apply" = [ "principal-arn", ... ] } }
  # This is made complicated because principals can be specified as:
  # - a principal ARN via trusted_role_arns
  # - a team name via trusted_teams
  # - a permission set in the `identity` account via trusted_identity_permission_sets
  # - a permission set in the target account via trusted_permission_sets
  account_auths = {
    for stack, vars in local.team_roles_vars : local.stack_account_map[stack] => {
      for i, role in [local.apply_role, local.plan_role] : i == 0 ? "apply" : "plan" => concat(
        [for principal in vars.roles[role].trusted_role_arns : principal],
        [for principal in vars.roles[role].trusted_teams : local.team_arns[principal]],
        [
          for principal in vars.roles[role].trusted_identity_permission_sets :
          format("%s:%s", local.identity_account_id, principal)
        ],
        [
          for principal in vars.roles[role].trusted_permission_sets :
          format("%s:%s", local.account_info_map[local.stack_account_map[stack]].id, principal)
        ],
      )
    }
  }

  # Get the complete, sorted, deduplicated list of all principals that are allowed to assume the planner role in any account.
  all_principals = sort(distinct(flatten([for account, roles in local.account_auths : values(roles)])))

  # Build up the principal -> account -> role map by first filling in the map for all principals allowed to assume the apply role.
  # Then, for each principal allowed to assume the plan role, add the account to the map if it is not already there.
  apply_principal_auths = {
    for principal in local.all_principals : principal => {
      for account, roles in local.account_auths : account => "apply" if contains(roles.apply, principal)
    }
  }

  # Now create the map with "plan" roles, and overwrite with "apply" roles where they exist.
  principal_terraform_access_map = {
    for principal in local.all_principals : principal => merge({
      for account, roles in local.account_auths : account => "plan" if contains(roles.plan, principal)
    }, lookup(local.apply_principal_auths, principal, {}))
  }
}

