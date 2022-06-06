output "bastion_ip" {
  value = module.bastion.public_ip
}

output "ecr_repo_url" {
  value = module.ecr.url
}
