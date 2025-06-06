defmodule QueryCanaryWeb.SitemapController do
  use QueryCanaryWeb, :controller
  alias QueryCanary.Blog
  alias QueryCanary.Docs

  @static_paths [
    "/",
    "/about",
    "/blog",
    "/quickstart",
    "/contact"
  ]

  def sitemap(conn, _params) do
    blog_posts = Blog.list_posts()
    blog_urls = Enum.map(blog_posts, fn post -> "/blog/" <> post.slug end)

    documentation = Docs.list_docs()
    doc_urls = Enum.map(documentation, fn doc -> "/docs/" <> doc.slug end)

    urls = @static_paths ++ blog_urls ++ doc_urls
    xml = render_sitemap_xml(urls, conn)

    conn
    |> put_resp_content_type("application/xml")
    |> send_resp(200, xml)
  end

  defp render_sitemap_xml(urls, _conn) do
    base = "https://querycanary.com"

    urls_xml =
      Enum.map(urls, fn path ->
        """
        <url><loc>#{base <> path}</loc></url>
        """
      end)
      |> Enum.join("")

    """
    <?xml version=\"1.0\" encoding=\"UTF-8\"?>
    <urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">
    #{urls_xml}
    </urlset>
    """
  end
end
