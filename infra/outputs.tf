output "bucket_name" {
  description = "Name of the S3 bucket hosting the SPA artifacts."
  value       = aws_s3_bucket.spa.bucket
}

output "cloudfront_distribution_id" {
  description = "Identifier of the CloudFront distribution serving the SPA."
  value       = aws_cloudfront_distribution.spa.id
}

output "cloudfront_domain_name" {
  description = "Public domain name of the CloudFront distribution."
  value       = aws_cloudfront_distribution.spa.domain_name
}
