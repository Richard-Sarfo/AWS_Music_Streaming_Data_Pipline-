"""Validate an incoming streams CSV before the transform stage runs.

Reads the file from S3 (passed in as --input_s3), checks that the required
columns are present, enforces a null-rate ceiling on the key fields, and
exits non-zero on any violation so Step Functions can route the file to
the rejected/ prefix and notify via SNS.
"""

import csv
import io
import json
import sys
from urllib.parse import urlparse

import boto3
from awsglue.utils import getResolvedOptions

REQUIRED_COLUMNS = {"user_id", "track_id", "listen_time"}
NULL_RATE_THRESHOLD = 0.05

args = getResolvedOptions(sys.argv, ["input_s3"])

s3 = boto3.client("s3")
parsed = urlparse(args["input_s3"])
bucket = parsed.netloc
key = parsed.path.lstrip("/")

obj = s3.get_object(Bucket=bucket, Key=key)
body = obj["Body"].read().decode("utf-8", errors="replace")

reader = csv.reader(io.StringIO(body))
header = [col.strip() for col in next(reader)]

missing = REQUIRED_COLUMNS - set(header)
if missing:
    raise SystemExit(
        f"VALIDATION_FAILED: missing required columns {sorted(missing)} in {args['input_s3']}"
    )

col_index = {col: header.index(col) for col in REQUIRED_COLUMNS}
rows = 0
nulls = 0
for row in reader:
    rows += 1
    if (
        not row[col_index["user_id"]]
        or not row[col_index["track_id"]]
        or not row[col_index["listen_time"]]
    ):
        nulls += 1

if rows == 0:
    raise SystemExit(f"VALIDATION_FAILED: empty file {args['input_s3']}")

null_rate = nulls / rows
if null_rate > NULL_RATE_THRESHOLD:
    raise SystemExit(
        f"VALIDATION_FAILED: null rate {nulls}/{rows} ({null_rate:.2%}) exceeds "
        f"threshold {NULL_RATE_THRESHOLD:.0%} in {args['input_s3']}"
    )

print(json.dumps({
    "status": "ok",
    "input": args["input_s3"],
    "rows": rows,
    "nulls": nulls,
    "null_rate": round(null_rate, 4),
}))
