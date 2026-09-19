# All account/org/stack identifiers are inputs with placeholder defaults.
# Never replace these defaults with real values in a committed file — override
# them locally via terraform.tfvars (gitignored) or -var flags instead.

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

variable "grafana_labs_aws_account_id" {
  description = "Grafana Labs' own published AWS account ID used for the CloudWatch Assume Role integration (not your account) — see https://grafana.com/docs/grafana/latest/datasources/aws-cloudwatch/aws-authentication/"
  type        = string
  default     = "" # fill in from Grafana's docs/portal for your stack/region
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

# Populated *after* phase 1 (creating the accounts) completes — see
# README's two-phase apply instructions. Terraform provider blocks are
# configured before the resource graph resolves, so a provider's assume_role
# cannot reference an aws_organizations_account ID created in the same
# apply; this variable breaks that cycle by letting you paste in the real
# account IDs once they exist, for the second apply that actually populates
# the accounts.
variable "demo_account_ids" {
  description = "Real AWS account IDs for account_a/b/c, filled in after phase 1 (account creation) completes. Leave empty for phase 1."
  type        = map(string)
  default = {
    account_a = ""
    account_b = ""
    account_c = ""
  }
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
