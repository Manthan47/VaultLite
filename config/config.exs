# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :vault_lite,
  ecto_repos: [VaultLite.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configures the endpoint
config :vault_lite, VaultLiteWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: VaultLiteWeb.ErrorHTML, json: VaultLiteWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: VaultLite.PubSub,
  live_view: [signing_salt: "hXNYavzQ"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :vault_lite, VaultLite.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  vault_lite: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.0.9",
  vault_lite: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# External logging configuration for audit logs
config :vault_lite, :external_logging,
  enabled: false,
  # Options: :sentry, :datadog, :elastic
  provider: :sentry,
  config: %{
    # Sentry configuration (when provider is :sentry)
    dsn: System.get_env("SENTRY_DSN"),

    # DataDog configuration (when provider is :datadog)
    api_key: System.get_env("DATADOG_API_KEY"),
    app_key: System.get_env("DATADOG_APP_KEY"),

    # Elasticsearch configuration (when provider is :elastic)
    url: System.get_env("ELASTICSEARCH_URL"),
    index: "vault_lite_audit_logs"
  }

# Audit log retention configuration
config :vault_lite, :audit_logs,
  retention_days: 365,
  auto_purge_enabled: false,
  # Run purge job daily at 2 AM
  purge_schedule: "0 2 * * *"

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
