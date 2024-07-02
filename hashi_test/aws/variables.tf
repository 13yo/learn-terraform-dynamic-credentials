variable "domain_name" {
  description = "The domain name for which the certificate should be issued"
  type        = string
  default     = "terraform-aws-modules.modules.tf"
}

variable "instance_type" {
  description = "Type of EC2 instance to use"
  default     = "t2.micro"
  type        = string
}

variable "tags" {
  description = "Tags for instances"
  type        = map(any)
  default     = {}
}

variable "aws_region" {
  type        = string
  default     = "us-west-2"
  description = "AWS region for all resources"
}