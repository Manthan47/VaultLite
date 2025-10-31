defmodule VaultLiteWeb.Router do
  use VaultLiteWeb, :router
  import VaultLiteWeb.AuthPlug

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {VaultLiteWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug VaultLiteWeb.Plugs.SecurityHeaders
    plug VaultLiteWeb.Plugs.RateLimiter
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug VaultLiteWeb.Plugs.SecurityHeaders
  end

  pipeline :authenticate do
    plug Guardian.Plug.Pipeline,
      module: VaultLite.Guardian,
      error_handler: VaultLiteWeb.AuthErrorHandler

    plug Guardian.Plug.VerifyHeader, realm: "Bearer"
    plug Guardian.Plug.EnsureAuthenticated
    plug Guardian.Plug.LoadResource
  end

  pipeline :rate_limit do
    plug :accepts, ["json"]
    plug VaultLiteWeb.Plugs.RateLimiter
  end

  # LiveView authentication pipeline
  pipeline :live_auth do
    plug :fetch_current_user
    plug :require_authenticated_user
  end

  pipeline :live_no_auth do
    plug :fetch_current_user
    plug :redirect_if_authenticated
  end

  # Public routes (unauthenticated)
  scope "/", VaultLiteWeb do
    pipe_through [:browser, :live_no_auth]

    live "/", AuthLive.LoginLive, :new
    live "/login", AuthLive.LoginLive, :new
    live "/register", AuthLive.RegisterLive, :new
  end

  # Protected LiveView routes (authenticated)
  scope "/", VaultLiteWeb do
    pipe_through [:browser, :live_auth]

    live "/dashboard", DashboardLive.SecretDashboardLive, :index
    live "/secrets/new", SecretsLive.SecretFormLive, :new
    live "/secrets/:key", SecretsLive.SecretDetailLive, :show
    live "/secrets/:key/edit", SecretsLive.SecretFormLive, :edit
    live "/secrets/:key/versions", SecretsLive.SecretDetailLive, :versions
    live "/secrets/:secret_key/share", SecretsLive.SecretSharingLive, :show

    # Admin routes
    live "/admin/users", AdminLive.UserManagementLive, :index
    live "/admin/roles", AdminLive.RoleManagementLive, :index
    live "/admin/audit", AdminLive.AuditLogLive, :index
  end

  # Root route redirect
  scope "/", VaultLiteWeb do
    pipe_through :browser

    post "/liveview_login", AuthController, :liveview_login
    delete "/logout", AuthController, :logout
  end

  # API routes with authentication and rate limiting
  scope "/api", VaultLiteWeb do
    pipe_through [:api, :rate_limit, :authenticate]

    # Secret management endpoints
    resources "/secrets", SecretController,
      only: [:index, :create, :show, :update, :delete],
      param: "key"

    get "/secrets/:key/versions", SecretController, :versions
    get "/secrets/:key/versions/:version", SecretController, :show_version

    # Secret sharing endpoints
    post "/secrets/:secret_key/share", SecretSharingController, :share_secret

    delete "/secrets/:secret_key/share/:shared_with_username",
           SecretSharingController,
           :revoke_sharing

    get "/secrets/:secret_key/shares", SecretSharingController, :get_secret_shares
    get "/secrets/:secret_key/permission", SecretSharingController, :check_permission
    get "/shared/with-me", SecretSharingController, :list_shared_with_me
    get "/shared/by-me", SecretSharingController, :list_my_shares

    # Role management endpoints
    resources "/roles", RoleController, only: [:create, :index, :show]
    post "/roles/assign", RoleController, :assign

    # Audit logging endpoints
    scope "/audit" do
      get "/logs", AuditController, :logs
      get "/secrets/:key", AuditController, :secret_trail
      get "/users/:user_id", AuditController, :user_trail
      get "/statistics", AuditController, :statistics
      delete "/purge", AuditController, :purge
    end
  end

  # Public authentication endpoints (no auth required)
  scope "/api/auth", VaultLiteWeb do
    pipe_through [:api, :rate_limit]

    post "/login", AuthController, :login
    post "/register", AuthController, :register
  end

  # Bootstrap endpoints (no auth required, one-time setup)
  scope "/api/bootstrap", VaultLiteWeb do
    pipe_through [:api, :rate_limit]

    get "/status", BootstrapController, :status
    post "/setup", BootstrapController, :setup
  end

  # Other scopes may use custom stacks.
  # scope "/api", VaultLiteWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:vault_lite, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: VaultLiteWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
