terraform {
  required_version = ">= 1.5.0"
}

variable "environment" { type = string }
variable "message"     { type = string }

resource "null_resource" "demo" {
  provisioner "local-exec" {
    command = "echo ENV=${var.environment} MSG='${var.message}'"
  }
}

output "message" {
  value = var.message
}

