defmodule QueryCanary.Connections.Adapters.PrometheusTest do
  use ExUnit.Case, async: true

  import Req.Test

  alias QueryCanary.Connections.Adapters.Prometheus

  setup :set_req_test_from_context
  setup :verify_on_exit!

  setup do
    Req.Test.stub(__MODULE__, &stub_prometheus/1)
    :ok
  end

  describe "Prometheus adapter" do
    test "can connect and validate build info" do
      assert {:ok, _conn} = Prometheus.connect(conn_details())
    end

    test "can list metric names" do
      {:ok, conn} = Prometheus.connect(conn_details())

      assert {:ok, ["prometheus_build_info", "up"]} = Prometheus.list_tables(conn)
    end

    test "can get metric schema" do
      {:ok, conn} = Prometheus.connect(conn_details())

      assert {:ok, schema} = Prometheus.get_table_schema(conn, "up")

      assert schema == [
               %{label: "instance", type: "keyword", detail: "label", section: "up"},
               %{label: "job", type: "keyword", detail: "label", section: "up"},
               %{
                 label: "timestamp",
                 type: "keyword",
                 detail: "unix timestamp",
                 section: "up"
               },
               %{label: "value", type: "keyword", detail: "sample value", section: "up"}
             ]
    end

    test "can get database schema" do
      {:ok, conn} = Prometheus.connect(conn_details())

      assert {:ok, schema} = Prometheus.get_database_schema(conn, "ignored")

      assert schema == %{
               "prometheus_build_info" => [
                 %{
                   label: "branch",
                   type: "keyword",
                   detail: "label",
                   section: "prometheus_build_info"
                 },
                 %{
                   label: "version",
                   type: "keyword",
                   detail: "label",
                   section: "prometheus_build_info"
                 },
                 %{
                   label: "timestamp",
                   type: "keyword",
                   detail: "unix timestamp",
                   section: "prometheus_build_info"
                 },
                 %{
                   label: "value",
                   type: "keyword",
                   detail: "sample value",
                   section: "prometheus_build_info"
                 }
               ],
               "up" => [
                 %{label: "instance", type: "keyword", detail: "label", section: "up"},
                 %{label: "job", type: "keyword", detail: "label", section: "up"},
                 %{
                   label: "timestamp",
                   type: "keyword",
                   detail: "unix timestamp",
                   section: "up"
                 },
                 %{label: "value", type: "keyword", detail: "sample value", section: "up"}
               ]
             }
    end

    test "can run a vector query" do
      {:ok, conn} = Prometheus.connect(conn_details())

      assert {:ok, result} = Prometheus.query(conn, "up")

      assert result.rows == [
               %{
                 "instance" => "localhost:9090",
                 "job" => "prometheus",
                 "value" => 1.0
               }
             ]
    end

    test "can run a scalar query" do
      {:ok, conn} = Prometheus.connect(conn_details())

      assert {:ok, result} = Prometheus.query(conn, "1")

      assert result.rows == [%{"value" => 1.0}]
    end

    test "can expose build info as a query result" do
      {:ok, conn} = Prometheus.connect(conn_details())

      assert {:ok, result} = Prometheus.query(conn, Prometheus.version_query())

      assert result.rows == [
               %{
                 "branch" => "main",
                 "buildDate" => "2026-03-31T00:00:00Z",
                 "buildUser" => "query-canary",
                 "goVersion" => "go1.24.0",
                 "revision" => "abc123",
                 "version" => "2.54.1"
               }
             ]
    end

    test "rejects positional parameters" do
      {:ok, conn} = Prometheus.connect(conn_details())

      assert {:error, "Prometheus queries do not support positional parameters"} =
               Prometheus.query(conn, "up", ["ignored"])
    end
  end

  defp conn_details do
    %{
      hostname: "prometheus.internal",
      port: 9090,
      username: "test_user",
      password: "test_pass",
      database: "ignored",
      req_options: [plug: {Req.Test, __MODULE__}]
    }
  end

  defp stub_prometheus(conn) do
    conn = Plug.Conn.fetch_query_params(conn)

    if basic_auth_header(conn) != "Basic dGVzdF91c2VyOnRlc3RfcGFzcw==" do
      Req.Test.json(%{conn | status: 401}, %{"status" => "error", "error" => "unauthorized"})
    else
      case {conn.method, conn.request_path, conn.params} do
        {"GET", "/api/v1/status/buildinfo", _params} ->
          Req.Test.json(conn, %{
            "status" => "success",
            "data" => %{
              "version" => "2.54.1",
              "revision" => "abc123",
              "branch" => "main",
              "buildUser" => "query-canary",
              "buildDate" => "2026-03-31T00:00:00Z",
              "goVersion" => "go1.24.0"
            }
          })

        {"GET", "/api/v1/label/__name__/values", _params} ->
          Req.Test.json(conn, %{
            "status" => "success",
            "data" => ["up", "prometheus_build_info"]
          })

        {"GET", "/api/v1/series", %{"match" => ["up"]}} ->
          Req.Test.json(conn, %{
            "status" => "success",
            "data" => [
              %{
                "__name__" => "up",
                "job" => "prometheus",
                "instance" => "localhost:9090"
              }
            ]
          })

        {"GET", "/api/v1/series", %{"match" => ["prometheus_build_info"]}} ->
          Req.Test.json(conn, %{
            "status" => "success",
            "data" => [
              %{
                "__name__" => "prometheus_build_info",
                "version" => "2.54.1",
                "branch" => "main"
              }
            ]
          })

        {"GET", "/api/v1/query", %{"query" => "up"}} ->
          Req.Test.json(conn, %{
            "status" => "success",
            "data" => %{
              "resultType" => "vector",
              "result" => [
                %{
                  "metric" => %{
                    "__name__" => "up",
                    "job" => "prometheus",
                    "instance" => "localhost:9090"
                  },
                  "value" => ["1711900800", "1"]
                }
              ]
            }
          })

        {"GET", "/api/v1/query", %{"query" => "1"}} ->
          Req.Test.json(conn, %{
            "status" => "success",
            "data" => %{
              "resultType" => "scalar",
              "result" => ["1711900800", "1"]
            }
          })

        other ->
          Req.Test.json(%{conn | status: 404}, %{"status" => "error", "error" => inspect(other)})
      end
    end
  end

  defp basic_auth_header(conn) do
    conn
    |> Plug.Conn.get_req_header("authorization")
    |> List.first()
  end
end
