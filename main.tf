terraform {
  # 1. This tells Terraform where to store the "Actual State"
  backend "s3" {
    bucket = "test-terraform-state-bucket-cloudfront-test"
    key    = "cloudfront/terraform.tfstate"
    region = "us-east-1"
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

variable "supertab_rewrite_license_path_function_name" {
  type = string
  default = "supertab-rewrite-license-path"
}

resource "aws_cloudfront_function" "supertab_rewrite_license_path_function" {
  name    = var.supertab_rewrite_license_path_function_name
  publish = true
  comment = "Rewrites /license.xml to supertab-connect path"

  runtime = "cloudfront-js-2.0"
  code    = <<-EOT
function handler(event) {
    var request = event.request;
    var originalUri = request.uri;

    var merchantURN = "urn:stc:merchant:system:b534d57b-6eb3-4f3c-83dd-6d789620aa62";

    // Rewrite the path
    request.uri = '/merchants/systems/' + merchantURN + originalUri;

    return request;
}
EOT
}

# 2. Defining the CloudFront Distribution
variable "supertab_connect_origin_id" {
  type    = string
  default = "supertab-connect-origin"
}

variable "supertab_rewrite_license_path_function_arn" {
  type = string
  default = "arn:aws:cloudfront::637423387169:function/supertab-rewrite-license-path"
}

resource "aws_cloudfront_distribution" "test_website" {
  enabled = true

  origin {
    domain_name = "api-connect.sbx.supertab.co"
    origin_id   = var.supertab_connect_origin_id

    custom_origin_config {
        http_port              = 80
        https_port             = 443
        origin_protocol_policy = "https-only"
        origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id       = var.supertab_connect_origin_id
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["GET", "HEAD", "OPTIONS"]
    cached_methods  = ["GET", "HEAD"]

    # This uses the "Managed-CachingOptimized" policy (AWS's recommended default)
    # This replaces the old "forwarded_values" block for a cleaner config
    cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6"

    compress = true
  }

  # Cache behavior with precedence 0
  ordered_cache_behavior {
    path_pattern     = "/license.xml"
    allowed_methods = ["GET", "HEAD"]
    cached_methods = ["GET", "HEAD"]
    target_origin_id = var.supertab_connect_origin_id

    forwarded_values {
      query_string = false
      headers = ["Origin"]

      cookies {
        forward = "none"
      }
    }

    function_association {
      event_type   = "viewer-request"
      function_arn = var.supertab_rewrite_license_path_function_arn
    }

    min_ttl                = 0
    default_ttl            = 86400
    max_ttl                = 31536000
    compress               = true
    viewer_protocol_policy = "redirect-to-https"
  }

  restrictions {
    geo_restriction { restriction_type = "none" }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}
