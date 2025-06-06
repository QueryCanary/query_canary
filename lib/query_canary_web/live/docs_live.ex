defmodule QueryCanaryWeb.DocsLive do
  use QueryCanaryWeb, :live_view
  alias QueryCanary.Docs

  def mount(%{"slug" => slug}, _session, socket) do
    doc = Docs.get_document_by_slug!(slug)

    {:ok,
     socket
     |> assign(:doc, doc)
     |> assign(:page_title, doc.title)
     |> assign(:custom_meta, %{
       title: doc.title,
       description: doc.description || Docs.preview(doc.body),
       image_url: url(~p"/images/querycanary-social.png")
     })}
  end

  def render(assigns) do
    ~H"""
    <section class="max-w-5xl mx-auto py-12 flex gap-4 flex-col md:flex-row px-4">
      <div>
        <ul class="menu bg-base-200 rounded-box w-full md:w-56">
          <li class="menu-title">Documentation</li>
          <li><.link navigate={~p"/docs/overview"}>Overview</.link></li>
          <li>
            <a>Servers</a>
            <ul>
              <li><.link navigate={~p"/docs/servers/postgresql"}>PostgreSQL</.link></li>
              <li><.link navigate={~p"/docs/servers/mysql"}>MySQL</.link></li>
              <li><.link navigate={~p"/docs/servers/clickhouse"}>ClickHouse</.link></li>
              <li><.link navigate={~p"/docs/servers/ssh-tunnel"}>SSH Tunnel</.link></li>
            </ul>
          </li>
        </ul>
      </div>
      <article class="space-y-8">
        <div>
          <h1 class="text-3xl font-bold">{@doc.title}</h1>
          <%!-- <p><em>Posted on: {@post.date}</em></p> --%>
        </div>

        <div class="prose prose-neutral">
          {raw(Earmark.as_html!(@doc.body, code_class_prefix: "language-"))}
        </div>
      </article>
    </section>
    """
  end
end
