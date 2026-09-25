# QueryCanary
QueryCanary is a lightweight tool for monitoring your production data using SQL. Define checks using real queries, run them on a schedule, and get alerted when something looks wrong.

[QueryCanary.com](https://querycanary.com/)

---

## What It Does

- ✅ Run SQL checks against your production database
- ✅ Schedule checks with simple choices, local times, or custom cron expressions
- ✅ Get alerts via email or Slack when values drift or break
- ✅ See historical trends and chart results over time
- ✅ Build custom reports that group metrics from multiple data sources
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
Install Node.js 22+ alongside Elixir; notification charts use the same Chart.js
renderer as the browser. `mix setup` installs the npm dependencies as well.
```bash
mix setup
```

### 3. Run server
```bash
mix phx.server
```

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

## Slack alerts

Run `mix ecto.migrate`, then create a Slack app using
[`priv/slack-app-manifest.json`](priv/slack-app-manifest.json). Set the app's OAuth
redirect URL to `https://YOUR_HOST/integrations/slack/callback` and configure
`SLACK_CLIENT_ID` and `SLACK_CLIENT_SECRET` on QueryCanary. The callback uses the
Phoenix endpoint's public URL (`PHX_HOST` in production); use an HTTPS development
tunnel and matching endpoint URL for local OAuth testing. Enable Slack app
distribution to allow customers to install it in their own workspaces.

The bot needs `chat:write`, `channels:read`, `groups:read`, and `files:write`. This implementation
uses workspace bot tokens with token rotation disabled, as in the manifest.
See Slack's [OAuth installation guide](https://docs.slack.dev/authentication/installing-with-oauth/).

A team admin connects Slack from the team page. Invite the QueryCanary bot into
the desired public or private channels, then select a channel under **Alert
notifications** when creating or editing each check. Each check can choose a
different channel and independently toggle **Email notifications** and **Slack
notifications**. Both default to enabled to preserve existing behavior; Slack
also requires a connected workspace and a selected channel. Turning Slack off
keeps its channel selection. Turning both off leaves the check running and
recording results. Email recipients and alert conditions remain unchanged;
Slack receives one message per check result, rather than one per team member.
Personal checks must use a team-owned server to configure chat delivery.

Slack messages include the applicable analysis details (previous/current values,
percentage change, expected range and z-score, status, or structure) and a PNG of
the last 48 runs through the alert. Email alerts include the same PNG inline
for each recipient; if chart rendering fails, the alert still sends with its
details and check link. The check page, Slack, and email share
`Checks.ChartData` and `assets/js/charts/check_chart.mjs`, including the same
Chart.js version, curved series, alert colors, average, anomaly thresholds, axes,
and legend. The snapshot freezes at the triggering run; later runs only change
the live page. Failed runs leave gaps in each chart.

Images render locally with Node.js and `@napi-rs/canvas`. The notification chart is
960×280px with a 5px white border on each side, exported at double resolution
(1940×580px); the live chart remains 256px tall. Animation and interaction are
disabled for the image. Development
and tests read the shared JavaScript source directly. `mix assets.build` and
`mix assets.deploy` package the renderer and native canvas dependencies into the
release. Docker includes Node and Liberation Sans; other deployments need Node
22+ and a system font such as Arial or Liberation Sans. Install npm dependencies
with `npm ci --prefix assets` before running tests independently of `mix setup`.

Images use Slack's private file upload flow and an image block in the alert,
without a publicly accessible chart endpoint or third-party chart service.
For an existing Slack app, add `files:write` to its bot scopes (or update its
manifest), then reconnect from the team page to approve the new permission.
Channel selections are preserved. Older installations still receive the detailed
text alert with a reconnect hint. If rendering or upload fails, the alert still
sends with its details and check link; image upload errors are logged.
Slack may accept an upload before its image is ready to embed. Explicit image
rejections retry the same uploaded file after 1, 2, and 4 seconds, then fall back
to the detailed alert without the image. Ambiguous message failures still use
the normal Oban retry policy; they are not immediately reposted.

Connections are unique per team/provider. Tokens are encrypted using the endpoint
secret, consistent with existing database credentials; preserve `SECRET_KEY_BASE`
across deployments. Reconnecting the same workspace refreshes the token and keeps
channel selections. Connecting a different workspace or disconnecting removes
those selections. Disconnecting removes QueryCanary's local connection; it does
not uninstall the Slack app from a workspace that other teams may use.

Delivery runs on the Oban `notifications` queue, with up to 10 attempts for temporary
failures and `Retry-After` handling for rate limits. Revoked tokens and inaccessible
channels cancel delivery; reconnect or update the channel before future alerts.
Pending deliveries recheck the check's current notification preference and cancel
if that provider is turned off. They also cancel when their destination is removed
or the server no longer belongs to that team. Jobs contain only destination and result IDs.
Duplicate enqueues are suppressed while their Oban job remains stored. Delivery
is at least once: a timeout after Slack accepts a message can still cause a duplicate.
Inspect failed/cancelled jobs through the existing admin Oban dashboard.

For Discord or Teams, implement `QueryCanary.Notifications.Provider`, register the
adapter in `Notifications.providers/0`, and add its connection flow. The shared
connection/destination tables, channel settings, alert payload, and delivery worker
already support multiple providers; email delivery stays independent.

## Admin dashboards

Phoenix LiveDashboard (`/admin/dashboard`) and Oban Web (`/admin/oban`) are available
in every environment to logged-in users with `users.is_admin` set to `true`.
Team admin roles do not grant site admin access.

Run `mix ecto.migrate` when upgrading. Existing and new users are non-admins by
default. To grant access, use a trusted IEx console (`iex -S mix`, or a remote
console for a running release):

```elixir
QueryCanary.Accounts.get_user_by_email("admin@example.com")
|> Ecto.Changeset.change(is_admin: true)
|> QueryCanary.Repo.update!()
```

Use `is_admin: false` to revoke access. The flag cannot be changed through
registration or account settings.

## Contributing
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
