---
title: Welcome to QueryCanary 🐤
---

QueryCanary is a lightweight, SQL-powered monitoring tool that helps you catch silent data failures in production databases — before they impact customers or downstream systems.

It was built to proactively alert you to real problems, either from issues you may suspect exist or most importantly things that have bitten you before.

Additionally, it can be used to keep track of values over time and even provide simple dashboards for your data. 


## Why QueryCanary?

- Your site has uptime monitoring.  
- Your servers have performance metrics.  
- Your companies software projects have unit tests. 
- But your **data** is silently breaking — and no one knows until it’s too late.

QueryCanary helps you recognize that by letting you:

- Define SQL-based data integrity checks
- Schedule them to run automatically
- Get alerts when results drift from expectations


## What It's Great For

- Detecting sudden drops in daily signups
- Catching null values where they shouldn’t be
- Monitoring counts, duplicates, or invalid joins
- Tracking expected combinations (e.g., `status + type`)
- Alerting on stale data that hasn't updated recently

## How It Works
### 1. Connect your database
We currently support [Postgres](/docs/servers/postgresql/) / [MySQL](/docs/servers/mysql/) + [SSH tunneling](/docs/servers/ssh-tunnel/). Our Quickstart will walk you through setting up a read only user. 

More database engines will be introduced as requested, if you need one, please email support@querycanary.com

### 2. Write a SQL check
We'll connect to your database and inspect the schema to provide you a editor to build & test a SQL check. The query results can return all sorts of data and we'll figure out good ways to analyze your results. 

Currently, single value metrics will give you solid out of the box features like charting, anomaly detection, thresholds, and more. Multiple column, or row based results will fall back to simpler checks like structure change.

Example:

```sql
-- Count all users created yesterday

SELECT COUNT(*) 
FROM users 
WHERE created_at >= CURRENT_DATE - INTERVAL '1 day';

-- Tricks like this ensure you are looking at full data
-- pictures instead of partial days.
```

###	3. Set a schedule
QueryCanary supports a full crontab syntax, so you can customize check intervals to pretty much anything you can imagine. 

### 4. Get alerted
When QueryCanary detects a change in your data, it'll send you or your team an email alert.

## Types of Checks
Currently QueryCanary smartly determines the right kind of checks applicable to the type, periodicity, and shape of your data. 

### Anomaly Detection 
Detects anomalies in numerical sequences using statistical methods.
Checks Performed:
* **Z-Score Analysis**: Calculates the z-score of the latest value compared to historical values. Triggers an alert if the z-score exceeds a specified threshold.
* **Baseline Statistics**: Uses the mean and standard deviation of historical values to establish a baseline for comparison.
* **Insufficient Data**: Skips anomaly detection if there are not enough historical values to calculate meaningful statistics.

### Percent Change 
Calculates the percentage change between numeric values. Triggers an alert if the percentage change exceeds a specified threshold. 

### Value change
Triggered by significant differences in values, types, or structures

* **List Comparison**: Compares the length of lists and triggers an alert if the length changes significantly. Detects changes from an empty list to a populated list or vice versa.
* **String Similarity**: Uses Levenshtein distance to calculate the similarity between strings. Triggers an alert if the similarity drops below a specified threshold.
* **Structural Change**: Compares the number of rows and column names in the result. Detects if the structure of the data (e.g., column names or row count) has changed between runs.


## Built for Safety
- Read-only access recommended
- SSL by default
- [SSH Tunnel](/docs/ssh-tunnel/) available
- Credentials are encrypted at rest
- No raw data is stored — only your SQL and summarized results

## Example Use Cases

These SQL checks can be used to monitor common business-critical data integrity conditions. Each includes:

- Business purpose
- What it catches
- SQL example

**1. Daily user signups dropped unexpectedly**

**Purpose:** Alert if new users fell below expected volume  
**Catches:** Failed signup flow, low traffic, frontend bugs

```sql
SELECT COUNT(*) FROM users
WHERE created_at >= CURRENT_DATE - INTERVAL '1 day';
```

**2. Listings with no price**

**Purpose:** Detect active listings without pricing  
**Catches:** Incomplete inventory, pricing bugs

```sql
SELECT COUNT(*) FROM listings
WHERE price IS NULL AND status = 'active';
```

**3. Orders created without associated users**

**Purpose:** Catch data integrity issues or bad joins  
**Catches:** Orphaned records from deleted users or import bugs

```sql
SELECT COUNT(*) FROM orders o
LEFT JOIN users u ON u.id = o.user_id
WHERE u.id IS NULL;
```

**4. Too many password reset requests**

**Purpose:** Monitor for spikes in account recovery traffic  
**Catches:** Spam attacks or broken login flows

```sql
SELECT COUNT(*) FROM password_resets
WHERE requested_at >= NOW() - INTERVAL '1 hour';
```

**5. Revenue total is lower than expected**

**Purpose:** Alert if revenue is abnormally low  
**Catches:** Payment failures or low sales volume

```sql
SELECT SUM(amount) FROM transactions
WHERE created_at >= CURRENT_DATE;
```

**6. Too many failed login attempts**

**Purpose:** Detect potential brute-force attempts  
**Catches:** Security threats or broken auth logic

```sql
SELECT COUNT(*) FROM login_attempts
WHERE success = false AND attempted_at >= NOW() - INTERVAL '10 minutes';
```

**7. Missing shipping addresses for shipped orders**

**Purpose:** Catch orders missing fulfillment info  
**Catches:** Bugs in order processing or database sync

```sql
SELECT COUNT(*) FROM orders
WHERE status = 'shipped' AND shipping_address_id IS NULL;
```

**8. Duplicate user emails**

**Purpose:** Ensure uniqueness of key identity field  
**Catches:** App logic bugs, import issues

```sql
SELECT email, COUNT(*) FROM users
GROUP BY email
HAVING COUNT(*) > 1;
```

**9. Inactive users with active subscriptions**

**Purpose:** Find billing mismatches  
**Catches:** Revenue leakage or status bugs

```sql
SELECT COUNT(*) FROM subscriptions s
JOIN users u ON u.id = s.user_id
WHERE u.status = 'inactive' AND s.status = 'active';
```

**10. Stale product catalog**

**Purpose:** Alert when products haven’t been updated  
**Catches:** ETL issues, scraper failure, stale cache

```sql
SELECT MAX(updated_at) FROM products;
```

**11. Customer records missing required fields**

**Purpose:** Validate completeness of customer data  
**Catches:** Form bugs, missing data from third-party sources

```sql
SELECT COUNT(*) FROM customers
WHERE email IS NULL OR country IS NULL;
```

**12. Unusually low inventory**

**Purpose:** Track low-stock products before they go out  
**Catches:** Stocking issues, demand spikes

```sql
SELECT COUNT(*) FROM products
WHERE stock_quantity < 5;
```


## Who It’s For
- Devs who know SQL
- Data engineers and analysts
- SaaS teams tired of finding broken dashboards after it’s too late
- CTOs with disparate teams constantly launching features

## Get Started

- [Quickstart](https://querycanary.com/quickstart)

Need help? support@querycanary.com or join our [Discord](https://discord.gg/Y6UMkgWXue)