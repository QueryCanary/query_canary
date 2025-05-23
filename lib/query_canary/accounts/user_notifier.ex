defmodule QueryCanary.Accounts.UserNotifier do
  import Swoosh.Email

  @moduledoc """
  Example email:

  <table border="0" cellpadding="0" cellspacing="0" width="100%">
    <tr>
      <td>
        <p style="margin-top: 0;">Hi {user},</p>
        <p>Your check <strong>{check.name}</strong> has detected an issue:</p>
      </td>
    </tr>

    <tr>
      <td style="padding: 15px; border-radius: 8px; border-left: 4px solid {alert_type_border_color(check_result.alert_type)}; background-color: {alert_type_bg_color(check_result.alert_type)}; margin: 20px 0;">
        <table border="0" cellpadding="0" cellspacing="0" width="100%">
          <tr>
            <td>
              <h2 style="margin: 0 0 10px 0; font-size: 18px; font-weight: 600; color: #111827;">
              {alert_type_title(check_result.alert_type)}
              </h2>
              <p style="margin-bottom: 15px;">
                {check_result.analysis_summary || "An issue was detected with your data."}
              </p>
              {render_alert_details_table(check_result)}
            </td>
          </tr>
        </table>
      </td>
    </tr>

    <tr>
      <td style="padding-top: 20px;">
        <p>
          You can view more details and the complete check history by clicking the button below:
        </p>
      </td>
    </tr>

    <tr>
      <td align="center" style="padding: 25px 0 15px 0;">
        <table border="0" cellpadding="0" cellspacing="0">
          <tr>
            <td
              bgcolor="#fbc700"
              style="border-radius: 6px; box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);"
            >
              <a
                href="{url}"
                target="_blank"
                style="display: inline-block; padding: 12px 24px; font-weight: 600; color: #333333; text-decoration: none;"
              >
                View Check Details
              </a>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
  """

  alias QueryCanary.Mailer
  alias QueryCanary.Accounts.User

  use Phoenix.Component

  # Delivers the email using the application mailer.
  defp deliver(body, recipient) do
    contents = heex_to_html(body)

    email =
      new()
      |> to(recipient)
      |> from({"QueryCanary", "support@querycanary.com"})
      |> subject(find_title(contents))
      |> html_body(contents)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  attr :title, :string
  attr :subtitle, :string, default: nil

  slot :inner_block

  defp email_layout(assigns) do
    ~H"""
    <!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
    <html xmlns="http://www.w3.org/1999/xhtml">
      <head>
        <meta http-equiv="Content-Type" content="text/html; charset=UTF-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1.0" />
        <title>{@title}</title>
      </head>
      <body style="margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; line-height: 1.5; color: #374151; background-color: #f9fafb;">
        <table border="0" cellpadding="0" cellspacing="0" width="100%">
          <tr>
            <td>
              <table
                align="center"
                border="0"
                cellpadding="0"
                cellspacing="0"
                width="600"
                style="border-collapse: collapse;"
              >
                <tr>
                  <td bgcolor="#00bafe" style="padding: 20px; border-radius: 8px 8px 0 0;">
                    <table border="0" cellpadding="0" cellspacing="0" width="100%">
                      <tr>
                        <td width="80" align="center" valign="top">
                          <img
                            src="https://querycanary.com/images/querycanary-email.png"
                            alt="QueryCanary Logo"
                            width="54"
                            style="display: block;"
                          />
                        </td>
                        <td style="color: #333333; padding-left: 15px;">
                          <h1 style="margin: 0; font-size: 24px; font-weight: 600;">
                            {@title}
                          </h1>
                          <p :if={@subtitle} style="margin: 5px 0 0; opacity: 0.8;">
                            {@subtitle}
                          </p>
                        </td>
                      </tr>
                    </table>
                  </td>
                </tr>

                <tr>
                  <td
                    bgcolor="#ffffff"
                    style="padding: 20px; border-radius: 0 0 8px 8px; box-shadow: 0 2px 4px rgba(0, 0, 0, 0.05);"
                  >
                    {render_slot(@inner_block)}

                    <table border="0" cellpadding="0" cellspacing="0" width="100%">
                      <tr>
                        <td style="padding-top: 20px; text-align: center; font-size: 13px; color: #6b7280;">
                          <p>
                            This is an automated message from QueryCanary. If you have any questions, please contact us at support@querycanary.com.
                          </p>
                          <p>© {Date.utc_today().year} Axxim, LLC. All rights reserved.</p>
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

  @doc """
  Deliver instructions to update a user email.
  """
  def deliver_update_email_instructions(user, url) do
    assigns = %{user: user, url: url}

    ~H"""
    <.email_layout title="Update your email on QueryCanary">
      <table border="0" cellpadding="0" cellspacing="0" width="100%">
        <tr>
          <td>
            <p style="margin-top: 0;">Hi {@user.email},</p>
            <p>Please approve changing your email by clicking the link below:</p>
          </td>
        </tr>

        <tr>
          <td align="center" style="padding: 25px 0 15px 0;">
            <table border="0" cellpadding="0" cellspacing="0">
              <tr>
                <td
                  bgcolor="#fbc700"
                  style="border-radius: 6px; box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);"
                >
                  <a
                    href={@url}
                    target="_blank"
                    style="display: inline-block; padding: 12px 24px; font-weight: 600; color: #333333; text-decoration: none;"
                  >
                    Change Email
                  </a>
                </td>
              </tr>
            </table>
          </td>
        </tr>
      </table>
    </.email_layout>
    """
    |> deliver(user.email)
  end

  @doc """
  Deliver instructions to log in with a magic link.
  """
  def deliver_login_instructions(user, url) do
    case user do
      %User{confirmed_at: nil} -> deliver_confirmation_instructions(user, url)
      _ -> deliver_magic_link_instructions(user, url)
    end
  end

  defp deliver_magic_link_instructions(user, url) do
    assigns = %{user: user, url: url}

    ~H"""
    <.email_layout title="Login to QueryCanary">
      <table border="0" cellpadding="0" cellspacing="0" width="100%">
        <tr>
          <td>
            <p style="margin-top: 0;">Hi {@user.email},</p>
            <p>You can log into your account by visiting the URL below:</p>
          </td>
        </tr>

        <tr>
          <td align="center" style="padding: 25px 0 15px 0;">
            <table border="0" cellpadding="0" cellspacing="0">
              <tr>
                <td
                  bgcolor="#fbc700"
                  style="border-radius: 6px; box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);"
                >
                  <a
                    href={@url}
                    target="_blank"
                    style="display: inline-block; padding: 12px 24px; font-weight: 600; color: #333333; text-decoration: none;"
                  >
                    Login
                  </a>
                </td>
              </tr>
            </table>
          </td>
        </tr>
      </table>
    </.email_layout>
    """
    |> deliver(user.email)
  end

  defp deliver_confirmation_instructions(user, url) do
    assigns = %{user: user, url: url}

    ~H"""
    <.email_layout title="Confirm your email on QueryCanary">
      <table border="0" cellpadding="0" cellspacing="0" width="100%">
        <tr>
          <td>
            <p style="margin-top: 0;">Hi {@user.email},</p>
            <p>You can confirm your account by visiting the URL below:</p>
          </td>
        </tr>

        <tr>
          <td align="center" style="padding: 25px 0 15px 0;">
            <table border="0" cellpadding="0" cellspacing="0">
              <tr>
                <td
                  bgcolor="#fbc700"
                  style="border-radius: 6px; box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);"
                >
                  <a
                    href={@url}
                    target="_blank"
                    style="display: inline-block; padding: 12px 24px; font-weight: 600; color: #333333; text-decoration: none;"
                  >
                    Confirm Email
                  </a>
                </td>
              </tr>
            </table>
          </td>
        </tr>
      </table>
    </.email_layout>
    """
    |> deliver(user.email)
  end

  def deliver_invite_instructions(user, team, url) do
    assigns = %{user: user, team: team, url: url}

    ~H"""
    <.email_layout title={"Join #{@team.name} on QueryCanary"}>
      <table border="0" cellpadding="0" cellspacing="0" width="100%">
        <tr>
          <td>
            <p style="margin-top: 0;">Hi {@user.email},</p>
            <p>
              You've been invited to join {@team.name} on QueryCanary, to accept the invite, click the link below:
            </p>
          </td>
        </tr>

        <tr>
          <td align="center" style="padding: 25px 0 15px 0;">
            <table border="0" cellpadding="0" cellspacing="0">
              <tr>
                <td
                  bgcolor="#fbc700"
                  style="border-radius: 6px; box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);"
                >
                  <a
                    href={@url}
                    target="_blank"
                    style="display: inline-block; padding: 12px 24px; font-weight: 600; color: #333333; text-decoration: none;"
                  >
                    Accept Team Invite
                  </a>
                </td>
              </tr>
            </table>
          </td>
        </tr>
      </table>
    </.email_layout>
    """
    |> deliver(user.email)
  end

  def deliver_invite_register_instructions(user, team, url) do
    assigns = %{user: user, team: team, url: url}

    ~H"""
    <.email_layout title={"Join #{@team.name} on QueryCanary"}>
      <table border="0" cellpadding="0" cellspacing="0" width="100%">
        <tr>
          <td>
            <p style="margin-top: 0;">Hi {@user.email},</p>
            <p>
              You were invite to join {@team.name} on QueryCanary. QueryCanary is a data monitoring tool that let's you define SQL checks against your database and get alerted when things don't look quite right.
            </p>
            <p>
              You can create an account & join the team by visiting the URL below:
            </p>
          </td>
        </tr>

        <tr>
          <td align="center" style="padding: 25px 0 15px 0;">
            <table border="0" cellpadding="0" cellspacing="0">
              <tr>
                <td
                  bgcolor="#fbc700"
                  style="border-radius: 6px; box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);"
                >
                  <a
                    href={@url}
                    target="_blank"
                    style="display: inline-block; padding: 12px 24px; font-weight: 600; color: #333333; text-decoration: none;"
                  >
                    Accept Team Invite
                  </a>
                </td>
              </tr>
            </table>
          </td>
        </tr>
      </table>
    </.email_layout>
    """
    |> deliver(user.email)
  end

  defp heex_to_html(template) do
    template
    |> Phoenix.HTML.Safe.to_iodata()
    |> IO.iodata_to_binary()
  end

  defp find_title(html) do
    html
    |> Floki.parse_document!()
    |> Floki.find("title")
    |> Floki.text(sep: "\n\n")
  end
end
