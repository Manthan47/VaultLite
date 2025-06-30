import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/vault_lite start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :vault_lite, VaultLiteWeb.Endpoint, server: true
end

# VaultLite specific configuration for all environments
# Configure encryption key for secrets
encryption_key = System.get_env("VAULT_LITE_ENCRYPTION_KEY")

if encryption_key do
  config :vault_lite, :encryption_key, encryption_key
end

# Configure Guardian JWT secret
guardian_secret = System.get_env("GUARDIAN_SECRET_KEY")

if guardian_secret do
  config :vault_lite, VaultLite.Guardian,
    issuer: "vault_lite",
    secret_key: guardian_secret
end

# Configure plug_attack for rate limiting
config :vault_lite, :plug_attack,
  storage: {PlugAttack.Storage.Ets, VaultLite.PlugAttack.Storage},
  rules: [
    # Limit to 5 requests per second
    {~r{^/api/}, [{:throttle, name: :api, limit: 5, period: 1_000}]},
    # Limit login attempts to 3 per minute
    {~r{^/api/auth/login}, [{:throttle, name: :login, limit: 3, period: 60_000}]}
  ]

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :vault_lite, VaultLite.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :vault_lite, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :vault_lite, VaultLiteWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base,
    # Enhanced security headers for production
    check_origin: true,
    # Force SSL in production
    force_ssl: [rewrite_on: [:x_forwarded_proto], host: nil],
    # Secure cookie settings
    session_options: [
      store: :cookie,
      key: "_vault_lite_key",
      signing_salt: System.get_env("SIGNING_SALT") || "secure_salt_change_in_prod",
      encryption_salt: System.get_env("ENCRYPTION_SALT") || "secure_encrypt_salt_change_in_prod",
      same_site: "Strict",
      secure: true,
      http_only: true,
      # 24 hours
      max_age: 86_400
    ]

  # ## SSL Support - Enhanced TLS Configuration
  #
  # SSL/TLS Configuration for production security
  ssl_port = String.to_integer(System.get_env("SSL_PORT") || "443")

  # Configure HTTPS if SSL certificates are provided
  if System.get_env("SSL_CERT_PATH") && System.get_env("SSL_KEY_PATH") do
    config :vault_lite, VaultLiteWeb.Endpoint,
      https: [
        port: ssl_port,
        cipher_suite: :strong,
        keyfile: System.get_env("SSL_KEY_PATH"),
        certfile: System.get_env("SSL_CERT_PATH"),
        # Enhanced TLS security settings
        versions: [:"tlsv1.2", :"tlsv1.3"],
        ciphers: [
          # TLS 1.3 ciphers
          "TLS_AES_256_GCM_SHA384",
          "TLS_AES_128_GCM_SHA256",
          "TLS_CHACHA20_POLY1305_SHA256",
          # TLS 1.2 ciphers
          "ECDHE-RSA-AES256-GCM-SHA384",
          "ECDHE-RSA-AES128-GCM-SHA256",
          "ECDHE-RSA-CHACHA20-POLY1305",
          "DHE-RSA-AES256-GCM-SHA384",
          "DHE-RSA-AES128-GCM-SHA256"
        ],
        # Security options
        secure_renegotiate: true,
        reuse_sessions: true,
        honor_cipher_order: true,
        # OCSP stapling
        stapling_cache: {VaultLite.OCSPCache, []}
      ]
  end

  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :vault_lite, VaultLiteWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :vault_lite, VaultLiteWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Also, you may need to configure the Swoosh API client of your choice if you
  # are not using SMTP. Here is an example of the configuration:
  #
  #     config :vault_lite, VaultLite.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # For this example you need include a HTTP client required by Swoosh API client.
  # Swoosh supports Hackney and Finch out of the box:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Hackney
  #
  # See https://hexdocs.pm/swoosh/Swoosh.html#module-installation for details.
end
