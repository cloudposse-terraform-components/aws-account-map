module "accounts" {
  source  = "cloudposse/stack-config/yaml//modules/remote-state"
  version = "1.8.0"

  component  = "account"
  privileged = true

  context = module.this.context
}
