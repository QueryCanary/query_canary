---
title: QueryCanary Now Supports ClickHouse and MySQL
slug: 2025-06-05-clickhouse-mysql-support

---

We're excited to announce that QueryCanary now supports two of the most popular database engines in modern analytics and SaaS: **ClickHouse** and **MySQL**! 🎉

## Why ClickHouse and MySQL?

Our mission is to help teams catch silent data issues before they impact your business. That means meeting you where your data lives. ClickHouse and MySQL are trusted by thousands of teams for everything from real-time analytics to core transactional workloads. Now, you can monitor, alert, and automate checks on these databases with the same power and ease you expect from QueryCanary.
 
## What Can You Do?

- **Run SQL checks** on your ClickHouse or MySQL databases, just like you do with PostgreSQL.
- **Detect anomalies** in your analytics pipelines, dashboards, or production data.
- **Get alerted** when your data drifts, breaks, or changes unexpectedly—no matter which engine you use.
- **Visualize results** and track trends over time, all in one place.

## How It Works

Just add a new database in QueryCanary, select ClickHouse or MySQL, and enter your connection details. You can start writing checks in SQL immediately—no extra setup required.

- For **ClickHouse**, we support both cloud and self-hosted deployments via the official HTTP and native protocols.
- For **MySQL**, you can connect to any version 5.7+ instance, including managed services like AWS RDS or Google Cloud SQL.

## Example: Monitoring a ClickHouse Table

```sql
SELECT count(*) FROM events WHERE event_date = today();
```

## Example: Monitoring a MySQL Table

```sql
SELECT COUNT(*) FROM users WHERE created_at >= CURDATE() - INTERVAL 1 DAY;
```

## Why This Matters

Data issues don't discriminate by database. Whether you're running a high-throughput analytics cluster or a classic transactional app, QueryCanary helps you:

- Catch silent failures and schema changes
- Detect drops or spikes in key metrics
- Alert your team before customers notice

## Get Started

Ready to try it? [Log in to QueryCanary](https://querycanary.com) and add your ClickHouse or MySQL database today. As always, setup takes just a few minutes, and you can start monitoring your most important data right away.

---

If you have questions, feedback, or want to see support for another database, let us know! We're building QueryCanary for teams like yours.

Happy monitoring! 🚦
