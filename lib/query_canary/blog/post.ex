defmodule QueryCanary.Blog.Post do
  @enforce_keys [:title, :slug, :date, :body, :description]
  defstruct [:title, :slug, :date, :body, :description]

  @type t :: %__MODULE__{
          title: String.t(),
          slug: String.t(),
          date: Date.t(),
          body: String.t(),
          description: String.t()
        }
end
