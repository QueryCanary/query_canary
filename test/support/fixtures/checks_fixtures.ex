defmodule QueryCanary.ChecksFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `QueryCanary.Checks` context.
  """

  @doc """
  Generate a check.
  """
  def check_fixture(scope, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        expectation: "some expectation",
        query: "some query"
      })

    {:ok, check} = QueryCanary.Checks.create_check(scope, attrs)
    check
  end
end
