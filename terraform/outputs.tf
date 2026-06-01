output "data_bucket" {
  description = "Name of the S3 data bucket holding raw, processed, archive, and rejected zones."
  value       = aws_s3_bucket.data.bucket
}

output "logs_bucket" {
  description = "Name of the S3 bucket receiving access logs."
  value       = aws_s3_bucket.logs.bucket
}

output "state_machine" {
  description = "ARN of the Step Functions state machine that orchestrates the pipeline."
  value       = aws_sfn_state_machine.pipeline.arn
}

output "ddb_genre_table" {
  description = "DynamoDB table holding per-genre daily KPIs."
  value       = aws_dynamodb_table.genre_kpis.name
}

output "ddb_top_table" {
  description = "DynamoDB table holding top-5 genres per day."
  value       = aws_dynamodb_table.top_genres.name
}

output "alerts_topic" {
  description = "ARN of the SNS topic that receives pipeline failure notifications."
  value       = aws_sns_topic.alerts.arn
}

output "glue_jobs" {
  description = "Names of the registered Glue jobs."
  value = {
    validate  = aws_glue_job.validate.name
    transform = aws_glue_job.transform.name
    load      = aws_glue_job.load.name
  }
}
