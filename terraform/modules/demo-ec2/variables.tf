variable "name" {
  description = "Name tag / identifier for this instance, unique per region it's used in"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "allowed_ssh_cidr" {
  description = "CIDR allowed to SSH into the instance (your own IP, /32) — no default, must be set explicitly"
  type        = string
}
