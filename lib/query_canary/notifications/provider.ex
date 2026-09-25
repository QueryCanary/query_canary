defmodule QueryCanary.Notifications.Provider do
  @moduledoc """
  Chat notification adapter. Connections belong to teams; destinations belong to checks.
  Discord and Teams can implement this contract and register in Notifications.providers/0.
  Credentials and provider HTTP responses must never be returned in delivery errors.
  """

  @callback valid_channel_id?(term()) :: boolean()
  @callback list_channels(binary()) :: {:ok, [%{id: binary(), name: binary()}]} | {:error, term()}
  @callback deliver(binary(), binary(), map()) :: :ok | {:error, term()}
end
