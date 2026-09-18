# Reference org/account context via data sources instead of resources — this
# example reads whatever org/account it's pointed at rather than creating one,
# so it stays inert (no provisioning) when cloned and planned as-is.

data "aws_organizations_organization" "this" {}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}
