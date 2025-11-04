module "accounts" {
  source  = "cloudposse/stack-config/yaml//modules/remote-state"
  version = "1.8.0"

  component  = var.account_component_name
  privileged = true

  context = module.this.context
}
