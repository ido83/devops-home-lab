include "root" {
  path = find_in_parent_folders("terragrunt.hcl")
}

terraform {
  source = "../../modules/null-example"
}

inputs = {
  message = "Hello from Terragrunt (dev)"
}

