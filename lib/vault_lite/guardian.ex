defmodule VaultLite.Guardian do
  @moduledoc """
  Guardian implementation for VaultLite JWT authentication.

  This module handles:
  - JWT token generation and validation
  - User authentication and authorization
  - Token claims management
  - Integration with VaultLite.Auth for RBAC
  """
  use Guardian, otp_app: :vault_lite

  alias VaultLite.Auth
  alias VaultLite.Repo
  alias VaultLite.Schema.User

  @doc """
  Encodes the user information into the JWT token.

  ## Parameters
  - user: The user struct to encode
  - token_type: Type of token (default: "access")
  - claims: Additional claims to include

  ## Examples
      iex> subject_for_token(user, %{})
      {:ok, "1"}
  """
  def subject_for_token(%User{id: user_id}, _claims) do
    {:ok, to_string(user_id)}
  end

  def subject_for_token(_, _) do
    {:error, :invalid_user}
  end

  @doc """
  Retrieves the user from the JWT token claims.

  ## Parameters
  - claims: The token claims containing user information

  ## Examples
      iex> resource_from_claims(%{"sub" => "1"})
      {:ok, %User{}}
  """
  def resource_from_claims(%{"sub" => user_id}) do
    case Repo.get(User, user_id) do
      nil -> {:error, :user_not_found}
      user -> {:ok, user}
    end
  end

  def resource_from_claims(_claims) do
    {:error, :invalid_claims}
  end

  @doc """
  Generates a JWT token for a user.

  ## Parameters
  - user: The user to generate a token for
  - claims: Additional claims to include (optional)
  - opts: Token options (optional)

  ## Examples
      iex> generate_token(user)
      {:ok, "eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9..."}

      iex> generate_token(user, %{permissions: ["read", "write"]})
      {:ok, "eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9..."}
  """
  def generate_token(%User{} = user, claims \\ %{}, opts \\ []) do
    # Add user permissions to token claims
    user_permissions = Auth.get_user_permissions(user.id)
    is_admin = Auth.is_admin?(user)

    enhanced_claims =
      claims
      |> Map.put(:permissions, user_permissions)
      |> Map.put(:is_admin, is_admin)
      |> Map.put(:username, user.username)
      |> Map.put(:iat, System.system_time(:second))

    case encode_and_sign(user, enhanced_claims, opts) do
      {:ok, token, _claims} -> {:ok, token}
      error -> error
    end
  end

  @doc """
  Validates a JWT token and returns the user.

  ## Parameters
  - token: The JWT token to validate

  ## Examples
      iex> validate_token("eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9...")
      {:ok, %User{}, %{"permissions" => [...]}}

      iex> validate_token("invalid_token")
      {:error, :invalid_token}
  """
  def validate_token(token) when is_binary(token) do
    case decode_and_verify(token) do
      {:ok, claims} ->
        case resource_from_claims(claims) do
          {:ok, user} -> {:ok, user, claims}
          error -> error
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Authenticates a user with username/email and password.

  ## Parameters
  - identifier: Username or email
  - password: User's password

  ## Examples
      iex> authenticate_user("admin", "password123")
      {:ok, %User{}, "jwt_token"}

      iex> authenticate_user("invalid", "wrong")
      {:error, :invalid_credentials}
  """
  def authenticate_user(identifier, password)
      when is_binary(identifier) and is_binary(password) do
    user = find_user_by_identifier(identifier)

    case user do
      nil ->
        # Run bcrypt to prevent timing attacks
        Bcrypt.no_user_verify()
        {:error, :invalid_credentials}

      %User{active: false} ->
        {:error, :user_inactive}

      %User{} = user ->
        if User.verify_password(user, password) do
          case generate_token(user) do
            {:ok, token} ->
              {:ok, user, token}

            error ->
              error
          end
        else
          {:error, :invalid_credentials}
        end
    end
  end

  @doc """
  Revokes a JWT token (adds to blacklist).

  Note: This is a placeholder implementation. In production, you would
  typically store revoked tokens in a database or cache.

  ## Parameters
  - token: The token to revoke

  ## Examples
      iex> revoke_token("jwt_token")
      :ok
  """
  def revoke_token(token) when is_binary(token) do
    # In a real implementation, you would store this in a blacklist
    # For now, we'll just return :ok
    # TODO: Implement token blacklisting with Redis or database
    :ok
  end

  @doc """
  Checks if a token is revoked.

  ## Parameters
  - token: The token to check

  ## Examples
      iex> token_revoked?("jwt_token")
      false
  """
  def token_revoked?(token) when is_binary(token) do
    # In a real implementation, you would check against a blacklist
    # For now, we'll assume no tokens are revoked
    # TODO: Implement token blacklist checking
    false
  end

  @doc """
  Refreshes a JWT token with updated user permissions.

  ## Parameters
  - current_token: The current valid token

  ## Examples
      iex> refresh_token("current_jwt_token")
      {:ok, "new_jwt_token"}
  """
  def refresh_token(current_token) when is_binary(current_token) do
    case validate_token(current_token) do
      {:ok, user, _claims} ->
        generate_token(user)

      error ->
        error
    end
  end

  defmodule AuthPipeline do
    @moduledoc "Guardian pipeline for authenticating requests"

    use Guardian.Plug.Pipeline,
      otp_app: :vault_lite,
      module: VaultLite.Guardian,
      error_handler: VaultLite.Guardian.AuthErrorHandler

    plug Guardian.Plug.VerifyHeader, scheme: "Bearer"
    plug Guardian.Plug.EnsureAuthenticated
    plug Guardian.Plug.LoadResource
  end

  defmodule AuthErrorHandler do
    @moduledoc "Handles authentication errors"

    import Phoenix.Controller, only: [json: 2]
    import Plug.Conn, only: [put_status: 2, halt: 1]

    @behaviour Guardian.Plug.ErrorHandler

    @impl Guardian.Plug.ErrorHandler
    def auth_error(conn, {type, _reason}, _opts) do
      body = %{
        error: %{
          type: to_string(type),
          message: error_message(type)
        }
      }

      conn
      |> put_status(:unauthorized)
      |> json(body)
      |> halt()
    end

    defp error_message(:invalid_token), do: "Invalid or expired authentication token"
    defp error_message(:unauthenticated), do: "Authentication required"
    defp error_message(:already_authenticated), do: "Already authenticated"
    defp error_message(_), do: "Authentication failed"
  end

  # Private helper functions

  defp find_user_by_identifier(identifier) do
    cond do
      String.contains?(identifier, "@") ->
        # Looks like an email
        Repo.get_by(User, email: identifier)

      true ->
        # Treat as username
        Repo.get_by(User, username: identifier)
    end
  end
end
