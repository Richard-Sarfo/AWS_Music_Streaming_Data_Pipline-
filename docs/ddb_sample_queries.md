# DynamoDB Sample Queries

Downstream consumers (BI dashboards, analytics microservices, etc.) read KPIs directly from DynamoDB. The two tables and their key schemas:

| Table | Partition key (`pk`) | Sort key (`sk`) | Attributes |
| --- | --- | --- | --- |
| `p1-streaming-dev-genre-daily-kpis` | `GENRE#<genre>` | `DATE#<yyyy-mm-dd>` | `listen_count`, `unique_listeners`, `total_listen_seconds`, `avg_listen_seconds_per_user`, `top3_songs` |
| `p1-streaming-dev-top-genres-daily` | `DATE#<yyyy-mm-dd>` | `RANK#<n>` | `genre`, `listen_count` |

Both schemas keep all reads to single-partition Query or GetItem — no Scan needed.

---

## Python (boto3)

```python
import boto3
from boto3.dynamodb.conditions import Key

ddb = boto3.resource("dynamodb")

genre_table = ddb.Table("p1-streaming-dev-genre-daily-kpis")
top_table   = ddb.Table("p1-streaming-dev-top-genres-daily")
```

### 1. Daily KPIs for a single genre over time

```python
resp = genre_table.query(
    KeyConditionExpression=Key("pk").eq("GENRE#pop"),
)
for item in resp["Items"]:
    print(item["sk"], item["listen_count"], item["unique_listeners"])
```

### 2. KPIs for a single genre on a specific day

```python
resp = genre_table.get_item(
    Key={"pk": "GENRE#pop", "sk": "DATE#2024-06-25"},
)
print(resp.get("Item"))
```

### 3. Top-5 genres for a given day

```python
resp = top_table.query(
    KeyConditionExpression=Key("pk").eq("DATE#2024-06-25"),
)
for item in resp["Items"]:
    print(item["sk"], item["genre"], item["listen_count"])
```

### 4. Daily KPIs for a genre within a date range

```python
resp = genre_table.query(
    KeyConditionExpression=
        Key("pk").eq("GENRE#rock")
        & Key("sk").between("DATE#2024-06-01", "DATE#2024-06-30"),
)
```

### 5. Top-3 songs inside a genre on a given day

```python
resp = genre_table.get_item(
    Key={"pk": "GENRE#jazz", "sk": "DATE#2024-06-25"},
    ProjectionExpression="top3_songs",
)
for song in resp["Item"]["top3_songs"]:
    print(song["track_name"], song["plays"])
```

---

## AWS CLI

```bash
# Top 5 genres for a day
aws dynamodb query \
  --table-name p1-streaming-dev-top-genres-daily \
  --key-condition-expression "pk = :p" \
  --expression-attribute-values '{":p":{"S":"DATE#2024-06-25"}}'

# All days for one genre
aws dynamodb query \
  --table-name p1-streaming-dev-genre-daily-kpis \
  --key-condition-expression "pk = :p" \
  --expression-attribute-values '{":p":{"S":"GENRE#pop"}}'
```
