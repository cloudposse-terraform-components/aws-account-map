module "accounts" {
  source  = "cloudposse/stack-config/yaml//modules/remote-state"
  version = "2.0.1"

  component  = "account"
  privileged = true

  context = module.this.context
}
