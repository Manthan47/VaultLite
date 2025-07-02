defmodule VaultLite.SecretSharing do
  @moduledoc """
  Context for managing secret sharing between users.

  This module provides functionality to:
  - Share personal secrets with other users
  - Manage sharing permissions (read_only, editable)
  - Revoke sharing access
  - List shared secrets and created shares
  """
  import Ecto.Query

  alias VaultLite.Audit
  alias VaultLite.Repo
  alias VaultLite.Schema.Secret
  alias VaultLite.Schema.SecretShare
  alias VaultLite.Schema.User

  @doc """
  Share a secret with another user.

  ## Parameters
  - secret_key: The key of the secret to share
  - owner_user: The user who owns the secret
  - shared_with_username: Username of the user to share with
  - permission_level: "read_only" or "editable"
  - opts: Optional parameters (expires_at, etc.)

  ## Examples
      iex> share_secret("my_key", owner, "recipient_user", "read_only")
      {:ok, %SecretShare{}}

      iex> share_secret("invalid_key", owner, "recipient_user", "read_only")
      {:error, :secret_not_found_or_not_owned}
  """
  def share_secret(secret_key, owner_user, shared_with_username, permission_level, opts \\ []) do
    with {:ok, shared_with_user} <- find_user_by_username(shared_with_username),
         {:ok, _secret} <- verify_secret_ownership(secret_key, owner_user),
         expires_at <- Keyword.get(opts, :expires_at),
         attrs <-
           build_share_attrs(
             secret_key,
             owner_user,
             shared_with_user,
             permission_level,
             expires_at
           ),
         {:ok, secret_share} <- create_secret_share(attrs),
         {:ok, _} <-
           log_sharing_action("share", secret_key, owner_user, shared_with_user, permission_level) do
      {:ok, secret_share}
    end
  end

  @doc """
  Revoke sharing of a secret with a specific user.

  ## Parameters
  - secret_key: The key of the secret
  - owner_user: The user who owns the secret
  - shared_with_username: Username of the user to revoke sharing from

  ## Examples
      iex> revoke_sharing("my_key", owner, "recipient_user")
      {:ok, %SecretShare{}}

      iex> revoke_sharing("my_key", owner, "nonexistent_user")
      {:error, :user_not_found}
  """
  def revoke_sharing(secret_key, owner_user, shared_with_username) do
    with {:ok, shared_with_user} <- find_user_by_username(shared_with_username),
         {:ok, secret_share} <- find_active_share(secret_key, owner_user.id, shared_with_user.id),
         {:ok, updated_share} <- deactivate_share(secret_share),
         {:ok, _} <-
           log_sharing_action(
             "revoke",
             secret_key,
             owner_user,
             shared_with_user,
             secret_share.permission_level
           ) do
      {:ok, updated_share}
    end
  end

  @doc """
  List all secrets shared with a user.

  Returns detailed information about each shared secret including
  the secret data, owner information, and sharing metadata.

  ## Parameters
  - user: The user to get shared secrets for

  ## Examples
      iex> list_shared_secrets(user)
      {:ok, [%{secret_key: "key1", permission_level: "read_only", ...}]}
  """
  def list_shared_secrets(user) do
    query =
      from s in SecretShare,
        join: secret in Secret,
        on: s.secret_key == secret.key,
        join: owner in User,
        on: s.owner_id == owner.id,
        where: s.shared_with_id == ^user.id and s.active == true,
        where: is_nil(secret.deleted_at) and secret.secret_type == "personal",
        select: %{
          secret_key: s.secret_key,
          permission_level: s.permission_level,
          shared_at: s.shared_at,
          expires_at: s.expires_at,
          owner_username: owner.username,
          owner_email: owner.email,
          secret: secret
        }

    {:ok, Repo.all(query)}
  end

  @doc """
  List all shares created by a user (secrets they've shared with others).

  ## Parameters
  - user: The user who shared the secrets

  ## Examples
      iex> list_created_shares(user)
      {:ok, [%{secret_key: "key1", shared_with_username: "user2", ...}]}
  """
  def list_created_shares(user) do
    query =
      from s in SecretShare,
        join: shared_with in User,
        on: s.shared_with_id == shared_with.id,
        where: s.owner_id == ^user.id and s.active == true,
        select: %{
          secret_key: s.secret_key,
          permission_level: s.permission_level,
          shared_at: s.shared_at,
          expires_at: s.expires_at,
          shared_with_username: shared_with.username,
          shared_with_email: shared_with.email,
          share_id: s.id
        }

    {:ok, Repo.all(query)}
  end

  @doc """
  Check if a user has access to a shared secret and return permission level.

  ## Parameters
  - secret_key: The key of the secret to check
  - user: The user to check access for

  ## Examples
      iex> get_shared_secret_permission("shared_key", user)
      {:ok, "read_only"}

      iex> get_shared_secret_permission("not_shared_key", user)
      {:error, :not_shared}
  """
  def get_shared_secret_permission(secret_key, user) do
    query =
      from s in SecretShare,
        where: s.secret_key == ^secret_key and s.shared_with_id == ^user.id and s.active == true

    case Repo.one(query) do
      nil ->
        {:error, :not_shared}

      share ->
        if share.expires_at && DateTime.compare(DateTime.utc_now(), share.expires_at) == :gt do
          {:error, :expired}
        else
          {:ok, share.permission_level}
        end
    end
  end

  @doc """
  Get sharing information for a specific secret and user combination.

  ## Parameters
  - secret_key: The key of the secret
  - owner_id: ID of the secret owner
  - shared_with_id: ID of the user the secret is shared with

  ## Examples
      iex> get_share_info("key1", 1, 2)
      {:ok, %SecretShare{}}

      iex> get_share_info("key1", 1, 999)
      {:error, :not_found}
  """
  def get_share_info(secret_key, owner_id, shared_with_id) do
    query =
      from s in SecretShare,
        where:
          s.secret_key == ^secret_key and s.owner_id == ^owner_id and
            s.shared_with_id == ^shared_with_id and s.active == true

    case Repo.one(query) do
      nil -> {:error, :not_found}
      share -> {:ok, share}
    end
  end

  # Private helper functions

  defp find_user_by_username(username) do
    case Repo.get_by(User, username: username, active: true) do
      nil -> {:error, :user_not_found}
      user -> {:ok, user}
    end
  end

  defp verify_secret_ownership(secret_key, owner_user) do
    query =
      from s in Secret,
        where:
          s.key == ^secret_key and s.owner_id == ^owner_user.id and s.secret_type == "personal" and
            is_nil(s.deleted_at),
        distinct: s.key,
        order_by: [desc: s.version]

    case Repo.one(query) do
      nil -> {:error, :secret_not_found_or_not_owned}
      secret -> {:ok, secret}
    end
  end

  defp build_share_attrs(secret_key, owner_user, shared_with_user, permission_level, expires_at) do
    %{
      secret_key: secret_key,
      owner_id: owner_user.id,
      shared_with_id: shared_with_user.id,
      permission_level: permission_level,
      shared_at: DateTime.utc_now() |> DateTime.truncate(:second),
      expires_at: expires_at,
      active: true
    }
  end

  defp create_secret_share(attrs) do
    # Check if an inactive share already exists for this combination
    case find_inactive_share(attrs.secret_key, attrs.shared_with_id) do
      nil ->
        # No existing share, create new one
        %SecretShare{}
        |> SecretShare.changeset(attrs)
        |> Repo.insert()

      existing_share ->
        # Reactivate existing share with updated attributes
        existing_share
        |> SecretShare.changeset(attrs)
        |> Repo.update()
    end
  end

  defp find_inactive_share(secret_key, shared_with_id) do
    query =
      from s in SecretShare,
        where:
          s.secret_key == ^secret_key and s.shared_with_id == ^shared_with_id and
            s.active == false

    Repo.one(query)
  end

  defp find_active_share(secret_key, owner_id, shared_with_id) do
    query =
      from s in SecretShare,
        where:
          s.secret_key == ^secret_key and s.owner_id == ^owner_id and
            s.shared_with_id == ^shared_with_id and s.active == true

    case Repo.one(query) do
      nil -> {:error, :share_not_found}
      share -> {:ok, share}
    end
  end

  defp deactivate_share(secret_share) do
    secret_share
    |> SecretShare.changeset(%{active: false})
    |> Repo.update()
  end

  defp log_sharing_action(action, secret_key, owner_user, shared_with_user, permission_level) do
    Audit.log_action(owner_user, "secret_#{action}", secret_key, %{
      shared_with_user_id: shared_with_user.id,
      shared_with_username: shared_with_user.username,
      permission_level: permission_level
    })
  end
end
