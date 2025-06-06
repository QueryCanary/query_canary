---
title: Using PostgreSQL with QueryCanary
---
QueryCanary fully supports PostgreSQL for production data monitoring. This guide walks you through connecting your database, writing SQL checks, and troubleshooting common issues.

## Overview

QueryCanary connects directly to your PostgreSQL database — with or without SSH tunneling — and allows you to define SQL checks to monitor important conditions in your data (e.g. low signups, null prices, broken joins). 

You can:

- Run scheduled SQL queries on your prod database
- Set expectations or anomaly detection on results
- Receive alerts via email or Slack when something looks off

## Requirements

- PostgreSQL version 10 or higher
- A read-only database user
- Access via direct TCP or through an SSH tunnel

We recommend connecting to a replica or using a read-only role for safety.

## Setup

### 1. Create a Read-Only User

In your Postgres server:

```sql
-- 1. Create a dedicated read-only user
CREATE USER querycanary_reader WITH PASSWORD 'your_secure_password';

-- 2. Allow it to connect to your database
GRANT CONNECT ON DATABASE your_database TO querycanary_reader;

-- 3. Grant usage on the schema you want to monitor (typically public)
GRANT USAGE ON SCHEMA public TO querycanary_reader;

-- 4. Grant read-only access to all existing tables
GRANT SELECT ON ALL TABLES IN SCHEMA public TO querycanary_reader;

-- 5. Ensure access to future tables too
ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT SELECT ON TABLES TO querycanary_reader;
```

## Connecting to Postgres

### Option 1: Direct Connection

Use this if your database is publicly accessible or hosted on a service like RDS, Supabase, or Fly.io.

You’ll need:

- Hostname (e.g. db.example.com)
- Port (usually 5432)
- Database name
- Username & password

### Option 2: SSH Tunnel (Recommended for Private Networks)

Use this if your DB is in a private VPC and only accessible from a bastion host.

You’ll additionally need:

- Bastion host (hostname/IP)
- SSH username
- SSH public key (we generate one for you securely)

QueryCanary connects via SSH, opens a secure tunnel, and connects to your internal Postgres instance.

## Writing SQL Checks

You can monitor anything you can query. Example:

**Daily Signups Check**

```sql
SELECT COUNT(*) FROM users WHERE created_at >= CURRENT_DATE - INTERVAL '1 day';
```

**Broken Joins Check**

```sql
SELECT COUNT(*) FROM orders o LEFT JOIN users u ON u.id = o.user_id WHERE u.id IS NULL;
```

## Troubleshooting

**Can't connect to database**

- Make sure the hostname and port are reachable
- Check that the user has CONNECT and SELECT permissions
- Confirm no VPN/firewall blocks our IP (contact support if needed)

**SSH tunnel fails**

- Make sure your bastion host is reachable
- Add the provided public key to ~/.ssh/authorized_keys on the bastion
- Check that the bastion user can access the database internally

**Query fails or returns empty**

- Test your query locally with psql or your app first
- Avoid LIMIT, ORDER BY, or formatting functions — we only need values
- Use COUNT, SUM, AVG, or conditional expressions to track value changes
