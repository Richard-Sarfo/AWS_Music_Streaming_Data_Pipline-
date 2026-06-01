locals {
  sfn_definition = jsonencode({
    Comment = "Music streaming ingest pipeline: validate, transform, load, archive"
    StartAt = "Validate"
    States = {
      Validate = {
        Type     = "Task"
        Resource = "arn:aws:states:::glue:startJobRun.sync"
        Parameters = {
          JobName = aws_glue_job.validate.name
          Arguments = {
            "--input_s3.$" = "States.Format('s3://{}/{}', $.bucket, $.key)"
          }
        }
        Retry = [{
          ErrorEquals     = ["Glue.ConcurrentRunsExceededException"]
          IntervalSeconds = 30
          MaxAttempts     = 5
          BackoffRate     = 2.0
        }]
        Catch = [{
          ErrorEquals = ["States.ALL"]
          Next        = "Reject"
          ResultPath  = "$.error"
        }]
        ResultPath = "$.validate"
        Next       = "Transform"
      }

      Transform = {
        Type     = "Task"
        Resource = "arn:aws:states:::glue:startJobRun.sync"
        Parameters = {
          JobName = aws_glue_job.transform.name
          Arguments = {
            "--input_s3.$"  = "States.Format('s3://{}/{}', $.bucket, $.key)"
            "--songs_s3"    = "s3://${aws_s3_bucket.data.id}/raw/songs/songs.csv"
            "--output_s3.$" = "States.Format('s3://${aws_s3_bucket.data.id}/processed/kpis/run={}', $$.Execution.Name)"
          }
        }
        Retry = [{
          ErrorEquals     = ["Glue.ConcurrentRunsExceededException"]
          IntervalSeconds = 30
          MaxAttempts     = 5
          BackoffRate     = 2.0
        }]
        Catch = [{
          ErrorEquals = ["States.ALL"]
          Next        = "NotifyFailure"
          ResultPath  = "$.error"
        }]
        ResultPath = "$.transform"
        Next       = "Load"
      }

      Load = {
        Type     = "Task"
        Resource = "arn:aws:states:::glue:startJobRun.sync"
        Parameters = {
          JobName = aws_glue_job.load.name
          Arguments = {
            "--output_s3.$" = "States.Format('s3://${aws_s3_bucket.data.id}/processed/kpis/run={}', $$.Execution.Name)"
            "--genre_table" = aws_dynamodb_table.genre_kpis.name
            "--top_table"   = aws_dynamodb_table.top_genres.name
          }
        }
        Catch = [{
          ErrorEquals = ["States.ALL"]
          Next        = "NotifyFailure"
          ResultPath  = "$.error"
        }]
        ResultPath = "$.load"
        Next       = "Archive"
      }

      Archive = {
        Type     = "Task"
        Resource = "arn:aws:states:::aws-sdk:s3:copyObject"
        Parameters = {
          "Bucket.$"     = "$.bucket"
          "CopySource.$" = "States.Format('{}/{}', $.bucket, $.key)"
          "Key.$"        = "States.Format('archive/{}', $.key)"
        }
        ResultPath = "$.archive"
        Next       = "DeleteOriginal"
      }

      DeleteOriginal = {
        Type     = "Task"
        Resource = "arn:aws:states:::aws-sdk:s3:deleteObject"
        Parameters = {
          "Bucket.$" = "$.bucket"
          "Key.$"    = "$.key"
        }
        End = true
      }

      Reject = {
        Type     = "Task"
        Resource = "arn:aws:states:::aws-sdk:s3:copyObject"
        Parameters = {
          "Bucket.$"     = "$.bucket"
          "CopySource.$" = "States.Format('{}/{}', $.bucket, $.key)"
          "Key.$"        = "States.Format('rejected/{}', $.key)"
        }
        Next = "NotifyFailure"
      }

      NotifyFailure = {
        Type     = "Task"
        Resource = "arn:aws:states:::sns:publish"
        Parameters = {
          TopicArn    = aws_sns_topic.alerts.arn
          Subject     = "P1 streaming pipeline failure"
          "Message.$" = "$"
        }
        ResultPath = "$.notification"
        Next       = "FailExecution"
      }

      FailExecution = {
        Type  = "Fail"
        Error = "PipelineFailed"
        Cause = "One of Validate, Transform, or Load failed. See execution input for details."
      }
    }
  })
}

resource "aws_sfn_state_machine" "pipeline" {
  name       = "${local.name_prefix}-pipeline"
  role_arn   = aws_iam_role.sfn.arn
  definition = local.sfn_definition

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.sfn.arn}:*"
    include_execution_data = true
    level                  = "ERROR"
  }
}
