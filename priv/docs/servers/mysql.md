---
title: Using MySQL with QueryCanary
slug: mysql
---
QueryCanary fully supports MySQL for production data monitoring. This guide walks you through connecting your database, writing SQL checks, and troubleshooting common issues.

## Overview

QueryCanary connects directly to your MySQL database — with or without SSH tunneling — and allows you to define SQL checks to monitor important conditions in your data (e.g. low signups, null prices, broken joins).

You can:

- Run scheduled SQL queries on your prod database
- Set expectations or anomaly detection on results
- Receive alerts via email or Slack when something looks off

## Requirements

- MySQL or MariaDB
- A read-only database user
- Access via direct TCP or through an SSH tunnel

We recommend connecting to a replica or using a read-only role for safety.

## Setup

### 1. Create a Read-Only User

In your MySQL server, create a dedicated read-only user, grant it SELECT access to the database you want to monitor, and flush privileges to apply changes.

```sql
-- 1. Create a dedicated read-only user
CREATE USER 'querycanary_reader'@'%' IDENTIFIED BY 'your_secure_password';

-- 2. Grant read-only access to the database you want to monitor
GRANT SELECT ON your_database.* TO 'querycanary_reader'@'%';

-- 3. Flush privileges to apply changes
FLUSH PRIVILEGES;
```

## Connecting to MySQL

### Option 1: Direct Connection

Use this if your database is publicly accessible or hosted on a service like RDS, PlanetScale, or DigitalOcean.

You’ll need:

- Hostname (for example, db.example.com)
- Port (usually 3306)
- Database name
- Username and password

### Option 2: SSH Tunnel (Recommended for Private Networks)

Use this if your database is in a private VPC and only accessible from a bastion host.

You’ll additionally need:

- Bastion host (hostname or IP)
- SSH username
- SSH public key (we generate one for you securely)

QueryCanary connects via SSH, opens a secure tunnel, and connects to your internal MySQL instance.

## Writing SQL Checks

You can monitor anything you can query. For example, you might check the number of daily signups by counting users created in the last day, or look for broken joins by counting orders without a matching user.

**Daily Signups Check**
```sql
SELECT COUNT(*) FROM users WHERE created_at >= CURDATE() - INTERVAL 1 DAY;
```

**Broken Joins Check**
```sql
SELECT COUNT(*) FROM orders o LEFT JOIN users u ON u.id = o.user_id WHERE u.id IS NULL;
```

## Troubleshooting

If you can't connect to the database, make sure the hostname and port are reachable, the user has SELECT permissions, and no VPN or firewall blocks our IP.  
If the SSH tunnel fails, ensure your bastion host is reachable, the provided public key is added to authorized keys on the bastion, and the bastion user can access the database internally.  
If a query fails or returns empty, test your query locally with the MySQL CLI or your app first. Avoid using LIMIT, ORDER BY, or formatting functions — QueryCanary only needs values. Use COUNT, SUM, AVG, or conditional expressions to track value changes.
