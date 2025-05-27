defmodule QueryCanary.Connections.Adapters.PostgreSQLTest do
  use ExUnit.Case, async: false

  alias QueryCanary.Connections.Adapters.PostgreSQL

  @moduletag :database_adapters

  setup_all do
    {:ok, conn} =
      PostgreSQL.connect(%{
        hostname: "localhost",
        port: 5432,
        username: "postgres",
        password: "postgres",
        database: "test_db"
      })

    {:ok, conn: conn}
  end

  describe "PostgreSQL Adapter" do
    test "can list tables", %{conn: conn} do
      {:ok, tables} = PostgreSQL.list_tables(conn)
      assert is_list(tables)
    end

    test "can get table schema", %{conn: conn} do
      {:ok, _schema} = PostgreSQL.get_table_schema(conn, "numbers")
    end

    test "can get database schema", %{conn: conn} do
      {:ok, schema} = PostgreSQL.get_database_schema(conn, "test_db")
      assert is_map(schema)

      assert schema ==
               %{
                 "numbers" => [
                   %{label: "id", type: "keyword", detail: "integer", section: "numbers"},
                   %{label: "value", type: "keyword", detail: "integer", section: "numbers"}
                 ]
               }
    end

    test "can run a query", %{conn: conn} do
      {:ok, result} = PostgreSQL.query(conn, "SELECT sum(value) from numbers")
      assert [%{sum: 674}] = result.rows
    end
  end
end
