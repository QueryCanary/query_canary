defmodule QueryCanaryWeb.DocsLive do
  use QueryCanaryWeb, :live_view
  alias QueryCanary.Docs

  def mount(%{"slug" => slug}, _session, socket) do
    doc = Docs.get_doc_by_slug!(slug)

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
    <section class="max-w-3xl mx-auto px-6 py-12 space-y-8">
      <article class="space-y-8">
        <div>
          <h1 class="text-3xl font-bold">{@doc.title}</h1>
          <%!-- <p><em>Posted on: {@post.date}</em></p> --%>
        </div>

        <div class="prose prose-neutral">
          {raw(Earmark.as_html!(@doc.body))}
        </div>
      </article>
    </section>
    """
  end
end
