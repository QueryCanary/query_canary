defmodule QueryCanaryWeb.Router do
  use QueryCanaryWeb, :router

  import QueryCanaryWeb.UserAuth
  import Oban.Web.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug QueryCanaryWeb.WwwRedirect
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {QueryCanaryWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", QueryCanaryWeb do
    pipe_through :browser

    get "/sitemap.xml", SitemapController, :sitemap
  end

  # Other scopes may use custom stacks.
  # scope "/api", QueryCanaryWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:query_canary, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: QueryCanaryWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview

      oban_dashboard("/oban")
    end
  end

  ## Authentication routes

  scope "/", QueryCanaryWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{QueryCanaryWeb.UserAuth, :require_authenticated}] do
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email

      live "/servers", ServerLive.Index, :index
      live "/servers/new", ServerLive.Form, :new
      live "/servers/:id", ServerLive.Show, :show
      live "/servers/:id/edit", ServerLive.Form, :edit

      live "/checks", CheckLive.Index, :index
      live "/checks/new", CheckLive.New
      live "/checks/:id/edit", CheckLive.Form, :edit

      live "/quickstart", Quickstart.DatabaseLive
      live "/quickstart/check", Quickstart.CheckLive

      live "/teams", TeamLive.Index, :index
      live "/teams/new", TeamLive.Form, :new
      live "/teams/:id", TeamLive.Show, :show
      live "/teams/:id/edit", TeamLive.Form, :edit
      live "/teams/:id/accept", TeamLive.Show, :accept
    end

    post "/users/update-password", UserSessionController, :update_password
  end

  scope "/", QueryCanaryWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [{QueryCanaryWeb.UserAuth, :mount_current_scope}] do
      live "/", HomeLive

      live "/users/register", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new

      live "/legal/privacy-policy", LegalLive, :privacy
      live "/legal/terms-of-service", LegalLive, :terms
      live "/legal/security", LegalLive, :security
      live "/about", AboutLive

      live "/checks/:id", CheckLive.Show, :show

      get "/docs", RedirectController, :docs
      live "/docs/*slug", DocsLive

      live "/blog/", BlogLive.Index, :index
      live "/blog/:slug", BlogLive.Show, :show
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
