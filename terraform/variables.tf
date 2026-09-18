# All account/org/stack identifiers are inputs with placeholder defaults.
# Never replace these defaults with real values in a committed file — override
# them locally via terraform.tfvars (gitignored) or -var flags instead.

variable "monitoring_account_id" {
  description = "AWS account ID that acts as the CloudWatch monitoring/aggregation account"
  type        = string
  default     = "111122223333"
}

variable "source_account_ids" {
  description = "AWS account IDs that will share CloudWatch data into the monitoring account"
  type        = list(string)
  default     = ["444455556666", "777788889999"]
}

variable "org_id" {
  description = "AWS Organizations ID that source/monitoring accounts belong to"
  type        = string
  default     = "o-exampleorgid"
}

variable "regions" {
  description = "Regions to demonstrate cross-region aggregation across"
  type        = list(string)
  default     = ["us-east-1", "us-west-2", "eu-central-1"]
}

# Three demo member accounts, one per region — except account_b, which
# deliberately shares account_a's region. That pair proves real cross-account
# OAM linking (same region, two accounts); account_c sits in a third region
# to demonstrate that OAM sinks/links cannot cross regions.
variable "demo_accounts" {
  description = "Demo member accounts: key -> region. account_a and account_b share a region on purpose."
  type        = map(string)
  default = {
    account_a = "us-east-1" # OAM monitoring account's region
    account_b = "us-east-1" # same region as account_a -> can link via OAM
    account_c = "us-west-2" # different region -> cannot link into account_a's sink
  }
}

variable "grafana_cloud_stack_slug" {
  description = "Grafana Cloud stack slug that receives CloudWatch data"
  type        = string
  default     = "example-stack"
}

variable "firehose_destination_bucket" {
  description = "Name of the S3 bucket that Metric Streams data is delivered to"
  type        = string
  default     = "example-metric-streams-bucket"
}

variable "grafana_cloud_access_policy_token" {
  description = "Grafana Cloud access policy token (set via env var TF_VAR_grafana_cloud_access_policy_token)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "grafana_aws_external_id" {
  description = "External ID provided by Grafana Cloud for the Assume Role trust policy"
  type        = string
  sensitive   = true
  default     = ""
}

# --- Real-infra switches -----------------------------------------------
# All default to false/inert so cloning and planning this repo never
# provisions anything. Flip these in your own gitignored terraform.tfvars.

variable "create_account" {
  description = "If true, creates a real AWS member account via aws_organizations_account"
  type        = bool
  default     = false
}

variable "demo_account_name" {
  description = "Name for the new AWS member account (only used if create_account = true)"
  type        = string
  default     = "cloudwatch-demo"
}

variable "demo_account_email" {
  description = "Root email for the new AWS member account (only used if create_account = true)"
  type        = string
  default     = ""
}

variable "demo_account_parent_ou_id" {
  description = "Organizational Unit ID the new account is created under (only used if create_account = true)"
  type        = string
  default     = ""
}

variable "create_ec2_instances" {
  description = "If true, launches one small EC2 instance per region to generate real CloudWatch metrics"
  type        = bool
  default     = false
}

variable "allowed_ssh_cidr" {
  description = "CIDR allowed to SSH into demo EC2 instances (your own IP, /32) — required if create_ec2_instances = true"
  type        = string
  default     = ""
}
