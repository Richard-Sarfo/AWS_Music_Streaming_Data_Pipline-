data "aws_caller_identity" "me" {}

locals {
  account_id  = data.aws_caller_identity.me.account_id
  name_prefix = "${var.project}-${var.env}"
  data_bucket = "${local.name_prefix}-data-${local.account_id}"
  logs_bucket = "${local.name_prefix}-logs-${local.account_id}"
  scripts_key = "glue-scripts"

  tags = {
    Project = var.project
    Env     = var.env
    Owner   = "richard.sarfo"
  }
}
