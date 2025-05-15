defmodule QueryCanary.Connections.SQLSchemaProvider do
  @moduledoc """
  Provides database schema information for CodeMirror SQL language support.

  This module fetches table and column information from the database using the
  ConnectionManager and formats it according to CodeMirror's SQL language schema
  requirements.
  """

  alias QueryCanary.Connections.ConnectionManager

  @doc """
  Fetches schema information for a server and formats it for CodeMirror.

  ## Parameters
    * server - The database server to fetch schema from

  ## Returns
    * {:ok, schema_json} - JSON string ready for use with CodeMirror
    * {:error, reason} - If schema fetch fails
  """
  def get_codemirror_schema(server) do
    with {:ok, tables} <- ConnectionManager.list_tables(server),
         {:ok, table_schemas} <- fetch_tables_with_columns(server, tables) do
      # schema =
      #   %{
      #     "tables" =>
      #   }
      schema =
        Enum.map(table_schemas, fn %{"name" => table, "columns" => columns} ->
          {table,
           Enum.map(columns, fn %{"name" => name, "type" => type} ->
             %{label: name, type: "keyword", detail: type, section: table}
           end)}
        end)
        |> Enum.into(%{})

      {:ok, Jason.encode!(schema)}
    end
  end

  @doc """
  Fetches schema information for a server and returns it as a JavaScript object literal string.
  This is useful for direct embedding in HTML templates.

  ## Parameters
    * server - The database server to fetch schema from
    * fallback - Default schema to return if fetch fails

  ## Returns
    * JavaScript object literal string for embedding in scripts
  """
  def get_schema_js(server, fallback \\ "{}") do
    case get_codemirror_schema(server) do
      {:ok, schema_json} -> schema_json
      {:error, _} -> fallback
    end
  end

  # Private functions

  # Fetches column information for all tables
  defp fetch_tables_with_columns(server, tables) do
    table_schemas =
      Enum.reduce_while(tables, [], fn table_name, acc ->
        case get_table_with_columns(server, table_name) do
          {:ok, table_schema} -> {:cont, [table_schema | acc]}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)

    case table_schemas do
      {:error, reason} -> {:error, reason}
      tables -> {:ok, tables}
    end
  end

  # Fetches column information for a single table
  defp get_table_with_columns(server, table_name) do
    case ConnectionManager.get_table_schema(server, table_name) do
      {:ok, schema} ->
        columns =
          Enum.map(schema.rows, fn row ->
            %{
              "name" => row[:column_name],
              "type" => map_sql_type(row[:data_type]),
              "nullable" => row[:is_nullable] == "YES"
            }
          end)

        {:ok,
         %{
           "name" => table_name,
           "columns" => columns
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Maps SQL types to simplified types that CodeMirror understands
  defp map_sql_type(type) when is_binary(type) do
    case String.downcase(type) do
      t when t in ["int", "integer", "smallint", "bigint", "serial", "bigserial"] ->
        "number"

      t when t in ["decimal", "numeric", "real", "double precision", "float"] ->
        "number"

      t when t in ["character", "character varying", "varchar", "text", "char", "name"] ->
        "string"

      t
      when t in [
             "timestamp",
             "timestamp without time zone",
             "timestamp with time zone",
             "date",
             "time"
           ] ->
        "date"

      t when t in ["boolean"] ->
        "boolean"

      t when t in ["json", "jsonb"] ->
        "json"

      t when t in ["uuid"] ->
        "string"

      t when t in ["bytea"] ->
        "binary"

      _ ->
        "other"
    end
  end

  defp map_sql_type(_), do: "other"
end
