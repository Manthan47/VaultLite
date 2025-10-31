defmodule VaultLiteWeb.SecretSharingController do
  use VaultLiteWeb, :controller
  alias VaultLite.SecretSharing

  action_fallback VaultLiteWeb.FallbackController

  @doc """
  Share a secret with another user.

  POST /api/secrets/:secret_key/share

  Body:
  {
    "shared_with_username": "username",
    "permission_level": "read_only" | "editable",
    "expires_at": "2024-12-31T23:59:59Z" (optional)
  }
  """
  def share_secret(conn, %{"secret_key" => secret_key} = params) do
    user = Guardian.Plug.current_resource(conn)
    shared_with_username = Map.get(params, "shared_with_username")
    permission_level = Map.get(params, "permission_level", "read_only")

    opts =
      case Map.get(params, "expires_at") do
        nil ->
          []

        expires_at_str ->
          case DateTime.from_iso8601(expires_at_str) do
            {:ok, expires_at, _} -> [expires_at: expires_at]
            _ -> []
          end
      end

    with {:ok, secret_share} <-
           SecretSharing.share_secret(
             secret_key,
             user,
             shared_with_username,
             permission_level,
             opts
           ) do
      conn
      |> put_status(:created)
      |> json(%{
        success: true,
        message: "Secret shared successfully",
        data: %{
          secret_key: secret_key,
          shared_with: shared_with_username,
          permission_level: permission_level,
          shared_at: secret_share.shared_at,
          expires_at: secret_share.expires_at
        }
      })
    end
  end

  @doc """
  Revoke sharing of a secret with a specific user.

  DELETE /api/secrets/:secret_key/share/:shared_with_username
  """
  def revoke_sharing(conn, %{"secret_key" => secret_key, "shared_with_username" => username}) do
    user = Guardian.Plug.current_resource(conn)

    with {:ok, _} <- SecretSharing.revoke_sharing(secret_key, user, username) do
      conn
      |> json(%{
        success: true,
        message: "Sharing revoked successfully",
        data: %{
          secret_key: secret_key,
          revoked_for: username
        }
      })
    end
  end

  @doc """
  List all secrets shared with the current user.

  GET /api/shared/with-me
  """
  def list_shared_with_me(conn, _params) do
    user = Guardian.Plug.current_resource(conn)

    with {:ok, shared_secrets} <- SecretSharing.list_shared_secrets(user) do
      formatted_secrets =
        Enum.map(shared_secrets, fn share_data ->
          %{
            secret_key: share_data.secret_key,
            permission_level: share_data.permission_level,
            shared_at: share_data.shared_at,
            expires_at: share_data.expires_at,
            owner: %{
              username: share_data.owner_username,
              email: share_data.owner_email
            },
            secret_info: %{
              version: share_data.secret.version,
              secret_type: share_data.secret.secret_type,
              created_at: share_data.secret.inserted_at,
              updated_at: share_data.secret.updated_at
            }
          }
        end)

      conn
      |> json(%{
        success: true,
        data: %{
          shared_secrets: formatted_secrets,
          count: length(formatted_secrets)
        }
      })
    end
  end

  @doc """
  List all shares created by the current user (secrets they've shared).

  GET /api/shared/by-me
  """
  def list_my_shares(conn, _params) do
    user = Guardian.Plug.current_resource(conn)

    with {:ok, created_shares} <- SecretSharing.list_created_shares(user) do
      formatted_shares =
        Enum.map(created_shares, fn share_data ->
          %{
            secret_key: share_data.secret_key,
            permission_level: share_data.permission_level,
            shared_at: share_data.shared_at,
            expires_at: share_data.expires_at,
            shared_with: %{
              username: share_data.shared_with_username,
              email: share_data.shared_with_email
            }
          }
        end)

      conn
      |> json(%{
        success: true,
        data: %{
          created_shares: formatted_shares,
          count: length(formatted_shares)
        }
      })
    end
  end

  @doc """
  Get sharing information for a specific secret.

  GET /api/secrets/:secret_key/shares
  """
  def get_secret_shares(conn, %{"secret_key" => secret_key}) do
    user = Guardian.Plug.current_resource(conn)

    with {:ok, created_shares} <- SecretSharing.list_created_shares(user) do
      secret_shares =
        Enum.filter(created_shares, fn share ->
          share.secret_key == secret_key
        end)

      formatted_shares =
        Enum.map(secret_shares, fn share_data ->
          %{
            permission_level: share_data.permission_level,
            shared_at: share_data.shared_at,
            expires_at: share_data.expires_at,
            shared_with: %{
              username: share_data.shared_with_username,
              email: share_data.shared_with_email
            }
          }
        end)

      conn
      |> json(%{
        success: true,
        data: %{
          secret_key: secret_key,
          shares: formatted_shares,
          count: length(formatted_shares)
        }
      })
    end
  end

  @doc """
  Check sharing permission for a specific secret.

  GET /api/secrets/:secret_key/permission
  """
  def check_permission(conn, %{"secret_key" => secret_key}) do
    user = Guardian.Plug.current_resource(conn)

    case SecretSharing.get_shared_secret_permission(secret_key, user) do
      {:ok, permission_level} ->
        conn
        |> json(%{
          success: true,
          data: %{
            secret_key: secret_key,
            permission_level: permission_level,
            can_read: true,
            can_edit: permission_level == "editable"
          }
        })

      {:error, :not_shared} ->
        conn
        |> put_status(:forbidden)
        |> json(%{
          success: false,
          error: "Secret is not shared with you"
        })

      {:error, :expired} ->
        conn
        |> put_status(:forbidden)
        |> json(%{
          success: false,
          error: "Sharing has expired"
        })
    end
  end
end
