defmodule QueryCanary.Checks.CheckNotifier do
  import Swoosh.Email
  require Logger

  alias QueryCanary.Mailer
  alias QueryCanary.Checks.{Check, CheckResult}
  alias QueryCanary.Accounts.User

  @support_email "support@querycanary.com"
  # Brand colors
  # Yellow brand color
  @brand_primary "#fbc700"
  # Dark color for text on yellow background
  @brand_dark "#333333"

  @doc """
  Delivers an alert notification when a check generates an alert.

  ## Parameters
    * user - The user who owns the check
    * check - The check that triggered the alert
    * check_result - The check result with the alert
    * url - URL to the check details page
  """
  def deliver_check_alert_notification(
        %User{} = user,
        %Check{} = check,
        %CheckResult{} = check_result,
        url
      ) do
    if check_result.is_alert do
      email =
        new()
        |> to(user.email)
        |> from({"QueryCanary Alerts", "alerts@querycanary.com"})
        |> reply_to({"QueryCanary Support", @support_email})
        |> subject("⚠️ Alert: #{check.name} - #{alert_type_title(check_result.alert_type)}")
        |> html_body(check_alert_html(user, check, check_result, url))
        |> text_body(check_alert_text(user, check, check_result, url))

      # |> attachment(logo_attachment())

      case Mailer.deliver(email) do
        {:ok, _metadata} ->
          Logger.info("Sent alert email for check #{check.id} to #{user.email}")
          {:ok, email}

        {:error, reason} ->
          Logger.error("Failed to send alert email for check #{check.id}: #{inspect(reason)}")
          {:error, reason}
      end
    else
      Logger.debug("Skipping email for non-alert check result #{check_result.id}")
      {:ok, :no_alert}
    end
  end

  # Add logo as embedded attachment
  defp logo_attachment do
    path = Application.app_dir(:query_canary, "priv/static/images/QueryCanary.svg")

    Swoosh.Attachment.new(path,
      type: "image/svg+xml",
      type: :inline,
      filename: "QueryCanary.svg",
      cid: "logo@querycanary"
    )
  end

  # HTML template for check alert emails
  defp check_alert_html(user, check, check_result, url) do
    """
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>QueryCanary Alert: #{check.name}</title>
      <style>
        body {
          font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
          line-height: 1.5;
          color: #374151;
          background-color: #f9fafb;
          margin: 0;
          padding: 0;
        }
        .container {
          max-width: 600px;
          margin: 0 auto;
          padding: 20px;
        }
        .logo {
          display: block;
          margin: 0 auto 10px;
          width: 54px;
          height: auto;
        }
        .header {
          background-color: #{@brand_primary};
          color: #{@brand_dark};
          padding: 20px;
          border-radius: 8px 8px 0 0;
          display: grid;
          grid-template-columns: repeat(4, 1fr);
          gap: 10px;
        }
        .header .header-left {
          grid-area: 1 / 1 / 2 / 2;
          text-align: center;
        }
        .header .header-right {
          text-align: left;
          grid-area: 1 / 2 / 2 / 5;
        }
        .header h1 {
          margin: 0;
          font-size: 24px;
          font-weight: 600;
        }
        .header p {
          margin: 5px 0 0;
          opacity: 0.8;
        }
        .content {
          background-color: white;
          padding: 20px;
          border-radius: 0 0 8px 8px;
          box-shadow: 0 2px 4px rgba(0, 0, 0, 0.05);
        }
        .alert-container {
          margin: 20px 0;
          padding: 15px;
          border-radius: 8px;
          border-left: 4px solid #ef4444;
          background-color: #fee2e2;
        }
        .alert-anomaly {
          border-color: #eab308;
          background-color: #fef9c3;
        }
        .alert-diff {
          border-color: #3b82f6;
          background-color: #dbeafe;
        }
        .alert-heading {
          display: flex;
          align-items: center;
          gap: 8px;
          margin-bottom: 10px;
        }
        .alert-heading h2 {
          margin: 0;
          font-size: 18px;
          font-weight: 600;
          color: #111827;
        }
        .alert-summary {
          margin-bottom: 15px;
        }
        .comparison-grid {
          display: grid;
          grid-template-columns: 1fr 1fr;
          gap: 10px;
          margin-top: 15px;
        }
        .comparison-item {
          padding: 10px;
          background-color: #f3f4f6;
          border-radius: 6px;
        }
        .comparison-label {
          font-size: 12px;
          font-weight: 600;
          margin-bottom: 5px;
          color: #4b5563;
        }
        .comparison-value {
          font-family: monospace;
          font-size: 14px;
          word-break: break-all;
        }
        .anomaly-stats {
          display: grid;
          grid-template-columns: 1fr 1fr 1fr;
          gap: 10px;
          margin-top: 15px;
        }
        .stat-item {
          padding: 10px;
          background-color: #f3f4f6;
          border-radius: 6px;
          text-align: center;
        }
        .stat-label {
          font-size: 12px;
          font-weight: 600;
          color: #4b5563;
        }
        .stat-value {
          font-size: 16px;
          font-weight: 600;
          margin-top: 5px;
        }
        .footer {
          margin-top: 20px;
          text-align: center;
          font-size: 13px;
          color: #6b7280;
        }
        .button {
          display: inline-block;
          background-color: #{@brand_primary};
          color: #{@brand_dark};
          text-decoration: none;
          padding: 12px 24px;
          border-radius: 6px;
          font-weight: 600;
          margin-top: 15px;
          transition: all 0.2s;
          box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);
        }
        .button:hover {
          background-color: #{darken(@brand_primary)};
        }
        .view-check-container {
          text-align: center;
          margin: 25px 0 15px;
        }
      </style>
    </head>
    <body>
      <div class="container">
        <div class="header">
          <div class="header-left">
            <img src="https://querycanary.com/images/QueryCanary.svg" alt="QueryCanary Logo" class="logo" />
          </div>
          <div class="header-right">
            <h1>Alert Notification</h1>
            <p>#{format_datetime(check_result.inserted_at)}</p>
          </div>
        </div>

        <div class="content">
          <p>Hi #{user_greeting(user)},</p>

          <p>Your check <strong>#{check.name}</strong> has detected an issue:</p>

          <div class="alert-container #{alert_type_class(check_result.alert_type)}">
            <div class="alert-heading">
              <h2>#{alert_type_title(check_result.alert_type)}</h2>
            </div>

            <div class="alert-summary">
              #{check_result.analysis_summary || "An issue was detected with your data."}
            </div>

            #{render_alert_details(check_result)}
          </div>

          <p>You can view more details and the complete check history by clicking the button below:</p>

          <div class="view-check-container">
            <a href="#{url}" class="button">View Check Details</a>
          </div>

          <div class="footer">
            <p>This is an automated message from QueryCanary. If you have any questions, please contact us at #{@support_email}.</p>
            <p>© #{current_year()} QueryCanary. All rights reserved.</p>
          </div>
        </div>
      </div>
    </body>
    </html>
    """
  end

  # Text template for check alert emails (fallback for email clients that don't support HTML)
  defp check_alert_text(user, check, check_result, url) do
    """
    QueryCanary Alert: #{check.name}
    ==============================

    Hi #{user_greeting(user)},

    Your check "#{check.name}" has detected an issue:

    #{alert_type_title(check_result.alert_type)} (#{format_datetime(check_result.inserted_at)})
    #{check_result.analysis_summary || "An issue was detected with your data."}

    #{text_alert_details(check_result)}

    View full details: #{url}

    ==============================
    This is an automated message from QueryCanary.
    If you have any questions, please contact us at #{@support_email}.
    """
  end

  # Helper to render alert details based on the alert type (HTML version)
  defp render_alert_details(%{alert_type: :diff, analysis_details: details})
       when is_map(details) do
    """
    <div class="comparison-grid">
      <div class="comparison-item">
        <div class="comparison-label">Previous Value:</div>
        <div class="comparison-value">#{format_value(details.previous_value)}</div>
      </div>
      <div class="comparison-item">
        <div class="comparison-label">Current Value:</div>
        <div class="comparison-value">#{format_value(details.current_value)}</div>
      </div>
    </div>
    """
  end

  defp render_alert_details(%{alert_type: :anomaly, analysis_details: details})
       when is_map(details) do
    """
    <div class="anomaly-stats">
      <div class="stat-item">
        <div class="stat-label">Current Value</div>
        <div class="stat-value">#{format_number(details.current_value)}</div>
      </div>
      <div class="stat-item">
        <div class="stat-label">Expected Range</div>
        <div class="stat-value">
          #{format_number(details.mean - details.std_dev)} -
          #{format_number(details.mean + details.std_dev)}
        </div>
      </div>
      <div class="stat-item">
        <div class="stat-label">Z-Score</div>
        <div class="stat-value">#{format_number(details.z_score)}</div>
      </div>
    </div>
    """
  end

  defp render_alert_details(_) do
    ""
  end

  # Helper to render alert details based on the alert type (text version)
  defp text_alert_details(%{alert_type: :diff, analysis_details: details}) when is_map(details) do
    """
    Previous Value: #{format_value(details.previous_value)}
    Current Value: #{format_value(details.current_value)}
    """
  end

  defp text_alert_details(%{alert_type: :anomaly, analysis_details: details})
       when is_map(details) do
    """
    Current Value: #{format_number(details.current_value)}
    Expected Range: #{format_number(details.mean - details.std_dev)} - #{format_number(details.mean + details.std_dev)}
    Z-Score: #{format_number(details.z_score)}
    """
  end

  defp text_alert_details(_) do
    ""
  end

  # Helper functions
  # defp user_greeting(%User{name: name}) when is_binary(name) and name != "", do: name
  defp user_greeting(%User{email: email}), do: email

  defp alert_type_class(:anomaly), do: "alert-anomaly"
  defp alert_type_class(:diff), do: "alert-diff"
  defp alert_type_class(_), do: ""

  defp alert_type_title(:anomaly), do: "Anomaly Detected"
  defp alert_type_title(:diff), do: "Significant Change Detected"
  defp alert_type_title(:failure), do: "Check Failed"
  defp alert_type_title(_), do: "Alert"

  defp format_value(value) when is_binary(value), do: value
  defp format_value(value) when is_number(value), do: "#{value}"
  defp format_value(nil), do: "N/A"
  defp format_value(value), do: inspect(value)

  defp format_number(nil), do: "N/A"
  defp format_number(num) when is_float(num), do: :erlang.float_to_binary(num, decimals: 2)
  defp format_number(num), do: to_string(num)

  defp format_datetime(%DateTime{} = dt) do
    Calendar.strftime(dt, "%B %d, %Y at %H:%M:%S UTC")
  end

  defp format_datetime(_), do: "N/A"

  defp current_year do
    DateTime.utc_now().year
  end

  # Calculate a darker version of a color for hover states
  defp darken(hex_color) do
    # Simple implementation - could be more sophisticated
    # This just makes the color about 10% darker
    "#e6b300"
  end
end
