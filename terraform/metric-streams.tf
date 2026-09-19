# Approach 3: Export/stream CloudWatch metrics out of CloudWatch entirely,
# straight into Grafana Cloud, bypassing the CloudWatch console/API view
# entirely (unlike Approaches 1 and 2).
#
# Metric Streams must be declared in the account that actually emits the
# metrics — so this is per-account (account_a, account_b, account_c), each
# using its own provider alias via the metric-stream module. Firehose
# delivers directly to Grafana Cloud's CloudWatch Metric Streams HTTP
# endpoint; S3 is only a per-account failure backup (FailedDataOnly), not
# the primary data path — matching Grafana's own reference architecture for
# this integration.

module "metric_stream_account_a" {
  source = "./modules/metric-stream"
  providers = {
    aws = aws.account_a
  }

  account_key                     = "account_a"
  grafana_metric_streams_endpoint = local.grafana_metric_streams_endpoint
  grafana_prometheus_user_id      = data.grafana_cloud_stack.this.prometheus_user_id
  grafana_metrics_write_token     = grafana_cloud_access_policy_token.metrics_write.token
}

module "metric_stream_account_b" {
  source = "./modules/metric-stream"
  providers = {
    aws = aws.account_b
  }

  account_key                     = "account_b"
  grafana_metric_streams_endpoint = local.grafana_metric_streams_endpoint
  grafana_prometheus_user_id      = data.grafana_cloud_stack.this.prometheus_user_id
  grafana_metrics_write_token     = grafana_cloud_access_policy_token.metrics_write.token
}

module "metric_stream_account_c" {
  source = "./modules/metric-stream"
  providers = {
    aws = aws.account_c
  }

  account_key                     = "account_c"
  grafana_metric_streams_endpoint = local.grafana_metric_streams_endpoint
  grafana_prometheus_user_id      = data.grafana_cloud_stack.this.prometheus_user_id
  grafana_metrics_write_token     = grafana_cloud_access_policy_token.metrics_write.token
}
