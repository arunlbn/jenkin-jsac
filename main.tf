module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "jenkins-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["us-east-1a", "us-east-1b", "us-east-1c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway = false
  enable_vpn_gateway = false

  tags = {
    Terraform = "true"
    Environment = "dev"
    service = "jenkins"
  }
}
  
  
  
locals {
  ports_in = [
    22,
    8080
  ]
  ports_out = [
    0
  ]
}

resource "aws_security_group" "jenkins_service_sg" {
  name        = "jenkins-service"
  description = "Security group for jenkins-service with custom ports open within VPC, and PostgreSQL publicly open"
  vpc_id      = module.vpc.vpc_id

   dynamic "ingress" {
    for_each = toset(local.ports_in)
    content {
      description = "SSH Jenkins Traffic from internet"
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }
  dynamic "egress" {
    for_each = toset(local.ports_out)
    content {
      description = "All traffic to internet"
      from_port   = egress.value
      to_port     = egress.value
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  tags = {
    Terraform   = "true"
    Environment = "dev"
    service = "jenkins"
  }  
}


module "ec2_instance" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  version = "~> 3.0"

  name = "jenkins-master"

  ami                    = var.amiid
  instance_type          = var.instancetype
  key_name               = var.sshkey
  monitoring             = true
  vpc_security_group_ids = aws_security_group.jenkins_service_sg.id
  subnet_id              = module.vpc.private_subnets[0]

  tags = {
    Terraform   = "true"
    Environment = "dev"
    service = "jenkins"
  }
}
