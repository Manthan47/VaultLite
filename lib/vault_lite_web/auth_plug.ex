defmodule VaultLiteWeb.AuthPlug do
  @moduledoc """
  Authentication plugs for LiveView integration with Guardian JWT.
  Provides session-based authentication for LiveView while maintaining JWT compatibility.
  """
  import Plug.Conn
  import Phoenix.Controller

  alias VaultLite.Auth
  alias VaultLite.Guardian
  alias VaultLite.Repo
  alias VaultLite.User

  @doc """
  Fetches the current user from session or Guardian token and assigns to conn.
  """
  def fetch_current_user(conn, _opts) do
    case get_session(conn, :user_token) do
      nil ->
        # Try to get user from Guardian if available (for API compatibility)
        case Guardian.Plug.current_resource(conn) do
          %User{} = user ->
            conn
            |> assign(:current_user, user)
            |> put_session(:user_token, user.id)

          _ ->
            assign(conn, :current_user, nil)
        end

      user_id when is_integer(user_id) ->
        user = Repo.get(User, user_id)
        assign(conn, :current_user, user)

      user_id when is_binary(user_id) ->
        case Integer.parse(user_id) do
          {id, ""} ->
            user = Repo.get(User, id)
            assign(conn, :current_user, user)

          _ ->
            assign(conn, :current_user, nil)
        end

      _ ->
        assign(conn, :current_user, nil)
    end
  end

  @doc """
  Requires an authenticated user. Redirects to login if not authenticated.
  """
  def require_authenticated_user(conn, _opts) do
    case conn.assigns[:current_user] do
      %User{} = _user ->
        conn

      _ ->
        conn
        |> put_flash(:error, "You must log in to access this page.")
        |> redirect(to: "/login")
        |> halt()
    end
  end

  @doc """
  Redirects to dashboard if user is already authenticated.
  """
  def redirect_if_authenticated(conn, _opts) do
    case conn.assigns[:current_user] do
      %User{} = _user ->
        conn
        |> redirect(to: "/dashboard")
        |> halt()

      _ ->
        conn
    end
  end

  @doc """
  Logs in a user by storing their ID in the session.
  """
  def log_in_user(conn, %User{} = user) do
    conn
    |> put_session(:user_token, user.id)
    |> put_session(:live_socket_id, "users_sessions:#{user.id}")
    |> configure_session(renew: true)
  end

  @doc """
  Logs out a user by clearing the session.
  """
  def log_out_user(conn) do
    if live_socket_id = get_session(conn, :live_socket_id) do
      VaultLiteWeb.Endpoint.broadcast(live_socket_id, "disconnect", %{})
    end

    conn
    |> clear_session()
    |> configure_session(renew: true)
  end

  @doc """
  Gets the current user from the connection assigns.
  """
  def current_user(conn), do: conn.assigns[:current_user]

  @doc """
  Checks if the current user has the specified role.
  """
  def has_role?(conn, role_name) do
    case current_user(conn) do
      %User{} = user ->
        Auth.has_role?(user, role_name)

      _ ->
        false
    end
  end

  @doc """
  Checks if the current user has admin privileges.
  """
  def is_admin?(conn) do
    has_role?(conn, "admin")
  end
end
