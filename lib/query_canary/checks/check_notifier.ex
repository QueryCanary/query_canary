defmodule QueryCanary.Checks.CheckNotifier do
  import Swoosh.Email
  require Logger

  alias QueryCanary.Mailer
  alias QueryCanary.Checks.{Check, CheckResult}
  alias QueryCanary.Accounts.User
  alias QueryCanary.Notifications.Chart

  @support_email "support@querycanary.com"
  # Brand colors
  @brand_primary "#fbc700"
  @brand_dark "#333333"

  @doc """
  Delivers an alert notification when a check generates an alert.

  ## Parameters
    * user - The user who owns the check
    * check - The check that triggered the alert
    * check_result - The check result with the alert
    * url - URL to the check details page
    * chart - Optional pre-rendered chart shared by all email recipients
  """
  def deliver_check_alert_notification(
        %User{} = user,
        %Check{} = check,
        %CheckResult{} = check_result,
        url,
        chart \\ :render
      ) do
    if check_result.is_alert and QueryCanary.Notifications.enabled?(check, "email") do
      chart =
        if chart == :render,
          do: Chart.render(check, QueryCanary.Checks.get_results_through(check_result)),
          else: chart

      chart_cid = if chart, do: chart.filename

      email =
        new()
        |> to(user.email)
        |> from({"QueryCanary Alerts", "alerts@querycanary.com"})
        |> reply_to({"QueryCanary Support", @support_email})
        |> subject("⚠️ Alert: #{check.name} - #{alert_type_title(check_result.alert_type)}")
        |> html_body(check_alert_html(user, check, check_result, url, chart, chart_cid))
        |> text_body(check_alert_text(user, check, check_result, url))
        |> attach_chart(chart, chart_cid)

      case Mailer.deliver(email) do
        {:ok, _metadata} ->
          Logger.info("Sent alert email for check #{check.id} to #{user.email}")
          {:ok, email}

        {:error, reason} ->
          Logger.error("Failed to send alert email for check #{check.id}: #{inspect(reason)}")
          {:error, reason}
      end
    else
      Logger.debug("Skipping email notification for check result #{check_result.id}")
      {:ok, if(check_result.is_alert, do: :notifications_disabled, else: :no_alert)}
    end
  end

  # HTML template for check alert emails
  defp check_alert_html(user, check, check_result, url, chart, chart_cid) do
    """
    <!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
    <html xmlns="http://www.w3.org/1999/xhtml">
    <head>
      <meta http-equiv="Content-Type" content="text/html; charset=UTF-8" />
      <meta name="viewport" content="width=device-width, initial-scale=1.0" />
      <title>QueryCanary Alert: #{check.name}</title>
    </head>
    <body style="margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; line-height: 1.5; color: #374151; background-color: #f9fafb;">
      <table border="0" cellpadding="0" cellspacing="0" width="100%">
        <tr>
          <td>
            <table align="center" border="0" cellpadding="0" cellspacing="0" width="600" style="border-collapse: collapse;">
              <!-- Header -->
              <tr>
                <td bgcolor="#{@brand_primary}" style="padding: 20px; border-radius: 8px 8px 0 0;">
                  <table border="0" cellpadding="0" cellspacing="0" width="100%">
                    <tr>
                      <td width="80" align="center" valign="top">
                        <img src="https://querycanary.com/images/querycanary-email.png" alt="QueryCanary Logo" width="54" style="display: block;" />
                      </td>
                      <td style="color: #{@brand_dark}; padding-left: 15px;">
                        <h1 style="margin: 0; font-size: 24px; font-weight: 600;">Alert Notification</h1>
                        <p style="margin: 5px 0 0; opacity: 0.8;">#{format_datetime(check_result.inserted_at)}</p>
                      </td>
                    </tr>
                  </table>
                </td>
              </tr>

              <!-- Content -->
              <tr>
                <td bgcolor="#ffffff" style="padding: 20px; border-radius: 0 0 8px 8px; box-shadow: 0 2px 4px rgba(0, 0, 0, 0.05);">
                  <table border="0" cellpadding="0" cellspacing="0" width="100%">
                    <tr>
                      <td>
                        <p style="margin-top: 0;">Hi #{user_greeting(user)},</p>
                        <p>Your check <strong>#{check.name}</strong> has detected an issue:</p>
                      </td>
                    </tr>

                    <!-- Alert Container -->
                    <tr>
                      <td style="padding: 15px; border-radius: 8px; border-left: 4px solid #{alert_type_border_color(check_result.alert_type)}; background-color: #{alert_type_bg_color(check_result.alert_type)}; margin: 20px 0;">
                        <table border="0" cellpadding="0" cellspacing="0" width="100%">
                          <tr>
                            <td>
                              <h2 style="margin: 0 0 10px 0; font-size: 18px; font-weight: 600; color: #111827;">#{alert_type_title(check_result.alert_type)}</h2>
                              <p style="margin-bottom: 15px;">#{check_result.analysis_summary || "An issue was detected with your data."}</p>

                              #{render_alert_details_table(check_result)}
                            </td>
                          </tr>
                        </table>
                      </td>
                    </tr>

                    #{chart_html(chart, chart_cid)}

                    <tr>
                      <td style="padding-top: 20px;">
                        <p>You can view more details and the complete check history by clicking the button below:</p>
                      </td>
                    </tr>

                    <!-- Button -->
                    <tr>
                      <td align="center" style="padding: 25px 0 15px 0;">
                        <table border="0" cellpadding="0" cellspacing="0">
                          <tr>
                            <td bgcolor="#{@brand_primary}" style="border-radius: 6px; box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);">
                              <a href="#{url}" target="_blank" style="display: inline-block; padding: 12px 24px; font-weight: 600; color: #{@brand_dark}; text-decoration: none;">View Check Details</a>
                            </td>
                          </tr>
                        </table>
                      </td>
                    </tr>

                    <!-- Footer -->
                    <tr>
                      <td style="padding-top: 20px; text-align: center; font-size: 13px; color: #6b7280;">
                        <p>This is an automated message from QueryCanary. If you have any questions, please contact us at #{@support_email}.</p>
                        <p>© #{current_year()} QueryCanary. All rights reserved.</p>
                      </td>
                    </tr>
                  </table>
                </td>
              </tr>
            </table>
          </td>
        </tr>
      </table>
    </body>
    </html>
    """
  end

  defp chart_html(nil, _cid), do: ""

  defp chart_html(chart, cid) do
    alt = chart.alt_text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

    """
    <tr>
      <td style="padding-top: 20px;">
        <p style="margin: 0 0 10px 0; font-weight: 600; color: #111827;">Result History</p>
        <img src="cid:#{cid}" alt="#{alt}" width="560" style="display: block; width: 100%; max-width: 560px; height: auto;" />
      </td>
    </tr>
    """
  end

  defp attach_chart(email, nil, _cid), do: email

  defp attach_chart(email, chart, cid) do
    attachment(
      email,
      Swoosh.Attachment.new({:data, chart.png},
        filename: chart.filename,
        content_type: "image/png",
        type: :inline,
        cid: cid
      )
    )
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

  # Share analysis formatting with chat providers. Persisted JSON uses string keys.
  defp render_alert_details_table(result) do
    rows =
      result
      |> QueryCanary.Notifications.Alert.details()
      |> Enum.map_join(fn {label, value} ->
        label = label |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
        value = value |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

        """
        <tr>
          <th align="left" style="padding: 8px; font-size: 12px; color: #4b5563;">#{label}</th>
          <td style="padding: 8px; font-family: monospace; word-break: break-all;">#{value}</td>
        </tr>
        """
      end)

    if rows == "",
      do: "",
      else:
        ~s(<table width="100%" style="margin-top: 15px; background-color: #f3f4f6;">#{rows}</table>)
  end

  defp text_alert_details(result) do
    result
    |> QueryCanary.Notifications.Alert.details()
    |> Enum.map_join("\n", fn {label, value} -> "#{label}: #{value}" end)
  end

  # Helper functions
  # defp user_greeting(%User{name: name}) when is_binary(name) and name != "", do: name
  defp user_greeting(%User{email: email}), do: email

  defp alert_type_border_color(:anomaly), do: "#eab308"
  defp alert_type_border_color(:diff), do: "#3b82f6"
  defp alert_type_border_color(_), do: "#ef4444"

  defp alert_type_bg_color(:anomaly), do: "#fef9c3"
  defp alert_type_bg_color(:diff), do: "#dbeafe"
  defp alert_type_bg_color(_), do: "#fee2e2"

  defp alert_type_title(:anomaly), do: "Anomaly Detected"
  defp alert_type_title(:diff), do: "Significant Change Detected"
  defp alert_type_title(:failure), do: "Check Failed"
  defp alert_type_title(_), do: "Alert"

  defp format_datetime(%DateTime{} = dt) do
    Calendar.strftime(dt, "%B %d, %Y at %H:%M:%S UTC")
  end

  defp format_datetime(_), do: "N/A"

  defp current_year do
    DateTime.utc_now().year
  end
end
