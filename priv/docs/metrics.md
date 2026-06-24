# Metrics

SQL-powered metrics execute a query on a configured Server and store a single numeric value for a time range.

Contract:
- Your SQL may accept $1 = from_ts and $2 = to_ts (PostgreSQL) or ? parameters (MySQL). If you don't use params, the SQL runs as-is.
- The first column of the first row is taken as the metric value.

Scheduling:
- Metrics default to a `0 8 * * *` schedule. An Oban Cron plugin enqueues MetricRunner jobs every minute.
- Granularity controls the base execution window (minute/hour/day/week/month).
- Reports sum stored metric values into the selected timeline bucket.

Backfill:
- Backfill can enqueue multiple MetricRunner jobs across historical ranges (future work).
