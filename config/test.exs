import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :vault_lite, VaultLite.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "vault_lite_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :vault_lite, VaultLiteWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "0ROQpDMkc+mbA7lo/aJFQuHn3MIkhjCENdGaVbr2Uo8fdFhHddyQcaUsglmu755R",
  server: false

# In test we don't send emails
config :vault_lite, VaultLite.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Configure encryption key for testing
config :vault_lite,
  encryption_key: "test_encryption_key_that_is_at_least_32_bytes_long_for_testing"

# Configure Guardian for JWT authentication in testing
config :vault_lite, VaultLite.Guardian,
  issuer: "vault_lite",
  secret_key: "test_guardian_secret_key_that_is_long_enough_for_jwt_signing_in_tests"
