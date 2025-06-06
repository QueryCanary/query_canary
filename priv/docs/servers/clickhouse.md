---
title: Using ClickHouse with QueryCanary
---
QueryCanary fully supports ClickHouse for production data monitoring. This guide walks you through connecting your database, writing SQL checks, and troubleshooting common issues.

## Overview

QueryCanary connects directly to your ClickHouse database — with or without SSH tunneling — and allows you to define SQL checks to monitor important conditions in your data (e.g. low signups, null prices, broken joins).

You can:

- Run scheduled SQL queries on your ClickHouse database
- Set expectations or anomaly detection on results
- Receive alerts via email or Slack when something looks off

## Requirements

- ClickHouse server (cloud or self-hosted)
- A user with read-only access
- Access via HTTP or HTTPS protocol (TCP)
- (Optional) SSH tunnel for private networks

We recommend connecting with a user that has only the necessary permissions for safety.

## Setup

### 1. Create a Read-Only User

In your ClickHouse server, create a user with read-only access. For example:

```sql
CREATE USER querycanary_reader IDENTIFIED WITH plaintext_password BY 'your_secure_password';
GRANT SELECT ON your_database.* TO querycanary_reader;
```

> For managed ClickHouse services, follow your provider's instructions for creating users and granting permissions.

> You can also configure the user inside the configuration of a self-hosted ClickHouse server.

## Connecting to ClickHouse

### Option 1: Direct Connection

Use this if your ClickHouse server is accessible via HTTP or native TCP (8123/9000), including cloud services like ClickHouse Cloud.

You’ll need:

- Hostname (e.g. ch.example.com)
- Port (usually 8123 for HTTP)
- Database name
- Username & password

### Option 2: SSH Tunnel (Recommended for Private Networks)

Use this if your ClickHouse server is only accessible from a bastion host.

You’ll additionally need:

- Bastion host (hostname/IP)
- SSH username
- SSH public key (we generate one for you securely)

QueryCanary connects via SSH, opens a secure tunnel, and connects to your internal ClickHouse instance.

## Writing SQL Checks

You can monitor anything you can query. For example:

**Daily Events Check**
```sql
SELECT count(*) FROM events WHERE event_date = today();
```

**Broken Joins Check**
```sql
SELECT count(*) FROM orders o LEFT JOIN users u ON o.user_id = u.id WHERE u.id IS NULL;
```

## Troubleshooting

**Can't connect to database**
- Make sure the hostname and port are reachable
- Check that the user has SELECT permissions
- Confirm no VPN/firewall blocks our IP (contact support if needed)

**SSH tunnel fails**
- Make sure your bastion host is reachable
- Add the provided public key to ~/.ssh/authorized_keys on the bastion
- Check that the bastion user can access the database internally

**Query fails or returns empty**
- Test your query locally with clickhouse-client or your app first
- Avoid LIMIT, ORDER BY, or formatting functions — we only need values
- Use COUNT, SUM, AVG, or conditional expressions to track value changes