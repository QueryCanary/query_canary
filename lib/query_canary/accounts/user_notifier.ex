defmodule QueryCanary.Accounts.UserNotifier do
  import Swoosh.Email

  alias QueryCanary.Mailer
  alias QueryCanary.Accounts.User

  # Delivers the email using the application mailer.
  defp deliver(recipient, subject, body) do
    email =
      new()
      |> to(recipient)
      |> from({"QueryCanary", "support@querycanary.com"})
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  @doc """
  Deliver instructions to update a user email.
  """
  def deliver_update_email_instructions(user, url) do
    deliver(user.email, "Update email instructions", """

    ==============================

    Hi #{user.email},

    You can change your email by visiting the URL below:

    #{url}

    If you didn't request this change, please ignore this.

    ==============================
    """)
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
    deliver(user.email, "Log in instructions", """

    ==============================

    Hi #{user.email},

    You can log into your account by visiting the URL below:

    #{url}

    If you didn't request this email, please ignore this.

    ==============================
    """)
  end

  defp deliver_confirmation_instructions(user, url) do
    deliver(user.email, "Confirmation instructions", """

    ==============================

    Hi #{user.email},

    You can confirm your account by visiting the URL below:

    #{url}

    If you didn't create an account with us, please ignore this.

    ==============================
    """)
  end

  def deliver_invite_instructions(user, team, url) do
    deliver(user.email, "Join #{team.name} on QueryCanary", """

    ==============================

    Hi #{user.email},

    You've been invited to join #{team.name} on QueryCanary, to accept the invite, click the link below:

    #{url}

    If you didn't request this email, please ignore this.

    ==============================
    """)
  end

  def deliver_invite_register_instructions(user, team, url) do
    deliver(user.email, "Join #{team.name} on QueryCanary", """

    ==============================

    Hi #{user.email},

    You were invite to join #{team.name} on QueryCanary. QueryCanary is a data monitoring tool that let's you define SQL checks against your database and get alerted when things don't look quite right.

    You can create an account & join the team by visiting the URL below:

    #{url}

    If you are not interested in joining, please ignore this email.

    ==============================
    """)
  end
end
