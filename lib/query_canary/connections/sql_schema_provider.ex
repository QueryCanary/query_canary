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
    ConnectionManager.get_database_schema(server)
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
end
