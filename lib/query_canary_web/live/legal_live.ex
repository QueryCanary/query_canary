defmodule QueryCanaryWeb.LegalLive do
  use QueryCanaryWeb, :live_view

  @impl true
  def render(%{live_action: :terms} = assigns) do
    ~H"""
    <section class="max-w-3xl mx-auto p-6 space-y-6 prose">
      <h2 class="text-2xl font-bold">Terms of Service</h2>

      <p>Effective: May 2025</p>

      <p>
        QueryCanary is a service that helps you run SQL-based data checks against your databases and receive alerts when something breaks. By using QueryCanary, you agree to these terms.
      </p>

      <h3>1. What We Do</h3>
      <p>
        We provide tools to monitor data health by running your custom SQL checks on a schedule. We store the results (e.g., counts, status) but never the raw data rows.
      </p>

      <h3>2. Your Responsibilities</h3>
      <ul>
        <li>You must have authorization to connect to and query any databases you provide.</li>
        <li>You’re responsible for the SQL you write and the results it generates.</li>
        <li>You must not use our service for abuse, scanning, or violating the rights of others.</li>
      </ul>

      <h3>3. Free & Paid Usage</h3>
      <p>
        QueryCanary currently offers free, unlimited usage. When pricing plans are introduced in the future, you will be notified and given an opportunity to upgrade.
      </p>

      <h3>4. Your Data</h3>
      <ul>
        <li>We store your check definitions, run results, and alert history.</li>
        <li>
          We also retrieve and store basic metadata from your database
          (e.g., table names and column types) to help you write queries.
        </li>
        <li>Credentials are encrypted and never shared.</li>
      </ul>

      <h3>5. Availability & Changes</h3>
      <p>
        We may add, change, or remove features at any time. We will do our best to communicate changes clearly and in advance.
      </p>

      <h3>6. Termination</h3>
      <p>
        You may stop using QueryCanary at any time. We may suspend your access if you violate these terms or abuse the service.
      </p>

      <h3>7. Legal</h3>
      <p>
        This agreement is governed by the laws of the Commonwealth of Pennsylvania, United States. You agree to resolve disputes in courts located in Pennsylvania.
      </p>

      <h3>8. Limitation of Liability</h3>
      <p>
        We do our best to keep QueryCanary running reliably, but we are not responsible for any business loss, missed alerts, or data errors caused by check results, outages, or bugs.
      </p>
    </section>
    """
  end

  def render(%{live_action: :privacy} = assigns) do
    ~H"""
    <section class="max-w-3xl mx-auto p-6 space-y-6 prose">
      <h2 class="text-2xl font-bold">Privacy Policy</h2>
      <p>Effective: May 2025</p>

      <h3>1. What We Collect</h3>
      <ul>
        <li>Your email and name during signup</li>
        <li>Your check definitions, schedule, and alert preferences</li>
        <li>Check run results (e.g., status, count values)</li>
        <li>Metadata about your database structure (tables and columns only)</li>
        <li>Basic logs and performance metrics</li>
      </ul>

      <h3>2. What We Don’t Collect</h3>
      <ul>
        <li>We do not store query result rows or full dataset snapshots</li>
        <li>We do not sell or share your data with third parties</li>
        <li>We do not collect personal data beyond what’s necessary to operate the service</li>
      </ul>

      <h3>3. Third-Party Services</h3>
      <p>
        We use trusted services like Fly.io, SendGrid, and Stripe to operate QueryCanary. Your data is handled securely in compliance with their practices.
      </p>

      <h3>4. Your Rights (GDPR / CCPA)</h3>
      <ul>
        <li>You can request a copy of your stored data</li>
        <li>You can delete your account and associated data at any time</li>
        <li>We do not discriminate based on data-related requests</li>
      </ul>

      <h3>5. Security</h3>
      <p>
        We encrypt credentials and sensitive fields. We recommend using read-only database users and IP/network controls to further protect your infrastructure.
      </p>

      <h3>6. Contact</h3>
      <p>
        Questions? Email us at <a href="mailto:support@querycanary.com">support@querycanary.com</a>
      </p>
    </section>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(:page_title, page_title(socket.assigns.live_action))}
  end

  defp page_title(:terms), do: "Terms of Service"
  defp page_title(:privacy), do: "Privacy Policy"
end
