terraform {
  backend "s3" {
      }
}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "jenkins-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["us-east-1a", "us-east-1b", "us-east-1c"]
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
      cidr_blocks = ["0.0.0.0/0"]
    }
    
  egress {
      description = "All traffic to EC2"
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = [module.vpc.vpc_cidr_block]
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
  subnet_id      = module.vpc.public_subnets[0]
  security_groups = [aws_security_group.efs_sg.id]
     
}
  
resource "aws_efs_mount_target" "az2" {
  file_system_id = aws_efs_file_system.jenkins_efs.id
  subnet_id      = module.vpc.public_subnets[1]
  security_groups = [aws_security_group.efs_sg.id]
      
} 
  
resource "aws_efs_mount_target" "az3" {
  file_system_id = aws_efs_file_system.jenkins_efs.id
  subnet_id      = module.vpc.public_subnets[2]
  security_groups = [aws_security_group.efs_sg.id] 
     
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
  
 user_data = "${base64encode(<<EOF
  #!/bin/bash
  curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key | \
         sudo tee   /usr/share/keyrings/jenkins-keyring.asc > /dev/null
  echo deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc]  \
       https://pkg.jenkins.io/debian-stable binary/ | sudo tee  \
       /etc/apt/sources.list.d/jenkins.list > /dev/null
  sudo apt update -y
  sudo apt install openjdk-11-jre -y
  sudo apt install jenkins -y
  sudo systemctl enable jenkins
EOF
)}"

  tag_specifications {
    resource_type = "instance"
   
    
  tags = {
      Name = "jenkins-lt"
      Terraform   = "true"
      Environment = "dev"
      service = "jenkins"
    }
}
  
}
  
resource "aws_autoscaling_group" "jenkins_asg" {
  vpc_zone_identifier       = [ module.vpc.public_subnets[0], module.vpc.public_subnets[1], module.vpc.public_subnets[2] ]
  desired_capacity   = 1
  max_size           = 1
  min_size           = 1
  target_group_arns = [aws_lb_target_group.jenkins_tg.arn]

  launch_template {
    id      = aws_launch_template.jenkins_lt.id
    version = "$Latest"
  }
}
  
resource "aws_lb" "jenkins_alb" {
  name               = "jenkins-lab"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.jenkins_alb_sg.id]
  subnets            = [module.vpc.public_subnets[0], module.vpc.public_subnets[1], module.vpc.public_subnets[2] ]

  enable_deletion_protection = false

  
  tags = {
      Name = "jenkins-lt"
      Terraform   = "true"
      Environment = "dev"
      service = "jenkins"
  }
}
    
resource "aws_lb_target_group" "jenkins_tg" {
  name     = "jenkins-tg"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = module.vpc.vpc_id
}
  
data "aws_acm_certificate" "amazon_issued" {
  domain      = "lbncyberlabs.com"
  types       = ["AMAZON_ISSUED"]
  most_recent = true
}  

resource "aws_lb_listener" "jenkins_frontend" {
  load_balancer_arn = aws_lb.jenkins_alb.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = data.aws_acm_certificate.amazon_issued.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.jenkins_tg.arn
  }
}  

data "aws_route53_zone" "lbn" {
  name         = "lbncyberlabs.com."
  private_zone = false
}
  
  
resource "aws_route53_record" "jenkins" {
  zone_id = data.aws_route53_zone.lbn.zone_id
  name    = "ci.lbncyberlabs.com"
  type    = "A"

  alias {
    name                   = aws_lb.jenkins_alb.dns_name
    zone_id                = aws_lb.jenkins_alb.zone_id
    evaluate_target_health = false
  }
}


