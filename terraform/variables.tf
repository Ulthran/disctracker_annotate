variable "aws_region" {
  description = "AWS region for the infrastructure."
  type        = string
  default     = "us-east-1"
}

variable "bucket_name" {
  description = "Name of the S3 bucket that stores the built SPA assets."
  type        = string
}

variable "index_document" {
  description = "Primary HTML document served by CloudFront."
  type        = string
  default     = "index.html"
}

variable "error_document" {
  description = "Optional error document to return for SPA routing."
  type        = string
  default     = null
}

variable "index_document_source" {
  description = "Path to the built index.html file that should be uploaded to S3."
  type        = string
}

variable "price_class" {
  description = "CloudFront price class to control edge locations."
  type        = string
  default     = "PriceClass_100"
}

variable "tags" {
  description = "Common tags applied to all resources."
  type        = map(string)
  default     = {}
}
