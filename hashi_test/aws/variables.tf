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
  description = "AWS region for all resources"
}

variable "name" {
  type        = string
  description = "Name of the project"
}