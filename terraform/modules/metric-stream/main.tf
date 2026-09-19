# One CloudWatch Metric Stream + Firehose delivery stream, sending directly
# to Grafana Cloud's CloudWatch Metric Streams HTTP endpoint (OTLP 1.0
# format — required; Grafana's ingest service does not accept JSON here).
# S3 is used only as a failure backup (FailedDataOnly), matching Grafana's
# own reference Terraform for this integration — not the primary data path.

resource "aws_s3_bucket" "failed_delivery" {
  # S3 bucket names allow only lowercase alphanumeric characters and hyphens.
  bucket = "cw-metric-stream-failed-${replace(var.account_key, "_", "-")}"
}

resource "aws_iam_role" "firehose_delivery" {
  name = "metric-stream-firehose-delivery"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "firehose.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "firehose_delivery_s3" {
  name = "firehose-delivery-s3-backup"
  role = aws_iam_role.firehose_delivery.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetBucketLocation",
          "s3:ListBucket",
        ]
        Resource = [
          aws_s3_bucket.failed_delivery.arn,
          "${aws_s3_bucket.failed_delivery.arn}/*",
        ]
      }
    ]
  })
}

resource "aws_kinesis_firehose_delivery_stream" "metric_stream" {
  name        = "metric-stream-${var.account_key}"
  destination = "http_endpoint"

  http_endpoint_configuration {
    url  = var.grafana_metric_streams_endpoint
    name = "Grafana Cloud CloudWatch Metric Streams"

    access_key = "${var.grafana_prometheus_user_id}:${var.grafana_metrics_write_token}"

    buffering_size     = 1
    buffering_interval = 60
    role_arn           = aws_iam_role.firehose_delivery.arn
    s3_backup_mode     = "FailedDataOnly"

    request_configuration {
      content_encoding = "GZIP"
    }

    s3_configuration {
      role_arn           = aws_iam_role.firehose_delivery.arn
      bucket_arn         = aws_s3_bucket.failed_delivery.arn
      buffering_size     = 5
      buffering_interval = 300
      compression_format = "GZIP"
    }
  }
}

resource "aws_iam_role" "metric_stream" {
  name = "cloudwatch-metric-stream"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "streams.metrics.cloudwatch.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "metric_stream_firehose" {
  name = "metric-stream-firehose"
  role = aws_iam_role.metric_stream.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Metric Streams calls the batch API (PutRecordBatch), not the
        # single-record PutRecord — without both, CloudWatch fails to
        # deliver to Firehose with no visible error on our side.
        Effect = "Allow"
        Action = [
          "firehose:PutRecord",
          "firehose:PutRecordBatch",
        ]
        Resource = aws_kinesis_firehose_delivery_stream.metric_stream.arn
      }
    ]
  })
}

resource "aws_cloudwatch_metric_stream" "this" {
  name          = "meetup-demo-metric-stream-${var.account_key}"
  role_arn      = aws_iam_role.metric_stream.arn
  firehose_arn  = aws_kinesis_firehose_delivery_stream.metric_stream.arn
  output_format = "opentelemetry1.0"
}
