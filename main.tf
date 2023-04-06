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
      cidr_blocks = [module.vpc.vpc_cidr_block]
    }
  }
  dynamic "egress" {
    for_each = toset(local.ports_out)
    content {
      description = "All traffic to internet"
      from_port   = egress.value
      to_port     = egress.value
      protocol    = "-1"
      cidr_blocks = [module.vpc.vpc_cidr_block]
    }
  }

  tags = {
    Terraform   = "true"
    Environment = "dev"
    service = "jenkins"
  }  
}

resource "aws_security_group" "efs_sg" {
  name        = "efs-service"
  description = "Security group for efs with custom ports open within VPC"
  vpc_id      = module.vpc.vpc_id

  ingress {
      description = "Traffic from EC2"
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      security_groups = [aws_security_group.jenkins_service_sg.id]
    }
  
  egress {
      description = "All traffic to EC2"
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      security_groups = [aws_security_group.jenkins_service_sg.id]
    }
  

  tags = {
    Terraform   = "true"
    Environment = "dev"
    service = "jenkins"
  }  
}
  
resource "aws_security_group" "jenkins_alb_sg" {
  name        = "jenkins-alb"
  description = "Security group for jenkins-alb with custom ports open within VPC, and PostgreSQL publicly open"
  vpc_id      = module.vpc.vpc_id

   ingress {
      description = "Traffic from internet"
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      security_groups = ["0.0.0.0/0"]
    }
  
  
  tags = {
    Terraform   = "true"
    Environment = "dev"
    service = "jenkins"
  }  
}
  
resource "aws_efs_file_system" "jenkins_efs" {
  creation_token = "jenkins-efs"
  encrypted = "true"

  tags = {
    Terraform   = "true"
    Environment = "dev"
    service = "jenkins"
  }
}
   
resource "aws_efs_mount_target" "az1" {
  file_system_id = aws_efs_file_system.jenkins_efs.id
  subnet_id      = module.vpc.private_subnets[0]
  security_groups = [aws_security_group.jenkins_service_sg.id]
     
}
  
resource "aws_efs_mount_target" "az2" {
  file_system_id = aws_efs_file_system.jenkins_efs.id
  subnet_id      = module.vpc.private_subnets[1]
  security_groups = [aws_security_group.jenkins_service_sg.id]
      
} 
  
resource "aws_efs_mount_target" "az3" {
  file_system_id = aws_efs_file_system.jenkins_efs.id
  subnet_id      = module.vpc.private_subnets[2]
  security_groups = [aws_security_group.jenkins_service_sg.id] 
     
}
  
 
  
data "aws_iam_policy_document" "policy" {
  statement {
    sid    = "efsaccesspolicy"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions = [
      "elasticfilesystem:ClientMount",
      "elasticfilesystem:ClientWrite",
    ]

    resources = [aws_efs_file_system.jenkins_efs.arn]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["true"]
    }
  }
}

resource "aws_efs_file_system_policy" "policy" {
  file_system_id                     = aws_efs_file_system.jenkins_efs.id
  bypass_policy_lockout_safety_check = true
  policy                             = data.aws_iam_policy_document.policy.json
}

  
resource "aws_launch_template" "jenkins_lt" {
  name = "jenkins-lt"
 
  image_id = var.amiid
  instance_type = var.instancetype
  key_name = var.sshkey
  monitoring {
    enabled = true
  }

 vpc_security_group_ids = [aws_security_group.jenkins_service_sg.id]

  tag_specifications {
    resource_type = "instance"
    Terraform   = "true"
    Environment = "dev"
    service = "jenkins"
  }
    
  tags = {
      Name = "jenkins-lt"
      Terraform   = "true"
      Environment = "dev"
      service = "jenkins"
    }
  
  
}
  
resource "aws_autoscaling_group" "jenkins_asg" {
  availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]
  desired_capacity   = 1
  max_size           = 1
  min_size           = 1

  launch_template {
    id      = aws_launch_template.jenkins_lt.id
    version = "$Latest"
  }
}
  
resource "aws_lb" "jenkins_lab" {
  name               = "jenkins-lab"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [module.vpc.public_subnets]

  enable_deletion_protection = false

  
  tags = {
      Name = "jenkins-lt"
      Terraform   = "true"
      Environment = "dev"
      service = "jenkins"
  }
}  


