defmodule QueryCanaryWeb.BlogLive.Show do
  use QueryCanaryWeb, :live_view
  alias QueryCanary.Blog

  def mount(%{"slug" => slug}, _session, socket) do
    post = Blog.get_post_by_slug!(slug)

    {:ok,
     socket
     |> assign(:post, post)
     |> assign(:page_title, post.title)
     |> assign(:custom_meta, %{
       title: post.title,
       description: post.description || Blog.preview(post.body),
       image_url: url(~p"/images/querycanary-social.png")
     })}
  end

  def render(assigns) do
    ~H"""
    <section class="max-w-3xl mx-auto px-6 py-12 space-y-8">
      <p>
        <.link navigate={~p"/blog"} class="link link-hover">
          <.icon name="hero-arrow-left" /> Back to Blog Posts
        </.link>
      </p>

      <article class="space-y-8">
        <div>
          <h1 class="text-3xl font-bold">{@post.title}</h1>
          <p><em>Posted on: {@post.date}</em></p>
        </div>

        <div class="prose prose-neutral">
          {raw(Earmark.as_html!(@post.body))}
        </div>
      </article>
    </section>
    """
  end
end
