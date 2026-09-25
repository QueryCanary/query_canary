---
title: Slack alerts
description: Connect your team's Slack workspace and choose channels for your checks.
---

Your team connects one Slack workspace, and each check can send to its own channel.
Each check has separate toggles for email and Slack notifications.

Alerts include the values that triggered the alert: previous and current values
and percentage change, or the expected range and z-score for anomalies. Status
and structure changes include their relevant details too.

Each alert includes the same **Result History** chart you see on the check page:
the same values, curves, highlighted alerts, average, and anomaly thresholds.
The image captures up to 48 runs ending at the alert, so it stays fixed as new
results arrive on the site. Failed runs leave gaps rather than being plotted as
zero. Chart images are uploaded directly to your Slack workspace.

## Connect your workspace

1. Open your team page and find **Alert integrations**.
2. As a team admin, select **Connect Slack** and approve the connection in Slack.
3. Invite the QueryCanary bot to every public or private channel that should receive alerts.

If Slack is not configured for your QueryCanary installation, contact your administrator.

## Choose a channel for a check

Create or edit a check on a server owned by your team. Under **Alert notifications**,
select a Slack channel and save. Each check has its own selection, so a billing check
can notify your finance channel while a signup check notifies your product channel.

Only channels the bot has joined appear. After inviting the bot to another channel,
reload the check settings.

## Turn notifications on or off

Use **Email notifications** and **Slack notifications** to choose email only,
Slack only, both, or neither for this check. Both toggles start enabled; Slack
also needs a selected channel. Email notifications go to active team members,
or to the owner of a personal check.

Turning Slack off preserves the selected channel for when you turn it back on.
Pending Slack deliveries check the current setting before sending. Turning both
notification types off keeps the check running and recording results.

## Manage the connection

Team admins can reconnect or disconnect Slack on the team page. Reconnecting the same
workspace keeps channel selections. Connecting a different workspace clears them;
select channels again in your checks. Disconnecting stops future Slack deliveries
and removes channel selections for the team.

If an alert asks you to reconnect to enable chart images, reconnect from the team
page and approve the file-upload permission. Your selected channels stay in place.
Alerts still arrive if Slack cannot accept the chart image; use **View check** to
open the chart in QueryCanary.

If alerts stop arriving, check that the channel still exists and the bot is still
a member. Reconnect Slack if its access was revoked. Temporary Slack failures are
retried automatically.
