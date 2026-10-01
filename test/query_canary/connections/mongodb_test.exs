defmodule QueryCanary.Connections.Adapters.MongoDBTest do
  use ExUnit.Case, async: true
  alias QueryCanary.Connections.Adapters.MongoDB

  test "rejects invalid JSON and non-object queries before accessing the database" do
    for query <- ["db.users.find({})", "[]", "null", "42"] do
      assert {:error, message} = MongoDB.query(nil, query)
      assert is_binary(message)
    end

    assert {:error, _} = MongoDB.query(nil, ~s({"delete": "users"}))
  end

  test "decodes typed values and whole-string parameters without interpolating text" do
    query =
      ~s({"find":"users","filter":{"created_at":{"$gte":"$1","$lt":"$2"},"name":"contains $1","id":{"$oid":"507f1f77bcf86cd799439011"},"date":{"$date":"2025-01-01T00:00:00Z"},"amount":{"$numberDecimal":"12.50"}}})

    from = ~U[2025-01-01 00:00:00Z]
    to = ~U[2025-01-02 00:00:00Z]
    assert {:ok, %{"filter" => filter}} = MongoDB.parse_query(query, [from, to])
    assert filter["created_at"] == %{"$gte" => from, "$lt" => to}
    assert filter["name"] == "contains $1"
    assert filter["id"] == BSON.ObjectId.decode!("507f1f77bcf86cd799439011")
    assert filter["date"] == from
    assert filter["amount"] == Decimal.new("12.50")
  end

  test "returns errors for missing parameters or invalid typed values" do
    for query <- [
          ~s({"count":"users","query":{"date":"$1"}}),
          ~s({"find":"users","filter":{"id":{"$oid":"invalid"}}}),
          ~s({"find":"users","filter":{"date":{"$date":"invalid"}}})
        ] do
      assert {:error, _} = MongoDB.query(nil, query)
    end
  end

  test "normalizes nested BSON results without interning database field names" do
    id = BSON.ObjectId.decode!("507f1f77bcf86cd799439011")

    result =
      MongoDB.format_results([
        %{
          "_id" => id,
          "value" => 10,
          "nested" => [
            %{
              "date" => ~U[2025-01-01 00:00:00Z],
              "amount" => Decimal.new("12.50"),
              "binary" => %BSON.Binary{binary: <<1, 2>>}
            }
          ]
        },
        %{"other" => true}
      ])

    assert result.columns == ["value", "_id", "nested", "other"]
    assert result.num_rows == 2

    assert [
             %{
               "_id" => "507f1f77bcf86cd799439011",
               "value" => 10,
               "nested" => [
                 %{"date" => "2025-01-01T00:00:00Z", "amount" => "12.50", "binary" => "AQI="}
               ]
             },
             %{"other" => true}
           ] = result.rows

    assert Jason.encode!(result.rows)
    assert %{rows: [], columns: [], num_rows: 0} = MongoDB.format_results([])
  end
end

defmodule QueryCanary.Connections.Adapters.MongoDBIntegrationTest do
  use QueryCanary.DataCase, async: false
  alias QueryCanary.Connections.Adapters.MongoDB
  alias QueryCanary.Connections.{ConnectionManager, ConnectionServer, ConnectionTester}
  import QueryCanary.AccountsFixtures
  import QueryCanary.ServersFixtures
  import QueryCanary.ChecksFixtures
  import QueryCanary.MetricsFixtures

  @moduletag :database_adapters
  @details %{
    hostname: "localhost",
    port: 27017,
    database: "test_db",
    username: "test_user",
    password: "test_pass",
    auth_source: "admin",
    ssl_mode: "disable"
  }

  setup do
    assert {:ok, conn} = MongoDB.connect(@details)
    on_exit(fn -> MongoDB.disconnect(conn) end)
    %{conn: conn}
  end

  test "counts documents, including an empty result", %{conn: conn} do
    assert {:ok, %{rows: [%{"value" => 2}], columns: ["value"]}} =
             MongoDB.query(conn, ~s({"count":"numbers","query":{"value":{"$gte":20}}}))

    assert {:ok, %{rows: [%{"value" => 0}]}} =
             MongoDB.query(conn, ~s({"count":"numbers","query":{"value":{"$gt":100}}}))
  end

  test "finds with projection and sorting and consumes multiple cursor batches", %{conn: conn} do
    assert {:ok, %{rows: [%{"value" => 30}, %{"value" => 20}, %{"value" => 10}], num_rows: 3}} =
             MongoDB.query(
               conn,
               ~s({"find":"numbers","projection":{"_id":0,"value":1},"sort":{"value":-1},"batchSize":1})
             )

    assert {:ok, %{rows: [], num_rows: 0}} =
             MongoDB.query(conn, ~s({"find":"numbers","filter":{"value":100}}))
  end

  test "aggregates, distinguishes values and converts BSON dates", %{conn: conn} do
    assert {:ok, %{rows: [%{"_id" => nil, "value" => 60}], columns: ["value", "_id"]}} =
             MongoDB.query(
               conn,
               ~s({"aggregate":"numbers","pipeline":[{"$group":{"_id":null,"value":{"$sum":"$value"}}}],"cursor":{"batchSize":1}})
             )

    assert {:ok, %{rows: rows}} = MongoDB.query(conn, ~s({"distinct":"numbers","key":"value"}))
    assert Enum.sort(Enum.map(rows, & &1["value"])) == [10, 20, 30]

    assert {:ok, %{rows: [%{"_id" => "507f1f77bcf86cd799439011", "created_at" => date}]}} =
             MongoDB.query(
               conn,
               ~s({"find":"numbers","filter":{"_id":{"$oid":"507f1f77bcf86cd799439011"}},"projection":{"created_at":1}})
             )

    assert date == "2025-01-01T12:00:00.000Z"
  end

  test "discovers collection fields", %{conn: conn} do
    assert {:ok, tables} = MongoDB.list_tables(conn)
    assert "numbers" in tables
    assert {:ok, %{"numbers" => fields}} = MongoDB.get_database_schema(conn, "test_db")
    assert Enum.any?(fields, &(&1.label == "created_at" and &1.detail == "date"))
    assert Enum.any?(fields, &(&1.label == "value" and &1.detail == "integer"))
  end

  test "reports database errors without terminating the connection", %{conn: conn} do
    assert {:error, message} =
             MongoDB.query(conn, ~s({"aggregate":"numbers","pipeline":[{"$invalid":{}}]}))

    assert is_binary(message)
    assert {:ok, _} = MongoDB.query(conn, ~s({"ping":1}))
  end

  test "rejects invalid credentials during connection validation" do
    assert {:error, reason} = MongoDB.connect(%{@details | password: "incorrect"})
    assert is_binary(reason)
  end

  test "connection manager, diagnostics, scheduled checks and metric windows" do
    scope = user_scope_fixture()

    server =
      server_fixture(scope, %{
        db_engine: "mongodb",
        db_hostname: "127.0.0.1",
        db_port: 27017,
        db_username: "test_user",
        db_password_input: "test_pass",
        db_auth_source: "admin",
        db_ssl_mode: "disable"
      })

    on_exit(fn -> ConnectionServer.invalidate(server.id) end)

    assert {:ok, _} = ConnectionManager.test_connection(server)
    assert {:ok, %{version: version}} = ConnectionTester.diagnose_connection(server)
    assert version != "Unknown version"

    check = check_fixture(scope, %{server_id: server.id, query: ~s({"count":"numbers"})})
    assert {:ok, result} = QueryCanary.Checks.run_check(check)
    assert result.success
    assert result.result == [%{"value" => 3}]

    metric =
      metric_fixture(scope, %{
        server: server,
        sql: ~s({"count":"numbers","query":{"created_at":{"$gte":"$1","$lt":"$2"}}})
      })

    assert {:ok, result} =
             QueryCanary.Metrics.run_metric_range(
               metric,
               ~U[2025-01-01 00:00:00Z],
               ~U[2025-01-03 00:00:00Z]
             )

    assert Decimal.equal?(result.value, Decimal.new(2))
  end
end
