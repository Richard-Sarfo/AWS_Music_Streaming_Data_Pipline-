resource "aws_sns_topic" "alerts" {
  name = "${local.name_prefix}-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_cloudwatch_log_group" "sfn" {
  name              = "/aws/vendedlogs/states/${local.name_prefix}-pipeline"
  retention_in_days = 30
}
