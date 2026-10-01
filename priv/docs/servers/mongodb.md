---
title: Using MongoDB with QueryCanary
---
QueryCanary supports MongoDB checks and metrics using JSON queries, with direct connections or SSH tunnels.

## Connect a database

Create a dedicated user with the `read` role on the database you want to monitor:

```javascript
use your_database
db.createUser({
  user: "querycanary_reader",
  pwd: "your_secure_password",
  roles: [{role: "read", db: "your_database"}]
})
```

Select **MongoDB** in Quickstart or the server form, then enter:

- **Hostname**: a MongoDB server hostname (without `mongodb://`).
- **Port**: `27017` by default.
- **Database**: the database to query.
- **Username / Password**: your monitoring user's credentials.
- **Authentication Database**: the database where the user was created. Leave blank to use Database. For Atlas users or users created in `admin`, enter `admin`.
- **TLS / SSL Mode**: disable for a local server without TLS; use `verify-full` for Atlas or a server with a trusted TLS certificate. `require` enables TLS without certificate verification. MongoDB does not negotiate TLS automatically: `allow` and `prefer` use plain TCP.

For Atlas, use an individual server hostname from the cluster's standard connection string and allow QueryCanary's IP in the network access list. The hostname field does not accept connection strings or SRV addresses. Direct connections discover replica set members; with SSH tunneling, QueryCanary connects only to the specified host through the tunnel.

## Write a check

Queries are JSON objects, using double quotes for keys and strings. JavaScript shell expressions such as `db.users.countDocuments()` are not supported.

Count matching documents (returns one row with a numeric `value`, including zero):

```json
{"count": "users", "query": {"active": true}}
```

Aggregate a numeric value:

```json
{
  "aggregate": "orders",
  "pipeline": [
    {"$match": {"status": "paid"}},
    {"$group": {"_id": null, "value": {"$sum": "$total"}}},
    {"$project": {"_id": 0, "value": 1}}
  ]
}
```

Find documents with filtering, projection, sorting and a limit:

```json
{
  "find": "orders",
  "filter": {"total": {"$gt": 100}},
  "projection": {"_id": 0, "total": 1},
  "sort": {"total": -1},
  "limit": 10
}
```

Distinct values return a row with a `value` for each match:

```json
{"distinct": "orders", "key": "status", "query": {}}
```

Supported query options include `limit`, `skip`, `sort`, `projection`, `batchSize`, `maxTimeMS`, `allowDiskUse`, `collation`, `hint` and `comment` where applicable. Aggregations also accept `cursor.batchSize`. All cursor batches are consumed. Collection fields in the saved schema are inferred from up to 100 documents per collection.

## Dates and object IDs

Use Extended JSON wrappers to query BSON types:

```json
{
  "find": "orders",
  "filter": {
    "_id": {"$oid": "507f1f77bcf86cd799439011"},
    "created_at": {"$gte": {"$date": "2025-01-01T00:00:00Z"}}
  }
}
```

`$date` accepts an ISO 8601 timestamp or integer milliseconds since the Unix epoch. `$numberDecimal` and `$numberLong` wrappers are also supported. Results convert object IDs, dates and decimals to strings for display and storage, while ordinary numeric and boolean values retain their types.

## Metrics with time windows

In a MongoDB metric query, the whole strings `"$1"` and `"$2"` are replaced with BSON dates for the beginning and end of the metric window. They are substituted as values rather than interpolated into the JSON text.

```json
{
  "count": "users",
  "query": {"created_at": {"$gte": "$1", "$lt": "$2"}}
}
```

For aggregation metrics, project a single numeric field named `value`. Empty aggregations return no rows; use a count query when a zero is required for an empty collection.
