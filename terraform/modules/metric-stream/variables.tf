variable "account_key" {
  description = "Logical name of the account this runs in (account_a/b/c), used for resource naming"
  type        = string
}

variable "grafana_metric_streams_endpoint" {
  description = "Grafana Cloud's CloudWatch Metric Streams Firehose HTTP endpoint for this stack, e.g. https://aws-metric-streams-<cluster>.grafana.net/aws-metrics/api/v1/push"
  type        = string
}

variable "grafana_prometheus_user_id" {
  description = "Grafana Cloud stack's Prometheus/metrics user ID (numeric), used as the Firehose access_key username"
  type        = string
}

variable "grafana_metrics_write_token" {
  description = "Grafana Cloud access policy token scoped for metrics:write, used as the Firehose access_key password"
  type        = string
  sensitive   = true
}
