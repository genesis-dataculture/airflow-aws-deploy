terraform {
  backend "s3" {
    region = "us-east-1"
    bucket = "ons-dg-00-dev-stage"
    key    = "airflow/terraform.tfstate"
  }
}