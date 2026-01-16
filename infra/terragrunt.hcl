# ------------------------------------------------------------------------------
# Root terragrunt config: define a local module source and common inputs.
# ------------------------------------------------------------------------------
locals {
  env = "dev"
}

remote_state {
  backend = "local"
  config = {
    path = "${get_terragrunt_dir()}/terraform.tfstate"
  }
}

inputs = {
  environment = local.env
}

