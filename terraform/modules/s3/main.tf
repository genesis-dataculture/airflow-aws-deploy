# # data "aws_s3_bucket" "airflow_bucket" {
# #   bucket = var.airflow_bucket_name
# # }

# # resource "aws_s3_bucket_ownership_controls" "airflow_bucket" {
# #   bucket = data.aws_s3_bucket.airflow_bucket.id
# #   rule {
# #     object_ownership = "BucketOwnerPreferred"
# #   }
# # }

# # resource "aws_s3_bucket_acl" "airflow_bucket" {
# #   depends_on = [aws_s3_bucket_ownership_controls.airflow_bucket]
# #   bucket = data.aws_s3_bucket.airflow_bucket.id
# #   acl    = "private"
# # }

# # resource "aws_s3_bucket_versioning" "airflow_bucket" {
# #   bucket = data.aws_s3_bucket.airflow_bucket.id
# #   versioning_configuration {
# #     status = "Enabled"
# #   }
# # }

# resource "aws_sns_topic" "airflow_dags_updates" {
#   name = "airflow-dags-updates"
# }

# resource "aws_sns_topic_policy" "airflow_dags_updates" {
#   arn = aws_sns_topic.airflow_dags_updates.arn

#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Effect = "Allow"
#         Principal = {
#           Service = "s3.amazonaws.com"
#         }
#         Action = "sns:Publish"
#         Resource = aws_sns_topic.airflow_dags_updates.arn
#         Condition = {
#           StringEquals = {
#             "aws:SourceAccount" = data.aws_caller_identity.current.account_id
#           }
#         }
#       }
#     ]
#   })
# }

# resource "aws_s3_bucket_notification" "bucket_notification" {
#   depends_on = [aws_sns_topic_policy.airflow_dags_updates]
#   bucket     = data.aws_s3_bucket.airflow_bucket.id

#   topic {
#     topic_arn     = aws_sns_topic.airflow_dags_updates.arn
#     events        = ["s3:ObjectCreated:*", "s3:ObjectRemoved:*"]
#     filter_prefix = "dags/"
#   }
# }

# data "aws_caller_identity" "current" {}