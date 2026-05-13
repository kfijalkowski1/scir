include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "../../../modules/data"
}

inputs = {
  discord_webhook_url = get_env("SCIR_DISCORD_WEBHOOK_URL", "")
  webhook_auth_token  = get_env("SCIR_WEBHOOK_AUTH_TOKEN", "")
}
