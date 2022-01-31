module "always" {
  source  = "cloudposse/label/null"
  version = "0.25.0"

  # account_map must always be enabled, even for components that are disabled
  enabled = true

  context = module.this.context
}

module "account_map" {
  source  = "cloudposse/stack-config/yaml//modules/remote-state"
  version = "0.19.0"

  component               = "account-map"
  privileged              = var.privileged
  environment             = var.global_environment_name
  stack_config_local_path = "../../../stacks"
  stage                   = var.root_account_stage_name
  tenant                  = var.global_tenant_name

  context = module.always.context
}

locals {
  principals = distinct(compact(flatten([for acct, v in var.role_map : (
    contains(v, "*") ? [module.account_map.outputs.full_account_map[acct]] :
    [
      for role in v : format(module.account_map.outputs.iam_role_arn_templates[acct], role)
    ]
  )])))
}
