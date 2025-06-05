---
title: Catching Signup Bugs Early
description: How QueryCanary helped a customer catch a subtle signup bug before it impacted growth, using anomaly detection on daily signups.
---


Even with strong test coverage, it’s easy to miss edge cases that have real-world impact. You can validate flows in staging, cover common paths with automated tests, and still end up with production issues that slip through unnoticed — especially when nothing technically breaks.

One of the most common (and costly) examples is a broken signup experience. If something silently reduces your conversion rate — a button doesn’t work, a required field never submits — you might not realize it until someone manually checks a dashboard, or worse, a few weeks pass and growth just “feels slow.”

This exact scenario recently played out with one of QueryCanary’s early users. A UI update unintentionally caused the signup flow for mobile users to render at half its normal size while being technically usable. There were no errors, no alerts, and the drop was just subtle enough to escape attention.

But their QueryCanary check caught it.

---

## Pint-sized Form

![Comparison picture showing the intended signup modal & the signup modal with the bug. The bug is that the signup modal is around half it's normal width.](/images/blog/2025-06-03-catching-signup-bugs-early/bug.jpg "Signup bug")
*Illustrative mockup showing the intended signup modal & the signup modal with the bug.*

The customer uses a traditional signup modal to allow users to authorize, and while the site doesn't require registration it's firmly encouraged to get the most out of the site. User conversion is a core metric tracked by the customer, however only at larger week / month long scales. 

The signup modal was changed to introduce a new content section explaining the benefits of signing up. While this feature worked as intended and the flow was approved by the QA team, it had a unintentional size impact on some mobile devices.

---

## The Little Dipper

![Chart showing check results for the number of signups for the day, the same information is provided below in a table.](/images/blog/2025-06-03-catching-signup-bugs-early/chart.jpg "QueryCanary Check Result Chart")

| Date       | New Signups |
|------------|-------------|
| 2025-05-05 | 342         |
| 2025-05-06 | 339         |
| 2025-05-07 | 313         |
| 2025-05-08 | 302         |
| 2025-05-09 | 337         |
| 2025-05-10 | 300         |
| 2025-05-11 | 308         |
| 2025-05-12 | 346         |
| 2025-05-13 | 349         |
| 2025-05-14 | 293         |
| 2025-05-15 | 320         |
| 2025-05-16 | 337         |
| 2025-05-17 | 208         |

When the signups dropped, QueryCanary immediately flagged the anomaly. The team received an alert and was able to quickly correlate the dip with the recent UI change. Because the check was running daily, the issue was caught within 24 hours—long before it could have a significant impact on growth or revenue.

Instead of waiting for a quarterly review or a hunch from a team member, the anomaly surfaced automatically. The team rolled back the problematic change, restoring the signup flow and preventing further loss.


---

## A Simple Check

The customer had defined a simple SQL check in QueryCanary:

```sql
SELECT COUNT(*) FROM users
WHERE created_at >= CURRENT_DATE - INTERVAL '1 day';
```

This check is useful to monitor the average daily conversion of the site, and is likely something you already track. However with QueryCanary, we monitor data as frequent as you want and use advanced models to determine if any of your data points look strange. 

In the case of the results above, our Anomaly Detection Algorithm had a good understanding for the "usual" number of signups by day and immediately warned the user when that number dropped outside of the normal range.

QueryCanary uniquely performs checks specific to the shape of data you are tracking: numeric anomaly detection, percent change detection, sudden value change (string, list, boolean, etc), and even structural changes.

![Anomaly results show in an image form.](/images/blog/2025-06-03-catching-signup-bugs-early/anomaly.jpg "QueryCanary Anomaly Check")

---

## Key Takeaways

- There were no app errors.
- Dashboards didn’t update until it was too late.
- No one thought to check — until it became a bigger problem.

But a simple check, powered by SQL and run on a schedule, turned that whisper of drift into a clear signal.

---


If you rely on user-generated data or metrics to run your product, don’t wait for dashboards to break or PMs to notice a drop.

Connect your database. Add a check. Start tracking normal, and get smartly alerted when something breaks.

QueryCanary helps you do that — with just a SQL query.

👉 [Start monitoring your production data with QueryCanary](https://querycanary.com)