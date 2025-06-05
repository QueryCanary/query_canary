defmodule QueryCanary.Blog.Post do
  @enforce_keys [:title, :slug, :date, :body]
  defstruct [:title, :slug, :date, :body]

  @type t :: %__MODULE__{
          title: String.t(),
          slug: String.t(),
          date: Date.t(),
          body: String.t()
        }
end
