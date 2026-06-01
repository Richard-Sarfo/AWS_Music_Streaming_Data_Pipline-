"""Compute daily genre KPIs and top-genre rankings from a validated streams batch.

Inputs:
  --input_s3   s3://.../raw/streams/<file>.csv
  --songs_s3   s3://.../raw/songs/songs.csv
  --output_s3  s3://.../processed/kpis/run=<execution_name>

Outputs JSONL under output_s3:
  genre_kpis/    per (genre, date) with listen_count, unique_listeners,
                 total_listen_seconds, avg_listen_seconds_per_user, top3_songs
  top5_genres/   per (date, rank) with genre and listen_count

Total listening time is computed as sum of songs.duration_ms per play,
converted to seconds (streams.csv has no per-play duration of its own).
"""

import sys

from awsglue.utils import getResolvedOptions
from pyspark.sql import SparkSession, Window
from pyspark.sql import functions as F

args = getResolvedOptions(
    sys.argv, ["input_s3", "songs_s3", "output_s3"]
)

spark = (
    SparkSession.builder.appName("p1-transform-kpis").getOrCreate()
)

streams = (
    spark.read.option("header", True)
    .option("escape", "\"")
    .csv(args["input_s3"])
    .withColumn("listen_time", F.to_timestamp("listen_time"))
    .withColumn("date", F.to_date("listen_time"))
)

songs = (
    spark.read.option("header", True)
    .option("escape", "\"")
    .csv(args["songs_s3"])
    .select(
        F.col("track_id"),
        F.col("track_name"),
        F.col("track_genre").alias("genre"),
        F.col("duration_ms").cast("long").alias("duration_ms"),
    )
)

joined = streams.join(F.broadcast(songs), "track_id", "inner")

per_track = (
    joined.groupBy("genre", "date", "track_id", "track_name")
    .agg(F.count("*").alias("plays"))
)

per_genre = (
    joined.groupBy("genre", "date")
    .agg(
        F.count("*").alias("listen_count"),
        F.countDistinct("user_id").alias("unique_listeners"),
        (F.sum("duration_ms") / 1000).alias("total_listen_seconds"),
    )
    .withColumn(
        "avg_listen_seconds_per_user",
        F.col("total_listen_seconds") / F.col("unique_listeners"),
    )
)

top3_window = Window.partitionBy("genre", "date").orderBy(F.col("plays").desc())
top3 = (
    per_track
    .withColumn("rk", F.row_number().over(top3_window))
    .filter(F.col("rk") <= 3)
    .groupBy("genre", "date")
    .agg(
        F.collect_list(
            F.struct("track_id", "track_name", "plays")
        ).alias("top3_songs")
    )
)

genre_kpis = per_genre.join(top3, ["genre", "date"], "left")

top5_window = Window.partitionBy("date").orderBy(F.col("listen_count").desc())
top5_genres = (
    per_genre
    .withColumn("rank", F.row_number().over(top5_window))
    .filter(F.col("rank") <= 5)
    .select("date", "rank", "genre", "listen_count")
)

output_base = args["output_s3"].rstrip("/")

(
    genre_kpis.coalesce(1)
    .write.mode("overwrite")
    .json(f"{output_base}/genre_kpis/")
)

(
    top5_genres.coalesce(1)
    .write.mode("overwrite")
    .json(f"{output_base}/top5_genres/")
)

print("OK")
