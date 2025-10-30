variable "origin_domain_name" {
  description = "Domain name do ALB (sem protocolo)"
  type        = string
}

variable "price_class" {
  description = "CloudFront price class"
  type        = string
  default     = "PriceClass_100"
}
