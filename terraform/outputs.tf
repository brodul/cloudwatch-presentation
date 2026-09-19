
output "metrics_read_token" {
  value     = grafana_cloud_access_policy_token.metrics_read.token
  sensitive = true
}

output "metrics_write_token" {
  value     = grafana_cloud_access_policy_token.metrics_write.token
  sensitive = true
}

output "stack_admin_token" {
  value     = grafana_cloud_stack_service_account_token.this.key
  sensitive = true
}
