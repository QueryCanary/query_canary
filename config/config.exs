# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :query_canary, :scopes,
  user: [
    default: true,
    module: QueryCanary.Accounts.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :id,
    schema_table: :users,
    test_data_fixture: QueryCanary.AccountsFixtures,
    test_login_helper: :register_and_log_in_user
  ]

config :query_canary,
  ecto_repos: [QueryCanary.Repo],
  generators: [timestamp_type: :utc_datetime],
  env: config_env()

# Configures the endpoint
config :query_canary, QueryCanaryWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: QueryCanaryWeb.ErrorHTML, json: QueryCanaryWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: QueryCanary.PubSub,
  live_view: [signing_salt: "RDuYJa+r"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :query_canary, QueryCanary.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  query_canary: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.0.9",
  query_canary: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :query_canary, Oban,
  engine: Oban.Engines.Basic,
  queues: [default: 10, checks: 10],
  repo: QueryCanary.Repo,
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},
    {Oban.Plugins.Cron,
     crontab: [
       {"* * * * *", QueryCanary.Jobs.CheckScheduler}
     ]},
    Oban.Plugins.Lifeline
  ]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
