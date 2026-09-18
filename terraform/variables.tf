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
