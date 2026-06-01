resource "aws_s3_object" "script_validate" {
  bucket = aws_s3_bucket.data.id
  key    = "glue-scripts/validate_streams.py"
  source = "${path.module}/../glue_jobs/validate_streams.py"
  etag   = filemd5("${path.module}/../glue_jobs/validate_streams.py")
}

resource "aws_s3_object" "script_transform" {
  bucket = aws_s3_bucket.data.id
  key    = "glue-scripts/transform_kpis.py"
  source = "${path.module}/../glue_jobs/transform_kpis.py"
  etag   = filemd5("${path.module}/../glue_jobs/transform_kpis.py")
}

resource "aws_s3_object" "script_load" {
  bucket = aws_s3_bucket.data.id
  key    = "glue-scripts/load_dynamodb.py"
  source = "${path.module}/../glue_jobs/load_dynamodb.py"
  etag   = filemd5("${path.module}/../glue_jobs/load_dynamodb.py")
}

resource "aws_glue_job" "validate" {
  name         = "${local.name_prefix}-validate"
  role_arn     = aws_iam_role.glue.arn
  glue_version = "4.0"
  max_capacity = 0.0625

  execution_property {
    max_concurrent_runs = 10
  }

  command {
    name            = "pythonshell"
    python_version  = "3.9"
    script_location = "s3://${aws_s3_bucket.data.id}/${aws_s3_object.script_validate.key}"
  }

  default_arguments = {
    "--TempDir"                          = "s3://${aws_s3_bucket.data.id}/glue-temp/"
    "--enable-continuous-cloudwatch-log" = "true"
  }
}

resource "aws_glue_job" "transform" {
  name              = "${local.name_prefix}-transform"
  role_arn          = aws_iam_role.glue.arn
  glue_version      = "4.0"
  worker_type       = "G.1X"
  number_of_workers = 2

  execution_property {
    max_concurrent_runs = 5
  }

  command {
    name            = "glueetl"
    python_version  = "3"
    script_location = "s3://${aws_s3_bucket.data.id}/${aws_s3_object.script_transform.key}"
  }

  default_arguments = {
    "--TempDir"                          = "s3://${aws_s3_bucket.data.id}/glue-temp/"
    "--enable-metrics"                   = "true"
    "--enable-continuous-cloudwatch-log" = "true"
    "--job-language"                     = "python"
  }
}

resource "aws_glue_job" "load" {
  name         = "${local.name_prefix}-load"
  role_arn     = aws_iam_role.glue.arn
  glue_version = "4.0"
  max_capacity = 0.0625

  execution_property {
    max_concurrent_runs = 5
  }

  command {
    name            = "pythonshell"
    python_version  = "3.9"
    script_location = "s3://${aws_s3_bucket.data.id}/${aws_s3_object.script_load.key}"
  }

  default_arguments = {
    "--TempDir"                          = "s3://${aws_s3_bucket.data.id}/glue-temp/"
    "--enable-continuous-cloudwatch-log" = "true"
    "--additional-python-modules"        = "boto3>=1.34"
  }
}
