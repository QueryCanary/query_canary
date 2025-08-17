defmodule QueryCanary.Connections.Adapter do
  @moduledoc """
  Behaviour for database connection adapters.

  Adapters wrap a single logical connection (or pooled abstraction) and expose
  a small uniform API used by ConnectionServer.
  """

  @callback connect(map) :: {:ok, term} | {:error, term}
  @callback query(term, String.t(), list) :: {:ok, term} | {:error, term}
  @callback list_tables(term) :: {:ok, list} | {:error, term}
  @callback get_table_schema(term, String.t()) :: {:ok, term} | {:error, term}
  @callback get_database_schema(term, String.t()) :: {:ok, term} | {:error, term}
  @callback disconnect(term) :: :ok | {:error, term}

  @optional_callbacks disconnect: 1
end
