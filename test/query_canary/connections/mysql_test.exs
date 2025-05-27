defmodule QueryCanary.Connections.Adapters.MySQLTest do
  use ExUnit.Case, async: false

  alias QueryCanary.Connections.Adapters.MySQL

  @moduletag :database_adapters

  @moduledoc """
  CREATE DATABASE IF NOT EXISTS test_db;
  CREATE USER 'test_user'@'localhost' IDENTIFIED BY   'test_pass';
  GRANT SELECT ON test_db.* TO 'test_user'@'localhost';
  use test_db;
  source test/support/adapters/mysql-seed.sql;
  """

  setup_all do
    {:ok, conn} =
      MySQL.connect(%{
        hostname: "localhost",
        port: 3306,
        username: "test_user",
        password: "test_pass",
        database: "test_db"
      })

    {:ok, conn: conn}
  end

  describe "MySQL Adapter" do
    test "can list tables", %{conn: conn} do
      {:ok, tables} = MySQL.list_tables(conn)
      assert is_list(tables)
    end

    test "can get table schema", %{conn: conn} do
      {:ok, _schema} = MySQL.get_table_schema(conn, "numbers")
    end

    test "can get database schema", %{conn: conn} do
      {:ok, schema} = MySQL.get_database_schema(conn, "test_db")
      assert is_map(schema)

      assert schema ==
               %{
                 "numbers" => [
                   %{label: "id", type: "keyword", detail: "int", section: "numbers"},
                   %{label: "value", type: "keyword", detail: "int", section: "numbers"}
                 ]
               }
    end

    test "can run a query", %{conn: conn} do
      {:ok, result} = MySQL.query(conn, "SELECT sum(value) from numbers")

      assert result.rows == [%{"sum(value)": Decimal.new("674")}]
    end
  end
end
