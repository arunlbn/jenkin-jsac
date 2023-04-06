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


module "jenkins_service_sg" {
  source = "terraform-aws-modules/security-group/aws"

  name        = "jenkins-service"
  description = "Security group for jenkins-service with custom ports open within VPC, and PostgreSQL publicly open"
  vpc_id      = module.vpc.vpcid

  ingress_cidr_blocks      = ["0.0.0.0/0"]
  ingress_rules            = ["ssh-tcp"]
  ingress_with_cidr_blocks = [
    {
      from_port   = 8080
      to_port     = 8080
      protocol    = "tcp"
      description = "jenkins-service ports"
      cidr_blocks = "0.0.0.0/0"
    },
    {
      rule        = "postgresql-tcp"
      cidr_blocks = "0.0.0.0/0"
    },
  ]
egress_cidr_blocks = ["0.0.0.0/0"]
egress_rules = ["any"]

}




module "ec2_instance" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  version = "~> 3.0"

  name = "jenkins-master"

  ami                    = var.amiid
  instance_type          = "t4g.small"
  key_name               = var.sshkey
  monitoring             = true
  vpc_security_group_ids = module.
  subnet_id              = module.vpc.private_subnets.[0]

  tags = {
    Terraform   = "true"
    Environment = "dev"
    service = "jenkins"
  }
}
