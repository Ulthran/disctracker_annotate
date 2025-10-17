provider "aws" {
  region = var.aws_region
}

resource "aws_s3_bucket" "spa" {
  bucket        = var.bucket_name
  force_destroy = true

  tags = merge(var.tags, {
    Component = "disctracker-annotate-frontend"
  })
}

resource "aws_s3_bucket_ownership_controls" "spa" {
  bucket = aws_s3_bucket.spa.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "spa" {
  bucket = aws_s3_bucket.spa.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_cloudfront_origin_access_control" "spa" {
  name                              = "disctracker-annotate-spa"
  description                       = "OAC for disctracker-annotate SPA"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

data "aws_iam_policy_document" "spa_bucket_policy" {
  statement {
    actions = [
      "s3:GetObject"
    ]

    resources = [
      "${aws_s3_bucket.spa.arn}/*"
    ]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.spa.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "spa" {
  bucket = aws_s3_bucket.spa.id
  policy = data.aws_iam_policy_document.spa_bucket_policy.json
}

locals {
  asset_directory    = abspath(var.asset_directory)
  asset_files        = [for file in fileset(local.asset_directory, "**") : file if file != var.index_document]
  default_error_page = var.error_document != null ? var.error_document : var.index_document

  content_type_map = {
    css  = "text/css"
    gif  = "image/gif"
    html = "text/html"
    ico  = "image/x-icon"
    jpg  = "image/jpeg"
    jpeg = "image/jpeg"
    js   = "application/javascript"
    json = "application/json"
    map  = "application/json"
    png  = "image/png"
    svg  = "image/svg+xml"
    txt  = "text/plain"
    webmanifest = "application/manifest+json"
    xml  = "application/xml"
  }
}

resource "aws_cloudfront_distribution" "spa" {
  enabled             = true
  default_root_object = var.index_document

  origin {
    domain_name = aws_s3_bucket.spa.bucket_regional_domain_name
    origin_id   = "spa-s3-origin"

    s3_origin_config {
      origin_access_identity = ""
    }

    origin_access_control_id = aws_cloudfront_origin_access_control.spa.id
  }

  default_cache_behavior {
    allowed_methods          = ["GET", "HEAD", "OPTIONS"]
    cached_methods           = ["GET", "HEAD"]
    target_origin_id         = "spa-s3-origin"
    cache_policy_id          = "658327ea-f89d-4fab-a63d-7e88639e58f6"
    origin_request_policy_id = "88a5eaf4-2fd4-4709-b370-b4c650ea3fcf"

    viewer_protocol_policy = "redirect-to-https"
    compress               = true
  }

  price_class = var.price_class

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  custom_error_response {
    error_caching_min_ttl = 0
    error_code            = 404
    response_code         = 200
    response_page_path    = "/${local.default_error_page}"
  }

  tags = merge(var.tags, {
    Component = "disctracker-annotate-frontend"
  })
}

resource "aws_s3_object" "spa_index" {
  bucket       = aws_s3_bucket.spa.id
  key          = var.index_document
  content_type = "text/html"
  source       = var.index_document_source

  etag = filemd5(var.index_document_source)
}

resource "aws_s3_object" "spa_assets" {
  for_each = { for file in local.asset_files : file => file }

  bucket = aws_s3_bucket.spa.id
  key    = each.key
  source = "${local.asset_directory}/${each.value}"
  etag   = filemd5("${local.asset_directory}/${each.value}")

  content_type = lookup(
    local.content_type_map,
    element(reverse(split(".", lower(each.value))), 0),
    "application/octet-stream"
  )
}
