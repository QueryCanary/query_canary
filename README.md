# QueryCanary
QueryCanary is a lightweight tool for monitoring your production data using SQL. Define checks using real queries, run them on a schedule, and get alerted when something looks wrong.

[QueryCanary.com](https://querycanary.com/)

---

## What It Does

- ✅ Run SQL checks against your production database
- ✅ Schedule checks using flexible cron expressions
- ✅ Get alerts via email or Slack when values drift or break
- ✅ See historical trends and chart results over time
- ✅ Catch issues like:
  - Low signups
  - Missing prices
  - Invalid data combinations
  - Broken joins

## Local Development

### 1. Clone the repo
```bash
git clone https://github.com/QueryCanary/query_canary.git
cd query_canary
```

### 2. Install dependencies
```bash
mix setup
```

### 3. Run server
```bash
mix phx.server
```

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://hexdocs.pm/phoenix/overview.html
* Docs: https://hexdocs.pm/phoenix
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix
