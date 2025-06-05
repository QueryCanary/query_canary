defmodule QueryCanaryWeb.BlogLive.Index do
  use QueryCanaryWeb, :live_view
  alias QueryCanary.Blog

  def mount(_params, _session, socket) do
    posts = Blog.list_posts()
    {:ok, assign(socket, posts: posts)}
  end

  def render(assigns) do
    ~H"""
    <section class="max-w-3xl mx-auto px-6 py-12 space-y-8">
      <h1 class="text-4xl font-bold mb-6">QueryCanary Blog</h1>
      <p class="text-lg text-gray-500 mb-8">
        Insights, updates, and guides on SQL monitoring, data reliability, and QueryCanary news.
      </p>
      <ul class="divide-y divide-base-200">
        <li :for={post <- @posts} class="py-6 flex flex-col gap-2">
          <.link navigate={~p"/blog/#{post.slug}"} class="text-2xl font-semibold link link-hover">
            {post.title}
          </.link>
          <span class="text-sm text-gray-400">
            {post.date}
          </span>
          <p class="prose prose-neutral">
            {post.description || Blog.preview(post.body)}
          </p>
        </li>
      </ul>
    </section>
    """
  end
end
