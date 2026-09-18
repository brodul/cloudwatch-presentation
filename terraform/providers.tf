terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    grafana = {
      source  = "grafana/grafana"
      version = "~> 3.0"
    }
  }
}

# Default provider represents the monitoring account's primary region.
provider "aws" {
  region = var.regions[0]
}

# One aliased provider per additional region, so cross-region resources
# (OAM sinks/links, Metric Streams) can be declared once per region.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

provider "aws" {
  alias  = "us_west_2"
  region = "us-west-2"
}

provider "aws" {
  alias  = "eu_central_1"
  region = "eu-central-1"
}

# Grafana Cloud provider, authenticated via a Cloud Access Policy token.
# Set via TF_VAR_grafana_cloud_access_policy_token from a gitignored .env, never in this file.
provider "grafana" {
  cloud_access_policy_token = var.grafana_cloud_access_policy_token
}
