provider "aws" {
  region = var.aws_region
}

data "aws_availability_zones" "available" {}

locals {
  region = var.aws_region
  name   = "acme-hashi-test"

  vpc_cidr = "10.0.0.0/16"
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)

  tags = {
    Name       = local.name
    Example    = local.name
  }
}

##################################################################
# Application Load Balancer
##################################################################

module "alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "9.9.0"

  name    = local.name
  vpc_id  = module.vpc.vpc_id
  subnets = module.vpc.public_subnets

  # For example only
  enable_deletion_protection = false

  # Security Group
  security_group_ingress_rules = {
    all_http = {
      from_port   = 80
      to_port     = 82
      ip_protocol = "tcp"
      description = "HTTP web traffic"
      cidr_ipv4   = "0.0.0.0/0"
    }
  }

  security_group_egress_rules = {
    all = {
      ip_protocol = "-1"
      cidr_ipv4   = module.vpc.vpc_cidr_block
    }
  }

  access_logs = {
    bucket = module.log_bucket.s3_bucket_id
    prefix = "access-logs"
  }

  connection_logs = {
    bucket  = module.log_bucket.s3_bucket_id
    enabled = true
    prefix  = "connection-logs"
  }

  client_keep_alive = 7200

  listeners = {
    http = {
      port               = 80
      protocol           = "HTTP"
      forward = {
        target_group_key = "acme-instance"
      }
    }
  }

  target_groups = {
    acme-instance = {
      name_prefix                       = "acme-"
      protocol                          = "HTTP"
      port                              = 80
      target_type                       = "instance"
      deregistration_delay              = 10
      load_balancing_algorithm_type     = "weighted_random"
      load_balancing_anomaly_mitigation = "on"
      load_balancing_cross_zone_enabled = false

      health_check = {
        enabled             = true
        interval            = 30
        path                = "/index.html"
        port                = "traffic-port"
        healthy_threshold   = 3
        unhealthy_threshold = 3
        timeout             = 6
        protocol            = "HTTP"
        matcher             = "200-399"
      }

      protocol_version = "HTTP1"
      target_id        = aws_instance.this.id
      port             = 80
      tags = {
        InstanceTargetGroupTag = "baz"
      }
    }
  }

  additional_target_group_attachments = {
    instance-other = {
      target_group_key = "acme-instance"
      target_type      = "instance"
      target_id        = aws_instance.other.id
      port             = "80"
    }
  }

  tags = local.tags
}

################################################################################
# Supporting resources
################################################################################

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = local.name
  cidr = local.vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 48)]

  enable_nat_gateway = true
  single_nat_gateway = true
  one_nat_gateway_per_az = false

  tags = local.tags
}

resource "aws_security_group" "instance" {
  name        = "acme-instance-sg"
  description = "SG for the web server instances"
  vpc_id      = module.vpc.vpc_id

  # Allow outbound internet access.
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group_rule" "opened_to_alb" {
  type                     = "ingress"
  from_port                = 80
  to_port                  = 82
  protocol                 = "tcp"
  source_security_group_id = module.alb.security_group_id
  security_group_id        = aws_security_group.instance.id
}


data "aws_ssm_parameter" "al2" {
  name = "/aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2"
}

resource "aws_instance" "this" {
  ami           = data.aws_ssm_parameter.al2.value
  instance_type = var.instance_type
  subnet_id     = element(module.vpc.private_subnets, 0)

  security_groups = [aws_security_group.instance.id]

  user_data = <<-EOF
    #!/bin/bash
    sudo yum update -y
    sudo yum install httpd -y
    sudo systemctl enable httpd
    sudo systemctl start httpd
    echo "<html><body><div>Hello, this is THIS!</div></body></html>" > /var/www/html/index.html
    EOF
}

resource "aws_instance" "other" {
  ami           = data.aws_ssm_parameter.al2.value
  instance_type = var.instance_type
  subnet_id     = element(module.vpc.private_subnets, 0)

  security_groups = [aws_security_group.instance.id]

  user_data = <<-EOF
    #!/bin/bash
    sudo yum update -y
    sudo yum install httpd -y
    sudo systemctl enable httpd
    sudo systemctl start httpd
    echo "<html><body><div>Hello, this is OTHER!</div></body></html>" > /var/www/html/index.html
    EOF
}

module "log_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 3.0"

  bucket_prefix = "${local.name}-logs-"
  acl           = "log-delivery-write"

  # For example only
  force_destroy = true

  control_object_ownership = true
  object_ownership         = "ObjectWriter"

  attach_elb_log_delivery_policy = true # Required for ALB logs
  attach_lb_log_delivery_policy  = true # Required for ALB/NLB logs

  attach_deny_insecure_transport_policy = true
  attach_require_latest_tls_policy      = true

  tags = local.tags
}