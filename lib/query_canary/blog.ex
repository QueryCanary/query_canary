defmodule QueryCanary.Blog do
  @moduledoc """
  The Blog context. Loads posts from markdown files in /blog at compile time.
  """
  alias QueryCanary.Blog.Post

  @blog_dir Path.join(:code.priv_dir(:query_canary), "/blog")

  # Find all markdown files at compile time
  @markdown_files Path.wildcard(Path.join(@blog_dir, "*.md"))

  # Mark as external resources so recompilation happens if files change
  Enum.each(@markdown_files, &Module.put_attribute(__MODULE__, :external_resource, &1))

  # Parse all posts at compile time and store in @posts
  @posts Enum.map(@markdown_files, fn path ->
           filename = Path.basename(path)

           slug = String.trim_trailing(filename, ".md")

           <<year::binary-4, "-", month::binary-2, "-", day::binary-2, "-", _rest::binary>> =
             String.trim_trailing(filename, ".md")

           {:ok, date} = Date.from_iso8601("#{year}-#{month}-#{day}")

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

           %Post{
             title: meta["title"] || slug,
             slug: slug,
             date: date,
             body: body,
             description: meta["description"]
           }
         end)

  @doc """
  Returns all blog posts, sorted by date descending.
  """
  def list_posts do
    Enum.sort_by(@posts, & &1.date, {:desc, Date})
  end

  @doc """
  Gets a post by slug.
  """
  def get_post_by_slug!(slug) do
    Enum.find(@posts, fn post -> post.slug == slug end) || raise "Post not found"
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
