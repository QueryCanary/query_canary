defmodule QueryCanary.Docs.Document do
  @enforce_keys [:title, :slug, :body, :description]
  defstruct [:title, :slug, :body, :description]

  @type t :: %__MODULE__{
          title: String.t(),
          slug: String.t(),
          body: String.t(),
          description: String.t()
        }
end
