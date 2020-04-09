output "public_ip" {
  value = aws_spot_instance_request.ec2_minecraft.public_ip
}

output "id" {
  value = aws_spot_instance_request.ec2_minecraft.spot_instance_id
}

