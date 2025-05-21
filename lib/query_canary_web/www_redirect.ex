defmodule QueryCanaryWeb.WwwRedirect do
  def init(opts), do: opts

  def call(%Plug.Conn{host: <<"www.", rest::binary>>} = conn, _opts) do
    if Mix.env() == :prod do
      new_url =
        conn
        |> Map.put(:host, rest)
        |> Plug.Conn.request_url()

      conn
      |> Plug.Conn.put_resp_header("location", new_url)
      |> Plug.Conn.send_resp(301, "Moved Permanently. Redirecting to https://querycanary.com/")
      |> Plug.Conn.halt()
    else
      conn
    end
  end

  def call(conn, _opts), do: conn
end
