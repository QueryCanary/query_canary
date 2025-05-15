defmodule QueryCanaryWeb.HomeLive do
  use QueryCanaryWeb, :live_view

  def render(assigns) do
    ~H"""
    <div class="container mx-auto max-w-4xl">
      <section class="hero py-12 bg-base-200 rounded-xl">
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
    WHERE DATE(date_joined) = CURRENT_DATE - INTERVAL '1 day';</pre>
              <p>Track daily events, missing data, or invalid records using your own SQL queries.</p>
            </div>
          </div>

          <div class="card bg-base-100 shadow-xl">
            <div class="card-body">
              <h2 class="card-title">Automated Scheduling</h2>
              <p>Run checks every on any cron-like schedule.</p>
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
                Receive email or Slack notifications when checks fail or change behavior.
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
      <section class="py-16 px-6 max-w-5xl mx-auto text-center space-y-8">
        <h2 class="text-4xl font-bold">Simple Pricing</h2>
        <p class="text-lg opacity-70">Simple, flat pricing, with no surprises.</p>

        <div class="grid md:grid-cols-2 gap-6 items-stretch mt-10">
          <div class="card border border-base-300 shadow-md">
            <div class="card-body items-center text-center">
              <h3 class="card-title text-2xl">Free</h3>
              <p class="text-sm opacity-70 mb-4">For testing and side projects</p>
              <p class="text-4xl font-bold mb-4">$0</p>

              <ul class="space-y-2 text-sm">
                <li>✔ 10 checks</li>
                <li>✔ 1 database connection</li>
                <li>✔ Daily frequency</li>
                <li>✔ Email alerts</li>
                <li>✔ 30-day rolling history</li>
              </ul>

              <div class="card-actions mt-6">
                <button class="btn btn-outline btn-primary">Start Free</button>
              </div>
            </div>
          </div>

          <div class="card border border-primary shadow-md">
            <div class="card-body items-center text-center">
              <h3 class="card-title text-2xl text-primary">Paid</h3>
              <p class="text-sm opacity-70 mb-4">Everything you need for production</p>
              <p class="text-4xl font-bold mb-4">$10<span class="text-base font-normal">/mo</span></p>

              <ul class="space-y-2 text-sm">
                <li>✔ 100 checks</li>
                <li>✔ 10 database connections</li>
                <li>✔ Every minute scheduling</li>
                <li>✔ Email + Slack alerts</li>
                <li>✔ 365-day rolling history</li>
                <li>✔ Team members</li>
              </ul>

              <div class="card-actions mt-6">
                <button class="btn btn-primary">Upgrade Now</button>
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
          let good = "#00d390";
          let warning = "#fcb700";
          let data = [124, 130, 98, 102, 180, 90, 45];
          new Chart(ctx, {
            type: 'line',
            data: {
              labels: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
              datasets: [
                {
                  label: 'User Registrations',
                  data: data,
                  borderColor: 'rgb(59, 130, 246)',
                  backgroundColor: 'rgba(59, 130, 246, 0.2)',
                  fill: true,
                  tension: 0.4,
                },
                {
                  label: "% Change from Avg",
                  data: [-9, -3, -26, -22, 33, -29, -60],
                  type: "bar",
                  backgroundColor: [good, good, good, good, good, good, warning],
                  yAxisID: 'y1',
                }
              ]
            },
            options: {
              responsive: true,
              scales: {
                y: {
                  beginAtZero: true
                },

                  y1: {
                    type: 'linear',
                    position: 'right',
                    min: -100,
                    max: 100,
                    grid: { drawOnChartArea: false },
                    title: { display: true, text: 'Moving Average' },
                  }
              }
            }
          });

          let avg = rollingAverage([135, 120, 110, 140, 160, 150, 124, 130, 98, 102, 180, 90, 72]);
          console.log(avg.forEach((el, index) => console.log(percIncrease(el, data[index]))))

        function rollingAverage(arr) {
        const windowSize = 7;

        const result = [];

        for (let i = 0; i <= arr.length - windowSize; i++) {
        const window = arr.slice(i, i + windowSize);
        const avg = window.reduce((sum, num) => sum + num, 0) / windowSize;
        result.push(Math.ceil(avg));
        }

        return result;
        }
        function percIncrease(a, b) {
          let percent;
          if(b !== 0) {
              if(a !== 0) {
                  percent = (b - a) / a * 100;
              } else {
                  percent = b * 100;
              }
          } else {
              percent = - a * 100;
          }
          return Math.floor(percent);
      }
    </script>
    """
  end
end
