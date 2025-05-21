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

  def render(%{live_action: :security} = assigns) do
    ~H"""
    <section class="max-w-3xl mx-auto p-6 space-y-6 prose">
      <h2 class="text-2xl font-bold">Security</h2>
      <p>Effective: May 2025</p>

      <p>
        QueryCanary was built with the assumption that we're connecting to your most sensitive systems: your production databases.
        Here's how we take that responsibility seriously.
      </p>

      <h3>1. Credential Handling</h3>
      <ul>
        <li>
          All database and SSH credentials are encrypted at rest using strong symmetric encryption (AES-256).
        </li>
        <li>
          We never store plaintext credentials. Decryption keys are stored separately and only used at runtime.
        </li>
        <li>Credentials can be rotated or deleted at any time via the dashboard.</li>
      </ul>

      <h3>2. Infrastructure</h3>
      <ul>
        <li>
          Our application is hosted on <strong>Fly.io</strong>, which provides per-app isolation and encrypted networking.
        </li>
        <li>
          All communication between QueryCanary and your databases is attempted over secure channels (SSH tunnels or SSL).
        </li>
      </ul>

      <h3>3. Data Access</h3>
      <ul>
        <li>We store only the results of the checks you define (e.g. “rows with null price: 12”).</li>
        <li>We never copy, persist, or index the information not returned by your SQL queries.</li>
        <li>
          Access to infrastructure and database connections is tightly restricted to the owner of the service.
        </li>
      </ul>

      <h3>4. Customer Responsibility</h3>
      <ul>
        <li>You should use read-only users when providing access to QueryCanary.</li>
        <li>
          You should provide scoped down permission sets for QueryCanary, with ideally only access to the specific data you want to query.
        </li>
        <li>
          We recommend restricting access to non-sensitive schemas and using network controls (VPN, firewalls, bastion hosts).
        </li>
        <li>You can delete or rotate any credential at any time with immediate effect.</li>
      </ul>

      <h3>5. Incident Response</h3>
      <ul>
        <li>
          In the event of a security incident, we will notify affected customers promptly with an assessment and recommended actions.
        </li>
        <li>
          We maintain internal monitoring, alerting, and audit logs to detect unauthorized access or behavior.
        </li>
      </ul>

      <h3>6. Third-Party Services</h3>
      <p>
        We rely on trusted infrastructure providers with their own strong security practices, including:
      </p>
      <ul>
        <li>Fly.io — App hosting and isolated containers</li>
        <li>SendGrid — Email alert delivery</li>
        <li>Stripe — Payment processing</li>
      </ul>

      <h3>7. Questions?</h3>
      <p>Need a copy of our architecture, access controls, or responsible disclosure policy?</p>
      <p>Email us at <a href="mailto:support@querycanary.com">support@querycanary.com</a>.</p>
    </section>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(:page_title, page_title(socket.assigns.live_action))}
  end

  defp page_title(:terms), do: "Terms of Service"
  defp page_title(:privacy), do: "Privacy Policy"
  defp page_title(:security), do: "Security"
end
