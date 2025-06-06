defmodule QueryCanary.Docs do
  @moduledoc """
  The Docs context. Loads posts from markdown files in /docs at compile time.
  """
  alias QueryCanary.Docs.Doc

  @docs_dir Path.join(:code.priv_dir(:query_canary), "/docs")

  # Find all markdown files at compile time
  @markdown_files Path.wildcard(Path.join(@docs_dir, "**/*.md"))

  # Mark as external resources so recompilation happens if files change
  Enum.each(@markdown_files, &Module.put_attribute(__MODULE__, :external_resource, &1))

  # Parse all posts at compile time and store in @docs
  @docs Enum.map(@markdown_files, fn path ->
          filename = Path.relative_to(path, @docs_dir)

          slug = String.trim_trailing(filename, ".md")

          {output, 0} = System.cmd("git", ["log", "-1", "--format=%cI", path]) |> dbg()
          modified_at = String.trim(output)
          dbg(modified_at)
          # foo

          {:ok, date} = {:ok, Date.utc_today()}

          {meta, body} =
            case Regex.run(~r/\A---\n(.+?)\n---\n(.*)/ms, File.read!(path)) do
              [_, yaml, body] ->
                meta =
                  yaml
                  |> String.split("\n")
                  |> Enum.map(fn line ->
                    case String.split(line, ":", parts: 2) do
                      [k, v] -> {String.trim(k), String.trim(v)}
                      _ -> nil
                    end
                  end)
                  |> Enum.reject(&is_nil/1)
                  |> Enum.into(%{})

                {meta, body}

              _ ->
                {%{"title" => nil, "description" => nil}, File.read!(path)}
            end

          %Doc{
            title: meta["title"] || slug,
            slug: slug,
            date: date,
            body: body,
            description: meta["description"]
          }
        end)

  @doc """
  Returns all docs posts, sorted by date descending.
  """
  def list_docs do
    Enum.sort_by(@docs, & &1.date, {:desc, Date})
  end

  @doc """
  Gets a post by slug.
  """
  def get_doc_by_slug!(slug) do
    Enum.find(@docs, fn doc -> doc.slug == Enum.join(slug, "/") end) ||
      raise "Documentation not found"
  end

  @doc """
  Previews the post body for use in meta tags and post previews.
  """
  def preview(body) do
    body
    |> String.split("\n")
    |> Enum.reject(&(&1 =~ ~r/^\s*$/))
    |> Enum.take(2)
    |> Enum.join(" ")
    |> String.slice(0, 160)
  end
end
