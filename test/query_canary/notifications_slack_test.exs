defmodule QueryCanary.Notifications.SlackTest do
  use ExUnit.Case, async: true
  alias QueryCanary.Notifications.{Slack, Alert}

  test "channel listing follows cursors and includes joined public and private channels only" do
    Req.Test.stub(Slack, fn conn ->
      assert conn.request_path == "/api/conversations.list"
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      params = URI.decode_query(body)
      assert params["types"] == "public_channel,private_channel"

      case params["cursor"] do
        "" ->
          Req.Test.json(conn, %{
            ok: true,
            channels: [
              %{id: "C12345678", name: "ops", is_member: true},
              %{id: "C00000000", name: "not-joined", is_member: false},
              %{id: "C11111111", name: "archived", is_member: true, is_archived: true}
            ],
            response_metadata: %{next_cursor: "page2"}
          })

        "page2" ->
          Req.Test.json(conn, %{
            ok: true,
            channels: [
              %{id: "G12345678", name: "private", is_member: true}
            ],
            response_metadata: %{next_cursor: ""}
          })
      end
    end)

    assert {:ok, [%{id: "C12345678", name: "ops"}, %{id: "G12345678", name: "private"}]} =
             Slack.list_channels("test")
  end

  test "channel listing rejects repeated cursors and malformed responses" do
    Req.Test.stub(
      Slack,
      &Req.Test.json(&1, %{ok: true, channels: [], response_metadata: %{next_cursor: "loop"}})
    )

    assert {:error, :pagination_failed} = Slack.list_channels("test")
    Req.Test.stub(Slack, &Req.Test.json(&1, %{ok: true}))
    assert {:error, :invalid_response} = Slack.list_channels("test")
  end

  test "messages use a compact title and chart link without expanding mentions" do
    alert = %Alert{
      title: "Alert",
      check_name: "<!channel> & <@U123>",
      server_name: "Production",
      summary: String.duplicate("x", 5000),
      url: "https://querycanary.com/checks/1",
      occurred_at: ~U[2026-09-25 12:00:00Z]
    }

    Req.Test.expect(Slack, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      payload = Jason.decode!(body)
      assert payload["parse"] == "none"
      assert payload["text"] =~ "&lt;!channel&gt; &amp; &lt;@U123&gt;"
      title = hd(payload["blocks"])["text"]
      assert title["type"] == "mrkdwn"
      assert title["verbatim"] == true
      assert title["text"] =~ "*&lt;!channel&gt; &amp; &lt;@U123&gt; — Fri Sep 25*"
      caption = Enum.at(payload["blocks"], 1)["text"]
      assert caption["text"] =~ "<https://querycanary.com/checks/1|View check>"
      assert String.length(caption["text"]) <= 3000
      Req.Test.json(conn, %{ok: true})
    end)

    assert :ok = Slack.deliver("test", "C12345678", alert)
  end

  test "transport errors and arbitrary provider responses never expose credentials" do
    Req.Test.stub(Slack, &Req.Test.transport_error(&1, :timeout))
    assert {:error, :unavailable} = Slack.list_channels("secret-token")
    Req.Test.stub(Slack, &Req.Test.json(&1, %{ok: false, error: "unexpected secret-token"}))
    assert {:error, :provider_error} = Slack.list_channels("secret-token")
  end

  test "uploads a PNG privately and includes its file ID and analysis in one channel message" do
    alert = chart_alert()

    Req.Test.expect(Slack, fn conn ->
      assert conn.request_path == "/api/files.getUploadURLExternal"
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer secret-token"]
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      params = URI.decode_query(body)
      assert params["filename"] == alert.chart.filename
      assert params["length"] == to_string(byte_size(alert.chart.png))

      Req.Test.json(conn, %{
        ok: true,
        file_id: "F12345678",
        upload_url: "https://files.slack.com/upload/v1/signed"
      })
    end)

    Req.Test.expect(Slack, fn conn ->
      assert conn.host == "files.slack.com"
      assert conn.request_path == "/upload/v1/signed"
      assert Plug.Conn.get_req_header(conn, "authorization") == []
      assert Plug.Conn.get_req_header(conn, "content-type") == ["image/png"]
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert body == alert.chart.png
      Plug.Conn.send_resp(conn, 200, "OK")
    end)

    Req.Test.expect(Slack, fn conn ->
      assert conn.request_path == "/api/files.completeUploadExternal"
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer secret-token"]
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      assert Jason.decode!(body) == %{
               "files" => [%{"id" => "F12345678", "title" => "Recent results"}]
             }

      Req.Test.json(conn, %{ok: true})
    end)

    Req.Test.expect(Slack, fn conn ->
      assert conn.request_path == "/api/chat.postMessage"
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      payload = Jason.decode!(body)
      assert payload["channel"] == "C12345678"
      assert payload["text"] =~ "Current value: 150"
      assert payload["text"] =~ "Change: 50.0%"

      assert hd(payload["blocks"])["text"]["text"] ==
               "*Orders — Fri Sep 25*\nSignificant Change Detected"

      table = Enum.find(payload["blocks"], &(&1["type"] == "table"))

      assert Enum.map(hd(table["rows"]), fn cell ->
               assert cell["type"] == "rich_text"
               text = cell["elements"] |> hd() |> Map.fetch!("elements") |> hd()
               assert text["style"] == %{"bold" => true}
               text["text"]
             end) == ["Previous value", "Current value", "Change"]

      assert Enum.at(table["rows"], 1) == [
               %{"type" => "raw_text", "text" => "100"},
               %{"type" => "raw_text", "text" => "150"},
               %{"type" => "raw_text", "text" => "50.0%"}
             ]

      assert Enum.at(payload["blocks"], 2)["text"]["text"] ==
               "<https://querycanary.com/checks/1|Recent results> (Value changed)"

      image = Enum.find(payload["blocks"], &(&1["type"] == "image"))
      assert image["slack_file"] == %{"id" => "F12345678"}
      refute Map.has_key?(image, "image_url")
      Req.Test.json(conn, %{ok: true})
    end)

    assert :ok = Slack.deliver("secret-token", "C12345678", alert)
  end

  test "a rejected table falls back to detail fields in the same message" do
    Req.Test.expect(Slack, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      payload = Jason.decode!(body)
      assert Enum.any?(payload["blocks"], &(&1["type"] == "table"))
      Req.Test.json(conn, %{ok: false, error: "invalid_blocks"})
    end)

    Req.Test.expect(Slack, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      payload = Jason.decode!(body)
      refute Enum.any?(payload["blocks"], &(&1["type"] == "table"))
      fields = Enum.find(payload["blocks"], &Map.has_key?(&1, "fields"))["fields"]
      assert %{"type" => "plain_text", "text" => "Current value\n150"} in fields
      Req.Test.json(conn, %{ok: true})
    end)

    assert :ok = Slack.deliver("test", "C12345678", %{chart_alert() | chart: nil})
  end

  test "older installs and failed image uploads still deliver the detailed alert" do
    for error <- ["missing_scope", "file_uploads_disabled", "storage_limit_reached"] do
      Req.Test.expect(Slack, fn conn ->
        assert conn.request_path == "/api/files.getUploadURLExternal"
        Req.Test.json(conn, %{ok: false, error: error})
      end)

      Req.Test.expect(Slack, fn conn ->
        assert conn.request_path == "/api/chat.postMessage"
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)
        assert payload["text"] =~ "Change: 50.0%"
        refute Enum.any?(payload["blocks"], &(&1["type"] == "image"))
        if error == "missing_scope", do: assert(body =~ "Reconnect Slack")
        Req.Test.json(conn, %{ok: true})
      end)

      assert :ok = Slack.deliver("test", "C12345678", chart_alert())
    end
  end

  test "untrusted upload URLs cannot receive chart data or credentials" do
    for url <- [
          "https://example.com/upload/v1/signed",
          "http://files.slack.com/upload/v1/signed",
          "https://files.slack.com.evil.test/upload/v1/signed"
        ] do
      Req.Test.expect(
        Slack,
        &Req.Test.json(&1, %{ok: true, file_id: "F12345678", upload_url: url})
      )

      Req.Test.expect(Slack, fn conn ->
        assert conn.request_path == "/api/chat.postMessage"
        Req.Test.json(conn, %{ok: true})
      end)

      assert :ok = Slack.deliver("test", "C12345678", chart_alert())
    end
  end

  test "binary upload and completion failures fall back without sending a broken image" do
    for stage <- [:upload, :complete] do
      Req.Test.expect(
        Slack,
        &Req.Test.json(&1, %{
          ok: true,
          file_id: "F12345678",
          upload_url: "https://files.slack.com/upload/v1/signed"
        })
      )

      Req.Test.expect(Slack, fn conn ->
        assert conn.request_path == "/upload/v1/signed"
        Plug.Conn.send_resp(conn, if(stage == :upload, do: 503, else: 200), "")
      end)

      if stage == :complete do
        Req.Test.expect(Slack, fn conn ->
          assert conn.request_path == "/api/files.completeUploadExternal"
          Req.Test.transport_error(conn, :timeout)
        end)
      end

      Req.Test.expect(Slack, fn conn ->
        assert conn.request_path == "/api/chat.postMessage"
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert body =~ "Chart unavailable"
        refute body =~ "slack_file"
        Req.Test.json(conn, %{ok: true})
      end)

      assert :ok = Slack.deliver("test", "C12345678", chart_alert())
    end
  end

  defp chart_alert do
    %Alert{
      title: "Significant Change Detected",
      check_name: "Orders",
      summary: "Value changed",
      server_name: "Production",
      url: "https://querycanary.com/checks/1",
      occurred_at: ~U[2026-09-25 12:00:00Z],
      details: [{"Previous value", "100"}, {"Current value", "150"}, {"Change", "50.0%"}],
      chart: %{
        png: "png-bytes",
        filename: "querycanary-1-2.png",
        title: "Recent results",
        alt_text: "Orders over time"
      }
    }
  end

  test "retries the same uploaded image when Slack has not finished processing it" do
    expect_upload()

    Req.Test.expect(Slack, fn conn ->
      assert conn.request_path == "/api/chat.postMessage"
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(self(), {:first_payload, Jason.decode!(body)})
      image_not_ready(conn)
    end)

    Req.Test.expect(Slack, fn conn ->
      assert conn.request_path == "/api/chat.postMessage"
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert_received {:first_payload, original}
      assert Jason.decode!(body) == original
      assert Enum.any?(original["blocks"], &(&1["slack_file"] == %{"id" => "F12345678"}))
      Req.Test.json(conn, %{ok: true})
    end)

    assert :ok = Slack.deliver("test", "C12345678", chart_alert())
  end

  test "a persistently rejected image cannot prevent delivery of the alert" do
    expect_upload()

    Req.Test.expect(Slack, 4, fn conn ->
      assert conn.request_path == "/api/chat.postMessage"
      image_not_ready(conn)
    end)

    Req.Test.expect(Slack, fn conn ->
      assert conn.request_path == "/api/chat.postMessage"
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      payload = Jason.decode!(body)
      refute Enum.any?(payload["blocks"], &(&1["type"] == "image"))
      assert payload["text"] =~ "Current value: 150"
      assert body =~ "Chart unavailable"
      Req.Test.json(conn, %{ok: true})
    end)

    assert :ok = Slack.deliver("test", "C12345678", chart_alert())
  end

  test "ambiguous post failures and rate limits are left to Oban without immediate reposting" do
    for failure <- [:timeout, :rate_limit] do
      expect_upload()

      Req.Test.expect(Slack, fn conn ->
        assert conn.request_path == "/api/chat.postMessage"

        case failure do
          :timeout ->
            Req.Test.transport_error(conn, :timeout)

          :rate_limit ->
            conn |> Plug.Conn.put_resp_header("retry-after", "17") |> Plug.Conn.send_resp(429, "")
        end
      end)

      expected = if failure == :timeout, do: :unavailable, else: {:rate_limited, 17}
      assert {:error, ^expected} = Slack.deliver("test", "C12345678", chart_alert())
    end
  end

  test "block diagnostics expose only recognized reasons, never raw response metadata" do
    for metadata <- [
          nil,
          "secret-token",
          %{"messages" => ["secret-token"]},
          %{"messages" => "secret-token"}
        ] do
      Req.Test.expect(
        Slack,
        &Req.Test.json(&1, %{ok: false, error: "invalid_blocks", response_metadata: metadata})
      )

      assert {:error, {:invalid_blocks, :invalid_format}} =
               Slack.deliver("secret-token", "C12345678", %{
                 chart_alert()
                 | chart: nil,
                   details: []
               })
    end
  end

  defp expect_upload do
    Req.Test.expect(Slack, fn conn ->
      assert conn.request_path == "/api/files.getUploadURLExternal"

      Req.Test.json(conn, %{
        ok: true,
        file_id: "F12345678",
        upload_url: "https://files.slack.com/upload/v1/signed"
      })
    end)

    Req.Test.expect(Slack, fn conn ->
      assert conn.request_path == "/upload/v1/signed"
      Plug.Conn.send_resp(conn, 200, "OK")
    end)

    Req.Test.expect(Slack, fn conn ->
      assert conn.request_path == "/api/files.completeUploadExternal"
      Req.Test.json(conn, %{ok: true})
    end)
  end

  defp image_not_ready(conn) do
    Req.Test.json(conn, %{
      ok: false,
      error: "invalid_blocks",
      response_metadata: %{
        messages: ["[ERROR] invalid slack file [json-pointer:/blocks/3/slack_file]"]
      }
    })
  end
end
