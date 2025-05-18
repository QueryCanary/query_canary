defmodule QueryCanaryWeb.BillingLive do
  use QueryCanaryWeb, :live_view

  def render(assigns) do
    ~H"""
    <section class="max-w-lg mx-auto p-6 space-y-8 text-center">
      <div class="card bg-base-200 max-w-md w-full text-center space-y-6 p-8">
        <h1 class="text-3xl font-bold">Paid Plans Coming Soon</h1>
        <p class="text-sm opacity-70">
          You're currently on our free early access plan with unlimited checks. Paid plans will launch soon — but you're all set for now.
        </p>
        <div class="text-sm text-success font-medium">
          ✅ You're getting full access at no cost.
        </div>

        <div class="divider">What’s coming</div>
        <ul class="text-left text-sm list-disc list-inside space-y-1">
          <li>Simple flat pricing</li>
          <li>Slack & webhook alerting</li>
          <li>Check history & charts</li>
          <li>Team support</li>
        </ul>

        <div class="mt-6">
          <button class="btn btn-disabled btn-wide">Upgrade to Pro — Coming Soon</button>
        </div>
      </div>
    </section>
    <%!-- <section class="max-w-2xl mx-auto p-6 space-y-8 text-center">
      <h2 class="text-3xl font-bold">Simple Pricing</h2>
      <p class="text-sm opacity-70 mb-6">Unlimited checks. Flat $15/month.</p>

      <div class="card bg-base-200 shadow-md">
        <div class="card-body items-center">
          <h3 class="card-title text-xl">Team Plan</h3>
          <p class="text-4xl font-bold my-4">$15<span class="text-base">/mo</span></p>

          <button phx-click="start_checkout" class="btn btn-primary mt-4">
            Upgrade
          </button>
        </div>
      </div>
    </section> --%>
    """
  end

  def handle_event("start_checkout", _, socket) do
    user = socket.assigns.current_scope.user

    case create_stripe_checkout_session(user) do
      {:ok, %Stripe.Checkout.Session{url: session_url}} ->
        {:noreply, redirect(socket, external: session_url)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to start checkout: #{inspect(reason)}")}
    end
  end

  defp create_stripe_checkout_session(user) do
    Stripe.Checkout.Session.create(%{
      payment_method_types: ["card"],
      mode: "subscription",
      line_items: [
        %{
          price: "price_1RPlcJPFoGavtXofodxe4qBa",
          quantity: 1
        }
      ],
      success_url: url(~p"/billing?session_id={CHECKOUT_SESSION_ID}"),
      cancel_url: url(~p"/billing"),
      customer_email: user.email
    })
  end
end
