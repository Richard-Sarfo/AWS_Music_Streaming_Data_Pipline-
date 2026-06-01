resource "aws_s3_bucket" "logs" {
  bucket = local.logs_bucket
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket" "data" {
  bucket = local.data_bucket
}

resource "aws_s3_bucket_versioning" "data" {
  bucket = aws_s3_bucket.data.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "data" {
  bucket = aws_s3_bucket.data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_logging" "data" {
  bucket        = aws_s3_bucket.data.id
  target_bucket = aws_s3_bucket.logs.id
  target_prefix = "s3-access/${local.data_bucket}/"
}

resource "aws_s3_bucket_public_access_block" "data" {
  bucket                  = aws_s3_bucket.data.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_notification" "data" {
  bucket      = aws_s3_bucket.data.id
  eventbridge = true
}

resource "aws_s3_bucket_lifecycle_configuration" "data" {
  bucket = aws_s3_bucket.data.id

  rule {
    id     = "archive-to-glacier"
    status = "Enabled"

    filter {
      prefix = "archive/"
    }

    transition {
      days          = 90
      storage_class = "GLACIER_IR"
    }

    expiration {
      days = 2555
    }
  }

  rule {
    id     = "rejected-cleanup"
    status = "Enabled"

    filter {
      prefix = "rejected/"
    }

    expiration {
      days = 30
    }
  }
}

resource "aws_s3_object" "zones" {
  for_each = toset([
    "raw/streams/",
    "raw/songs/",
    "raw/users/",
    "processed/kpis/",
    "archive/streams/",
    "rejected/streams/",
    "glue-scripts/",
    "glue-temp/",
  ])

  bucket  = aws_s3_bucket.data.id
  key     = each.value
  content = ""
}
