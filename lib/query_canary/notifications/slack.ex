defmodule QueryCanary.Notifications.Slack do
  @behaviour QueryCanary.Notifications.Provider
  require Logger

  @scopes ~w(chat:write channels:read groups:read files:write)
  @image_retry_delays [1_000, 2_000, 4_000]

  def configured? do
    Enum.all?([:client_id, :client_secret], &(is_binary(config()[&1]) and config()[&1] != ""))
  end

  def authorize_url(state) do
    "https://slack.com/oauth/v2/authorize?" <>
      URI.encode_query(%{
        client_id: config()[:client_id],
        scope: Enum.join(@scopes, ","),
        redirect_uri: redirect_uri(),
        state: state
      })
  end

  def exchange_code(code) do
    with {:ok, body} <-
           request("oauth.v2.access",
             form: [
               client_id: config()[:client_id],
               client_secret: config()[:client_secret],
               code: code,
               redirect_uri: redirect_uri()
             ]
           ),
         %{
           "access_token" => token,
           "token_type" => "bot",
           "team" => %{"id" => id, "name" => name},
           "scope" => scopes
         } <- body,
         true <- is_binary(token) and token != "" and is_binary(id) and is_binary(name),
         true <- is_binary(scopes) and Enum.all?(@scopes, &(&1 in String.split(scopes, ","))) do
      {:ok, %{token: token, external_id: id, name: name}}
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_installation}
    end
  end

  @impl true
  def valid_channel_id?(id), do: is_binary(id) and Regex.match?(~r/\A[CG][A-Z0-9]{8,254}\z/, id)

  @impl true
  def list_channels(token), do: list_channels(token, "", [], MapSet.new())

  defp list_channels(token, cursor, channels, seen) do
    if MapSet.member?(seen, cursor) or MapSet.size(seen) >= 100 do
      {:error, :pagination_failed}
    else
      with {:ok, %{"channels" => page} = body} when is_list(page) <-
             request("conversations.list",
               auth: {:bearer, token},
               form: [
                 types: "public_channel,private_channel",
                 exclude_archived: true,
                 limit: 200,
                 cursor: cursor
               ]
             ) do
        available =
          for %{"id" => id, "name" => name, "is_member" => true} = channel <- page,
              channel["is_archived"] != true,
              do: %{id: id, name: name}

        channels = channels ++ available

        case get_in(body, ["response_metadata", "next_cursor"]) do
          next when next in [nil, ""] -> {:ok, Enum.sort_by(channels, & &1.name)}
          next -> list_channels(token, next, channels, MapSet.put(seen, cursor))
        end
      else
        {:error, _} = error -> error
        _ -> {:error, :invalid_response}
      end
    end
  end

  @impl true
  def deliver(token, channel_id, alert) do
    details = Enum.map_join(alert.details, "\n", fn {label, value} -> "#{label}: #{value}" end)
    chart_blocks = chart_blocks(token, alert.chart)

    payload = %{
      channel: channel_id,
      text:
        escape(
          String.slice(
            "#{alert.title}: #{alert.check_name}\n#{alert.summary}\n#{details}",
            0,
            3500
          ) <>
            "\n#{alert.url}"
        ),
      parse: "none",
      unfurl_links: false,
      unfurl_media: false,
      blocks:
        [
          %{type: "header", text: plain(alert.title, 150)},
          %{type: "section", text: plain("#{alert.check_name}\n#{alert.summary}", 3000)}
        ] ++
          detail_blocks(alert.details) ++
          chart_blocks ++
          [
            %{
              type: "context",
              elements: [plain("#{alert.server_name} · #{alert.occurred_at} UTC", 2000)]
            },
            %{
              type: "actions",
              elements: [
                %{type: "button", text: plain("View check", 75), url: alert.url}
              ]
            }
          ]
    }

    post_message(token, payload, @image_retry_delays)
  end

  defp post_message(token, payload, delays) do
    case request("chat.postMessage", auth: {:bearer, token}, json: payload) do
      {:ok, _} ->
        :ok

      {:error, {:invalid_blocks, reason}} = error
      when reason in [:invalid_slack_file, :image_download_failed] ->
        if Enum.any?(payload.blocks, &(&1.type == "image")) do
          case delays do
            [delay | remaining] ->
              # Completing an upload can succeed before Slack can embed the image.
              # Retry the SAME file only after an explicit rejection, never an ambiguous timeout.
              Process.sleep(delay)
              post_message(token, payload, remaining)

            [] ->
              Logger.warning(
                "Slack chart is unavailable after processing retries; delivering without image"
              )

              blocks =
                Enum.flat_map(payload.blocks, fn
                  %{type: "image"} -> chart_unavailable_blocks(reason)
                  block -> [block]
                end)

              post_message(token, %{payload | blocks: blocks}, [])
          end
        else
          error
        end

      {:error, _} = error ->
        error
    end
  end

  defp detail_blocks([]), do: []

  defp detail_blocks(details) do
    fields =
      Enum.map(Enum.take(details, 10), fn {label, value} -> plain("#{label}\n#{value}", 2000) end)

    [%{type: "section", fields: fields}]
  end

  defp chart_blocks(_token, nil), do: []

  defp chart_blocks(token, chart) do
    case upload_chart(token, chart) do
      {:ok, file_id} ->
        [
          %{
            type: "image",
            slack_file: %{id: file_id},
            title: plain(chart.title, 2000),
            alt_text: chart.alt_text
          }
        ]

      {:error, reason} ->
        # File permissions, storage limits, or an image service outage must not mute alerts.
        Logger.warning("Slack chart upload failed: #{inspect(reason)}")

        chart_unavailable_blocks(reason)
    end
  end

  defp chart_unavailable_blocks(reason) do
    message =
      if reason == :missing_scope,
        do: "Reconnect Slack from team settings to enable chart images.",
        else: "Chart unavailable. View this check in QueryCanary for its chart."

    [%{type: "context", elements: [plain(message, 2000)]}]
  end

  defp upload_chart(token, chart) do
    with {:ok, %{"upload_url" => url, "file_id" => file_id}}
         when is_binary(url) and is_binary(file_id) <-
           request("files.getUploadURLExternal",
             auth: {:bearer, token},
             form: [
               filename: chart.filename,
               length: byte_size(chart.png),
               alt_txt: chart.alt_text
             ]
           ),
         :ok <- upload_bytes(url, chart.png),
         {:ok, _} <-
           request("files.completeUploadExternal",
             auth: {:bearer, token},
             json: %{files: [%{id: file_id, title: chart.title}]}
           ) do
      # Keep the file private; the same bot embeds it in the one alert message.
      {:ok, file_id}
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_response}
    end
  end

  defp upload_bytes(url, png) do
    case URI.parse(url) do
      %URI{
        scheme: "https",
        host: "files.slack.com",
        port: 443,
        userinfo: nil,
        path: "/upload/" <> _
      } ->
        # The signed URL needs no bot credential, and redirects must not leak query data.
        opts = http_options(url, body: png, headers: [{"content-type", "image/png"}])

        case Req.request(opts) do
          {:ok, %{status: 200}} -> :ok
          {:ok, %{status: 429} = response} -> {:error, {:rate_limited, retry_after(response)}}
          {:ok, %{status: status}} -> {:error, {:http, status}}
          {:error, _} -> {:error, :unavailable}
        end

      _ ->
        {:error, :invalid_upload_url}
    end
  end

  defp plain(text, limit), do: %{type: "plain_text", text: String.slice(text, 0, limit)}

  defp escape(text),
    do:
      text
      |> String.replace("&", "&amp;")
      |> String.replace("<", "&lt;")
      |> String.replace(">", "&gt;")

  defp request(method, opts) do
    # Oban owns delivery retries. Never return request structs containing credentials.
    opts = http_options("https://slack.com/api/" <> method, opts)

    case Req.request(opts) do
      {:ok, %{status: 200, body: %{"ok" => true} = body}} ->
        {:ok, body}

      {:ok, %{status: 200, body: %{"ok" => false, "error" => "invalid_blocks"} = body}} ->
        {:error, {:invalid_blocks, block_error(body)}}

      {:ok, %{status: 200, body: %{"ok" => false, "error" => error}}} ->
        {:error, api_error(error)}

      {:ok, %{status: 429} = response} ->
        {:error, {:rate_limited, retry_after(response)}}

      {:ok, %{status: status}} ->
        {:error, {:http, status}}

      {:error, _} ->
        {:error, :unavailable}
    end
  end

  # Preserve actionable diagnostics without logging raw responses or credentials.
  defp block_error(body) do
    messages =
      case body do
        %{"response_metadata" => %{"messages" => messages}} when is_list(messages) ->
          Enum.filter(messages, &is_binary/1)

        _ ->
          []
      end

    cond do
      Enum.any?(messages, &String.contains?(&1, "invalid slack file")) ->
        :invalid_slack_file

      Enum.any?(messages, &String.contains?(&1, "downloading image failed")) ->
        :image_download_failed

      true ->
        :invalid_format
    end
  end

  defp http_options(url, opts) do
    [
      url: url,
      method: :post,
      retry: false,
      redirect: false,
      receive_timeout: 10_000,
      connect_options: [timeout: 5_000]
    ]
    |> Keyword.merge(opts)
    |> Keyword.merge(Application.get_env(:query_canary, :slack_req_options, []))
  end

  defp api_error(error)
       when error in ~w(invalid_auth token_revoked account_inactive not_authed),
       do: :unauthorized

  defp api_error(error)
       when error in ~w(channel_not_found not_in_channel is_archived restricted_action),
       do: :invalid_destination

  defp api_error("ratelimited"), do: {:rate_limited, 60}
  defp api_error("missing_scope"), do: :missing_scope

  defp api_error(error)
       when error in ~w(invalid_arguments invalid_url invalid_blocks_format msg_too_long no_text),
       do: {:invalid_payload, error}

  defp api_error(_), do: :provider_error

  defp retry_after(response) do
    case Req.Response.get_header(response, "retry-after") do
      [value | _] ->
        case Integer.parse(value) do
          {seconds, ""} when seconds > 0 -> seconds
          _ -> 60
        end

      _ ->
        60
    end
  end

  defp redirect_uri, do: QueryCanaryWeb.Endpoint.url() <> "/integrations/slack/callback"
  defp config, do: Application.get_env(:query_canary, :slack, [])
end
