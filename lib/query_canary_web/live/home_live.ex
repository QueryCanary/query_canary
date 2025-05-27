defmodule QueryCanaryWeb.HomeLive do
  use QueryCanaryWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "SQL Data Monitoring and Alerting")
     |> assign(:custom_meta, %{
       title: "QueryCanary: SQL Data Monitoring and Alerting",
       description:
         "Define automated SQL checks against your production database and get proactive alerts when the data starts to look wrong.",
       image_url: url(~p"/images/querycanary-social.png")
     })}
  end

  def render(assigns) do
    ~H"""
    <div class="container mx-auto max-w-4xl space-y-4 md:space-y-16">
      <section class="hero py-12 bg-base-200 rounded-xl">
        <div class="hero-content text-center">
          <div class="max-w-xl">
            <h1 class="text-4xl font-bold">
              Your data is silently breaking.
            </h1>
            <p class="py-4 text-lg">
              You define SQL checks against your production database. We monitor the results, detect anomalies, and alert you when something breaks.
            </p>
            <.link navigate={~p"/quickstart"} class="btn btn-primary">Start Monitoring Now</.link>
          </div>
        </div>
      </section>

      <p class="text-center italic text-2xl font-light">
        Your servers have uptime monitors. Your data should too.
      </p>

      <section id="features" class="container mx-auto">
        <div class="grid md:grid-cols-2 gap-10">
          <div class="card bg-base-100 shadow-md">
            <div class="card-body">
              <h2 class="card-title">Define Checks with SQL</h2>
              <pre class="bg-neutral text-neutral-content p-4 rounded font-mono">
    <span class="text-emerald-400">--- Select the full count of</span>
    <span class="text-emerald-400">--- users from yesterday</span>
    <span class="text-info">SELECT</span> <span class="text-warning">COUNT</span>(*)
    <span class="text-info">FROM</span> <span class="text-secondary">users</span>
    <span class="text-info">WHERE</span> <span class="text-warning">DATE</span>(<span class="text-secondary">date_joined</span>) =
    <span class="text-warning">CURRENT_DATE</span> - <span class="text-warning">INTERVAL</span> <span class="text-success">'1 day'</span>;</pre>
              <p>Track daily events, missing data, or invalid records using your own SQL queries.</p>
              <.button navigate={~p"/checks/7"} variant="info">View Example Check</.button>
            </div>
          </div>

          <div class="card bg-base-100 shadow-md">
            <div class="card-body">
              <h2 class="card-title">Automated Scheduling</h2>
              <div class="bg-neutral text-neutral-content p-4 rounded">
                <div class="flex items-center space-x-2 mb-3">
                  <span class="badge badge-success">Active</span>
                  <span class="font-semibold">New User Check</span>
                </div>
                <div class="grid grid-cols-2 gap-3 text-sm">
                  <div class="flex items-center">
                    <svg
                      xmlns="http://www.w3.org/2000/svg"
                      class="h-5 w-5 mr-2 opacity-70"
                      fill="none"
                      viewBox="0 0 24 24"
                      stroke="currentColor"
                    >
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        stroke-width="2"
                        d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"
                      />
                    </svg>
                    <span>8AM UTC</span>
                  </div>
                  <div class="flex items-center">
                    <svg
                      xmlns="http://www.w3.org/2000/svg"
                      class="h-5 w-5 mr-2 opacity-70"
                      fill="none"
                      viewBox="0 0 24 24"
                      stroke="currentColor"
                    >
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        stroke-width="2"
                        d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z"
                      />
                    </svg>
                    <span>Every day</span>
                  </div>
                  <div class="flex items-center">
                    <svg
                      xmlns="http://www.w3.org/2000/svg"
                      class="h-5 w-5 mr-2 opacity-70"
                      fill="none"
                      viewBox="0 0 24 24"
                      stroke="currentColor"
                    >
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        stroke-width="2"
                        d="M7 21h10a2 2 0 002-2V9.414a1 1 0 00-.293-.707l-5.414-5.414A1 1 0 0012.586 3H7a2 2 0 00-2 2v14a2 2 0 002 2z"
                      />
                    </svg>
                    <span>Last run: 2 min ago</span>
                  </div>
                  <div class="flex items-center">
                    <svg
                      xmlns="http://www.w3.org/2000/svg"
                      class="h-5 w-5 mr-2 opacity-70"
                      fill="none"
                      viewBox="0 0 24 24"
                      stroke="currentColor"
                    >
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        stroke-width="2"
                        d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z"
                      />
                    </svg>
                    <span>543 runs total</span>
                  </div>
                </div>
                <div class="mt-3 pt-3 border-t border-neutral-700 flex justify-between items-center">
                  <div class="text-xs opacity-70">Custom cron: <code>0 8 * * *</code></div>
                  <div class="flex space-x-1">
                    <span class="badge badge-xs badge-success">✓ 539</span>
                    <span class="badge badge-xs badge-error">✗ 4</span>
                  </div>
                </div>
              </div>
              <p class="mt-2">
                Schedule checks to run from every minute to once a month, with custom cron expressions for advanced needs.
              </p>
            </div>
          </div>

          <div class="card bg-base-100 shadow-md">
            <div class="card-body">
              <h2 class="card-title">Visualize Results</h2>
              <canvas id="home-chart" phx-hook="HomeChart" class="w-full h-64"></canvas>
              <p class="mt-2">Spot anomalies and understand trends over time.</p>
            </div>
          </div>

          <div class="card bg-base-100 shadow-md">
            <div class="card-body flex justify-between">
              <h2 class="card-title">Instant Alerts</h2>
              <div class="flex flex-col gap-2">
                <div class="alert alert-warning">
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    class="stroke-current shrink-0 h-6 w-6"
                    fill="none"
                    viewBox="0 0 24 24"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"
                    />
                  </svg>
                  <div>
                    <div class="font-medium">User registrations dropped 60% today</div>
                    <div class="text-xs opacity-70">Sun, May 16 at 8:00 AM</div>
                  </div>
                </div>
                <div class="alert alert-success">
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    class="stroke-current shrink-0 h-6 w-6"
                    fill="none"
                    viewBox="0 0 24 24"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"
                    />
                  </svg>
                  <div>
                    <div class="font-medium">All checks passed on last run</div>
                    <div class="text-xs opacity-70">Sat, May 15 at 8:00 AM</div>
                  </div>
                </div>
              </div>
              <div>
                <p>
                  Get notified through multiple channels when checks detect anomalies in your data.
                </p>
              </div>
            </div>
          </div>
        </div>
      </section>
      <section class="px-6 max-w-5xl mx-auto text-center space-y-2">
        <h2 class="text-4xl font-bold">Simple Pricing</h2>
        <p class="text-lg opacity-70">Straightforward plans with everything you need</p>

        <div class="grid md:grid-cols-2 gap-8 items-stretch mt-10">
          <div class="card border border-base-300 shadow-md transition-all hover:shadow-lg">
            <div class="card-body items-center text-center">
              <h3 class="card-title text-2xl">Personal</h3>
              <p class="text-sm opacity-70 mb-4">For testing and side projects</p>
              <p class="text-4xl font-bold mb-4">$0</p>

              <ul class="space-y-3 text-sm w-full">
                <li class="flex items-center">
                  <.green_check /> 10 checks
                </li>
                <li class="flex items-center">
                  <.green_check /> 1 database connection
                </li>
                <li class="flex items-center">
                  <.green_check /> Daily frequency
                </li>
                <li class="flex items-center">
                  <.green_check /> Email alerts
                </li>
                <li class="flex items-center">
                  <.green_check /> 30-day rolling history
                </li>
              </ul>

              <div class="card-actions mt-6">
                <.link navigate={~p"/quickstart"} class="btn btn-outline btn-primary">
                  Start Free
                </.link>
              </div>
            </div>
          </div>

          <div class="card border-2 border-primary shadow-md relative transition-all hover:shadow-lg">
            <%!-- <div class="absolute -top-4 left-0 right-0 mx-auto w-fit px-4 py-1 bg-primary text-primary-content text-sm font-medium rounded-full">
              Coming Soon!
            </div> --%>
            <div class="card-body items-center text-center">
              <h3 class="card-title text-2xl text-primary">Team</h3>
              <p class="text-sm opacity-70 mb-4">Everything you need for production</p>
              <p class="text-4xl font-bold mb-4">$15<span class="text-base font-normal">/mo</span></p>

              <ul class="space-y-3 text-sm w-full">
                <li class="flex items-center">
                  <.green_check />
                  <span class="font-medium">100 checks</span>
                </li>
                <li class="flex items-center">
                  <.green_check />
                  <span class="font-medium">10 database connections</span>
                </li>
                <li class="flex items-center">
                  <.green_check />
                  <span class="font-medium">Every minute scheduling</span>
                </li>
                <li class="flex items-center">
                  <.green_check />
                  <span class="font-medium">Email + Slack alerts</span>
                </li>
                <li class="flex items-center">
                  <.green_check />
                  <span class="font-medium">365-day rolling history</span>
                </li>
                <li class="flex items-center">
                  <.green_check />
                  <span class="font-medium">Team members</span>
                </li>
              </ul>

              <div class="card-actions mt-6">
                <.link navigate={~p"/teams"} class="btn btn-primary">Upgrade Now</.link>
              </div>
            </div>
          </div>
        </div>
      </section>

      <p class="text-center italic text-2xl font-light">
        Catch broken data before it shows up on your customer reports.
      </p>

      <section id="cta" class="hero bg-primary text-primary-content py-16 rounded-xl">
        <div class="hero-content text-center">
          <div class="max-w-xl">
            <h2 class="text-4xl font-bold mb-4">Start Monitoring in Minutes</h2>
            <p class="mb-6">
              No credit card required. Connect your database and create your first check in under 5 minutes.
            </p>
            <.link navigate={~p"/quickstart"} class="btn btn-accent btn-lg">
              Get Started for Free
            </.link>
          </div>
        </div>
      </section>
    </div>
    """
  end

  defp green_check(assigns) do
    ~H"""
    <svg class="w-5 h-5 mr-2 text-success" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"></path>
    </svg>
    """
  end
end
