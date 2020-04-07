output "public_ip" {
  value = module.ec2_minecraft.public_ip[0]
}

output "id" {
  value = module.ec2_minecraft.id[0]
}

