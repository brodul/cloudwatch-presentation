# Approach 3: Export/stream CloudWatch metrics out of CloudWatch entirely
#
# Necessary when you want true consolidation into one queryable store spanning
# accounts and regions (rather than a "view" like OAM/the console feature), or
# long-term retention beyond CloudWatch's own limits. Each region needs its
# own Metric Stream + Firehose delivery stream, but the destination (here, S3)
# can be a single shared bucket.

resource "aws_s3_bucket" "metric_streams" {
  bucket = var.firehose_destination_bucket
}

resource "aws_iam_role" "firehose_delivery" {
  name = "metric-streams-firehose-delivery"

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
  name = "firehose-delivery-s3"
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
          aws_s3_bucket.metric_streams.arn,
          "${aws_s3_bucket.metric_streams.arn}/*",
        ]
      }
    ]
  })
}

resource "aws_kinesis_firehose_delivery_stream" "metric_streams" {
  for_each = toset(var.regions)

  name        = "metric-streams-${each.key}"
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn   = aws_iam_role.firehose_delivery.arn
    bucket_arn = aws_s3_bucket.metric_streams.arn
    prefix     = "region=${each.key}/"
  }
}

resource "aws_iam_role" "metric_streams" {
  name = "cloudwatch-metric-streams"

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

resource "aws_iam_role_policy" "metric_streams_firehose" {
  name = "metric-streams-firehose"
  role = aws_iam_role.metric_streams.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "firehose:PutRecord"
        Resource = [for stream in aws_kinesis_firehose_delivery_stream.metric_streams : stream.arn]
      }
    ]
  })
}

resource "aws_cloudwatch_metric_stream" "this" {
  for_each = toset(var.regions)

  name          = "meetup-demo-metric-stream-${each.key}"
  role_arn      = aws_iam_role.metric_streams.arn
  firehose_arn  = aws_kinesis_firehose_delivery_stream.metric_streams[each.key].arn
  output_format = "opentelemetry1.0"
}
