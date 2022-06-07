locals {
  name = var.is_public_required ? "External" : "Internal"
}