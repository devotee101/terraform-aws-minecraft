// This module creates a single EC2 instance for running a Minecraft server

// Tested with this version of Terraform
terraform {
  required_version = ">= 0.12.21"
}

// Find latest Ubuntu AMI, use as default if no AMI specified
data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name = "name"
    values = [
    "ubuntu/images/hvm-ssd/ubuntu-xenial-16.04-amd64-server-*"]
  }

  filter {
    name = "virtualization-type"
    values = [
    "hvm"]
  }

  owners = [
  "099720109477"]
  # Canonical
}

// S3 bucket info
data "aws_s3_bucket" "mc" {
  bucket = var.bucket_id
}

// IAM role for S3 access
resource "aws_iam_role" "allow_s3" {
  name               = "minecraft-ec2-to-s3"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_instance_profile" "mc" {
  name = "minecraft_instance_profile"
  role = aws_iam_role.allow_s3.name
}

resource "aws_iam_role_policy" "mc_allow_ec2_to_s3" {
  name   = "mc_allow_ec2_to_s3"
  role   = aws_iam_role.allow_s3.id
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:ListBucket"],
      "Resource": ["${data.aws_s3_bucket.mc.arn}"]
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject",
        "s3:DeleteObject"
      ],
      "Resource": ["${data.aws_s3_bucket.mc.arn}/*"]
    }
  ]
}
EOF
}

// Script to configure the server - this is where most of the magic occurs!
data "template_file" "user_data" {
  template = file("${path.module}/user_data.sh")

  vars = {
    mc_root        = var.mc_root
    mc_bucket      = var.bucket_id
    mc_backup_freq = var.mc_backup_freq
    mc_version     = var.mc_version
    java_mx_mem    = var.java_mx_mem
    java_ms_mem    = var.java_ms_mem
  }
}

// Security group for our instance - allows SSH and minecraft 
module "ec2_security_group" {
  source = "terraform-aws-modules/security-group/aws"

  name        = "${var.name}-ec2"
  description = "Allow SSH and TCP ${var.mc_port}"
  vpc_id      = var.vpc_id

  ingress_cidr_blocks = [
  var.allowed_cidrs]
  ingress_rules = [
  "ssh-tcp"]
  ingress_with_cidr_blocks = [
    {
      from_port   = var.mc_port
      to_port     = var.mc_port
      protocol    = "tcp"
      description = "Minecraft server"
      cidr_blocks = var.allowed_cidrs
    },
  ]
  egress_rules = [
  "all-all"]
}

// EC2 spot instance for the server
resource "aws_spot_instance_request" "ec2_minecraft" {
  # instance
  key_name             = var.key_name
  ami                  = var.ami != "" ? var.ami : data.aws_ami.ubuntu.image_id
  instance_type        = var.instance_type
  iam_instance_profile = aws_iam_instance_profile.mc.id
  user_data            = data.template_file.user_data.rendered

  # network
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [module.ec2_security_group.this_security_group_id]
  associate_public_ip_address = var.associate_public_ip_address

  # spot instance
  spot_price           = var.spot_price
  wait_for_fulfillment = true
  spot_type            = "one-time"

  tags = {
    Name   = "${var.name}-public"
    tostop = "true"
  }
}

data "aws_eip" "by_public_ip" {
  public_ip = var.elastic_ip
}

resource "aws_eip_association" "this" {
  instance_id   = aws_spot_instance_request.ec2_minecraft.spot_instance_id
  allocation_id = data.aws_eip.by_public_ip.id
}

module "ec2_stop_weekday" {
  source                         = "diodonfrost/lambda-scheduler-stop-start/aws"
  name                           = "ec2_stop_weekday"
  cloudwatch_schedule_expression = "cron(0 21 ? * MON-FRI *)"
  schedule_action                = "stop"
  autoscaling_schedule           = "false"
  spot_schedule                  = "terminate"
  ec2_schedule                   = "true"
  rds_schedule                   = "false"
  resources_tag = {
    key   = "tostop"
    value = "true"
  }
}

module "ec2_stop_weekend" {
  source                         = "diodonfrost/lambda-scheduler-stop-start/aws"
  name                           = "ec2_stop_weekend"
  cloudwatch_schedule_expression = "cron(0 22 ? * SAT-SUN *)"
  schedule_action                = "stop"
  autoscaling_schedule           = "false"
  spot_schedule                  = "terminate"
  ec2_schedule                   = "true"
  rds_schedule                   = "false"
  resources_tag = {
    key   = "tostop"
    value = "true"
  }
}

module "ec2_start_weekday" {
  source                         = "diodonfrost/lambda-scheduler-stop-start/aws"
  name                           = "ec2_start_weekday"
  cloudwatch_schedule_expression = "cron(0 8 ? * MON-FRI *)"
  schedule_action                = "stop"
  autoscaling_schedule           = "false"
  spot_schedule                  = "terminate"
  ec2_schedule                   = "true"
  rds_schedule                   = "false"
  resources_tag = {
    key   = "tostop"
    value = "true"
  }
}

module "ec2_start_weekend" {
  source                         = "diodonfrost/lambda-scheduler-stop-start/aws"
  name                           = "ec2_start_weekend"
  cloudwatch_schedule_expression = "cron(0 9 ? * SAT-SUN *)"
  schedule_action                = "stop"
  autoscaling_schedule           = "false"
  spot_schedule                  = "terminate"
  ec2_schedule                   = "true"
  rds_schedule                   = "false"
  resources_tag = {
    key   = "tostop"
    value = "true"
  }
}
