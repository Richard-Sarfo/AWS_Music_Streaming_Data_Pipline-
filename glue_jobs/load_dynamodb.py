"""Load processed KPI JSONL outputs into DynamoDB.

Inputs:
  --output_s3   s3://.../processed/kpis/run=<execution_name>
  --genre_table DynamoDB table for per-genre daily KPIs
  --top_table   DynamoDB table for top-5-genres per day

Reads JSONL part files under <output_s3>/genre_kpis/ and <output_s3>/top5_genres/,
reshapes each row to the documented key schema, and writes in batches of 25 using
BatchWriteItem with overwrite-by-key semantics so re-runs are idempotent.
"""

import decimal
import json
import sys
from urllib.parse import urlparse

import boto3
from awsglue.utils import getResolvedOptions

args = getResolvedOptions(
    sys.argv, ["output_s3", "genre_table", "top_table"]
)

s3 = boto3.client("s3")
ddb = boto3.resource("dynamodb")


def iter_jsonl(s3_prefix):
    parsed = urlparse(s3_prefix)
    bucket = parsed.netloc
    prefix = parsed.path.lstrip("/")
    paginator = s3.get_paginator("list_objects_v2")
    for page in paginator.paginate(Bucket=bucket, Prefix=prefix):
        for obj in page.get("Contents", []):
            key = obj["Key"]
            if not (key.endswith(".json") or key.endswith(".jsonl") or "part-" in key):
                continue
            body = s3.get_object(Bucket=bucket, Key=key)["Body"].read().decode()
            for line in body.splitlines():
                line = line.strip()
                if line:
                    yield json.loads(line, parse_float=decimal.Decimal)


def chunked(iterable, size=25):
    buf = []
    for item in iterable:
        buf.append(item)
        if len(buf) == size:
            yield buf
            buf = []
    if buf:
        yield buf


def write_batch(table_name, items):
    table = ddb.Table(table_name)
    written = 0
    for batch in chunked(items):
        with table.batch_writer(overwrite_by_pkeys=["pk", "sk"]) as writer:
            for item in batch:
                writer.put_item(Item=item)
        written += len(batch)
    return written


def to_genre_item(row):
    return {
        "pk": f"GENRE#{row['genre']}",
        "sk": f"DATE#{row['date']}",
        "listen_count": int(row.get("listen_count") or 0),
        "unique_listeners": int(row.get("unique_listeners") or 0),
        "total_listen_seconds": decimal.Decimal(str(row.get("total_listen_seconds") or 0)),
        "avg_listen_seconds_per_user": decimal.Decimal(str(row.get("avg_listen_seconds_per_user") or 0)),
        "top3_songs": row.get("top3_songs") or [],
    }


def to_top_item(row):
    return {
        "pk": f"DATE#{row['date']}",
        "sk": f"RANK#{int(row['rank'])}",
        "genre": row["genre"],
        "listen_count": int(row["listen_count"]),
    }


base = args["output_s3"].rstrip("/")

genre_written = write_batch(
    args["genre_table"],
    (to_genre_item(row) for row in iter_jsonl(f"{base}/genre_kpis/")),
)
top_written = write_batch(
    args["top_table"],
    (to_top_item(row) for row in iter_jsonl(f"{base}/top5_genres/")),
)

print(json.dumps({
    "status": "ok",
    "genre_items_written": genre_written,
    "top_items_written": top_written,
}))
