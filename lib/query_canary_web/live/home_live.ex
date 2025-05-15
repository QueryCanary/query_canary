defmodule QueryCanaryWeb.HomeLive do
  use QueryCanaryWeb, :live_view

  def render(assigns) do
    ~H"""
    <div class="container mx-auto max-w-4xl">
      <section class="hero py-12 bg-base-200">
        <div class="hero-content text-center">
          <div class="max-w-xl">
            <h1 class="text-4xl font-bold">SQL-Powered Data Monitoring</h1>
            <p class="py-4 text-lg">
              Define automated SQL checks against your production database. Get alerts when the data looks wrong.
            </p>
            <a href="/quickstart" class="btn btn-primary">Start Monitoring Now</a>
          </div>
        </div>
      </section>

      <section id="features" class="container mx-auto py-20">
        <div class="grid md:grid-cols-2 gap-10">
          <div class="card bg-base-100 shadow-xl">
            <div class="card-body">
              <h2 class="card-title">Define Checks with SQL</h2>
              <pre class="bg-neutral text-neutral-content p-4 rounded">
    SELECT COUNT(*)
    FROM users
    WHERE created_at > NOW() - interval '1 day';</pre>
              <p>Track daily events, missing data, or invalid records using your own SQL queries.</p>
            </div>
          </div>

          <div class="card bg-base-100 shadow-xl">
            <div class="card-body">
              <h2 class="card-title">Automated Scheduling</h2>
              <p>Run checks every 5 minutes, hourly, or on a cron-like schedule.</p>
            </div>
          </div>

          <div class="card bg-base-100 shadow-xl">
            <div class="card-body">
              <h2 class="card-title">Visualize Results</h2>
              <canvas id="checkChart" class="w-full h-64"></canvas>
              <p class="mt-2">Spot anomalies and understand trends over time.</p>
            </div>
          </div>

          <div class="card bg-base-100 shadow-xl">
            <div class="card-body">
              <h2 class="card-title">Instant Alerts</h2>
              <p>
                Receive Slack, email, or PagerDuty notifications when checks fail or change behavior.
              </p>
              <div class="alert alert-warning mt-4">
                <span>⚠️ User registrations dropped 60% today.</span>
              </div>
              <div class="alert alert-success mt-2">
                <span>✅ All checks passed on last run.</span>
              </div>
            </div>
          </div>
        </div>
      </section>

      <section id="pricing" class="container mx-auto py-20 text-center">
        <h2 class="text-4xl font-bold mb-10">Simple Pricing</h2>
        <div class="grid grid-cols-1 md:grid-cols-3 gap-10">
          <div class="card bg-base-100 shadow-xl">
            <div class="card-body items-center text-center">
              <h3 class="card-title">Free</h3>
              <p class="text-4xl font-bold">$0</p>
              <p>Up to 5 checks<br />1 database<br />Email alerts</p>
              <div class="card-actions mt-4">
                <a href="/quickstart" class="btn btn-outline">Get Started</a>
              </div>
            </div>
          </div>

          <div class="card bg-primary text-primary-content shadow-xl">
            <div class="card-body items-center text-center">
              <h3 class="card-title">Pro</h3>
              <p class="text-4xl font-bold">$49/mo</p>
              <p>Up to 100 checks<br />Multiple databases<br />Slack + Email alerts</p>
              <div class="card-actions mt-4">
                <button class="btn btn-accent">Choose Plan</button>
              </div>
            </div>
          </div>

          <div class="card bg-base-100 shadow-xl">
            <div class="card-body items-center text-center">
              <h3 class="card-title">Enterprise</h3>
              <p class="text-4xl font-bold">Custom</p>
              <p>Unlimited checks<br />SSO + Audit Logs<br />Priority support</p>
              <div class="card-actions mt-4">
                <button class="btn btn-outline">Contact Us</button>
              </div>
            </div>
          </div>
        </div>
      </section>

      <section id="cta" class="hero bg-primary text-primary-content py-16">
        <div class="hero-content text-center">
          <div class="max-w-xl">
            <h2 class="text-4xl font-bold mb-4">Start Monitoring in Minutes</h2>
            <p class="mb-6">
              Setup your first check, connect your database, and get alerted when something goes wrong.
            </p>
            <a href="/quickstart" class="btn btn-accent btn-lg">Get Started for Free</a>
          </div>
        </div>
      </section>
    </div>

    <script>
      const ctx = document.getElementById('checkChart').getContext('2d');
      new Chart(ctx, {
        type: 'line',
        data: {
          labels: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
          datasets: [{
            label: 'User Registrations',
            data: [124, 130, 98, 102, 180, 90, 76],
            borderColor: 'rgb(59, 130, 246)',
            backgroundColor: 'rgba(59, 130, 246, 0.2)',
            fill: true,
            tension: 0.4,
          }]
        },
        options: {
          responsive: true,
          scales: {
            y: {
              beginAtZero: true
            }
          }
        }
      });
    </script>
    """
  end
end
