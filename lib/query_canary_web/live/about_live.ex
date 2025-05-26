defmodule QueryCanaryWeb.AboutLive do
  use QueryCanaryWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(:page_title, "About")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section class="max-w-3xl mx-auto px-6 py-12 space-y-8 prose prose-neutral">
      <h1 class="text-3xl font-bold">About QueryCanary</h1>

      <p>
        QueryCanary was built out of a very real problem: discovering your production data is broken… days too late.
        Whether it’s a metric that silently flatlines, signups that drop and go unnoticed, or a
        <code>NULL</code>
        where there
        shouldn’t be — the data broke, and no one knew.
      </p>

      <p>
        I built QueryCanary to give developers and data teams an early warning system for their production databases.
        It's lightweight, SQL-powered, and designed to help you define integrity checks you care about — like low signups,
        broken joins, or invalid prices — and then get alerted when things drift off course.
      </p>

      <p>
        It started as a personal tool to make sure I didn't get blindsided at work by broken analytics. Now it's
        a fully functional micro-SaaS, used in production to monitor real systems — quietly catching issues before they become
        problems.
      </p>

      <p>
        QueryCanary supports scheduled SQL checks, anomaly detection, SSH-tunneled Postgres connections, email alerts,  teams, and a simple dashboard. It’s still early, but I’m actively building, shipping,
        and listening.
      </p>

      <h2 class="text-2xl font-semibold">The Team <small class="text-xs">(of one)</small></h2>
      <div class="hero">
        <div class="hero-content flex-col lg:flex-row">
          <img src={~p"/images/luke.jpg"} class="max-w-sm rounded-lg shadow-2xl size-48 mx-6" />
          <div>
            <p>
              Hi, I’m <strong>Luke Strickland</strong>
              — software developer, carpenter, and volunteer firefighter. I’m building QueryCanary from a small town in Western Pennsylvania focused on delivering a simple product for a simple price.
            </p>

            <p>
              I’d love your feedback. If you have questions, ideas, or find bugs, email me at <a
                href="mailto:luke@querycanary.com"
                class="link link-primary"
              >luke@querycanary.com</a>.
            </p>

            <p>
              🙇 Thanks for checking out QueryCanary.
            </p>
          </div>
        </div>
      </div>
    </section>
    """
  end
end
