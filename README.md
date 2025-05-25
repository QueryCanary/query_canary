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

### Contributing
1. [Fork it!](https://github.com/QueryCanary/query_canary/fork)
2. Create your feature branch (`git checkout -b feature/my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin feature/my-new-feature`)
5. Create new Pull Request


## Testing
QueryCanary includes a comprehensive and very fast test suite, so you should be encouraged to run tests as frequently as possible.

```sh
mix test
```

Any broken tests will be called out with the file and line number. If you are working on a single test, or a single test file you can easily specify a smaller test sample with:

```sh
mix test test/query_canary/your_test.exs
# Or specifying a specific line
mix test test/query_canary/your_test.exs:15
```

## Help
If you need help with the product, email us at [support@querycanary.com](mailto:support@querycanary.com).
If you need help with developing the software, please feel free to open [a GitHub Issue](https://github.com/QueryCanary/query_canary/issues/new).

## License
QueryCanary is licensed under the [AGPL-3.0 license](LICENSE.md).