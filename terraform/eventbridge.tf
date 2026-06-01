resource "aws_cloudwatch_event_rule" "streams_landed" {
  name        = "${local.name_prefix}-streams-landed"
  description = "Trigger the pipeline when a new stream file lands under raw/streams/"

  event_pattern = jsonencode({
    source        = ["aws.s3"]
    "detail-type" = ["Object Created"]
    detail = {
      bucket = { name = [aws_s3_bucket.data.id] }
      object = { key = [{ prefix = "raw/streams/" }] }
    }
  })
}

resource "aws_cloudwatch_event_target" "to_sfn" {
  rule     = aws_cloudwatch_event_rule.streams_landed.name
  arn      = aws_sfn_state_machine.pipeline.arn
  role_arn = aws_iam_role.events.arn

  input_transformer {
    input_paths = {
      bucket = "$.detail.bucket.name"
      key    = "$.detail.object.key"
    }
    input_template = "{\"bucket\":\"<bucket>\",\"key\":\"<key>\"}"
  }
}
