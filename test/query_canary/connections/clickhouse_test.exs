defmodule QueryCanary.Connections.Adapters.ClickHouseTest do
  use ExUnit.Case, async: false

  alias QueryCanary.Connections.Adapters.ClickHouse

  @moduletag :database_adapters

  @conn_details %{
    hostname: "localhost",
    port: 8123,
    username: "test_user",
    password: "test_pass",
    database: "test_db"
  }

  describe "ClickHouse Adapter" do
    test "can connect" do
      assert {:ok, _conn} = ClickHouse.connect(@conn_details)
    end

    test "can list tables" do
      {:ok, conn} = ClickHouse.connect(@conn_details)
      {:ok, tables} = ClickHouse.list_tables(conn)
      assert is_list(tables)
    end

    test "can get table schema" do
      {:ok, conn} = ClickHouse.connect(@conn_details)
      {:ok, _schema} = ClickHouse.get_table_schema(conn, "numbers")
    end

    test "can get database schema" do
      {:ok, conn} = ClickHouse.connect(@conn_details)
      {:ok, schema} = ClickHouse.get_database_schema(conn, "default")
      assert is_map(schema)
    end

    test "can run a query" do
      {:ok, conn} = ClickHouse.connect(@conn_details)
      {:ok, result} = ClickHouse.query(conn, "SELECT sum(value) FROM numbers")
      assert Enum.any?(result.rows, fn row -> Map.has_key?(row, "sum(value)") end)
    end
  end
end
