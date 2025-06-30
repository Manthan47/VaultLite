defmodule VaultLite.Secrets do
  @moduledoc """
  The Secrets context - manages secret CRUD operations with encryption and versioning.

  This module provides secure secret management with the following features:
  - AES-256-GCM encryption for secret values
  - Versioning support with automatic increment
  - Soft deletion for audit trail preservation
  - Integration with audit logging
  - Support for both role-based and personal secrets
  """

  import Ecto.Query, warn: false
  alias VaultLite.Repo
  alias VaultLite.{Secret, User, Audit, Encryption, Auth}

  @doc """
  Creates a new encrypted secret with version 1.

  ## Parameters
  - key: The secret identifier
  - value: The plaintext secret value to encrypt
  - user: The user creating the secret (for audit logging)
  - metadata: Optional metadata (default: %{})
  - secret_type: Type of secret - "role_based" or "personal" (default: "role_based")

  ## Examples
      iex> create_secret("api_key", "super_secret_value", user)
      {:ok, %Secret{}}

      iex> create_secret("my_password", "secret123", user, %{}, "personal")
      {:ok, %Secret{secret_type: "personal", owner_id: user.id}}

      iex> create_secret("", "value", user)
      {:error, %Ecto.Changeset{}}
  """
  def create_secret(key, value, user, metadata \\ %{}, secret_type \\ "role_based") do
    with {:ok, :authorized} <- check_secret_access(user, key, "create", secret_type),
         {:ok, encrypted_value} <- Encryption.encrypt(value),
         changeset <- build_create_changeset(key, encrypted_value, metadata, secret_type, user),
         {:ok, secret} <- Repo.insert(changeset),
         {:ok, _audit} <-
           log_secret_action("create", key, user, Map.put(metadata, :secret_type, secret_type)) do
      {:ok, secret}
    else
      {:error, :unauthorized} -> {:error, :unauthorized}
      {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Retrieves a secret by key, optionally a specific version.
  Returns the decrypted value.

  ## Parameters
  - key: The secret identifier
  - user: The user requesting the secret (for audit logging)
  - version: Optional specific version (default: latest)

  ## Examples
      iex> get_secret("api_key", user)
      {:ok, %{key: "api_key", value: "decrypted_value", version: 2}}

      iex> get_secret("api_key", user, 1)
      {:ok, %{key: "api_key", value: "decrypted_value", version: 1}}

      iex> get_secret("nonexistent", user)
      {:error, :not_found}
  """
  def get_secret(key, user, version \\ nil) do
    with secret when not is_nil(secret) <- find_secret(key, version),
         {:ok, :authorized} <- check_secret_access(user, key, "read", secret.secret_type, secret),
         {:ok, decrypted_value} <- Encryption.decrypt(secret.value),
         {:ok, _audit} <-
           log_secret_action("read", key, user, %{
             version: secret.version,
             secret_type: secret.secret_type
           }) do
      {:ok,
       %{
         key: secret.key,
         value: decrypted_value,
         version: secret.version,
         metadata: secret.metadata,
         secret_type: secret.secret_type,
         owner_id: secret.owner_id,
         inserted_at: secret.inserted_at,
         updated_at: secret.updated_at
       }}
    else
      nil -> {:error, :not_found}
      {:error, :unauthorized} -> {:error, :unauthorized}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Updates a secret by creating a new version with incremented version number.

  ## Parameters
  - key: The secret identifier
  - value: The new plaintext secret value to encrypt
  - user: The user updating the secret (for audit logging)
  - metadata: Optional additional metadata

  ## Examples
      iex> update_secret("api_key", "new_secret_value", user)
      {:ok, %Secret{version: 2}}

      iex> update_secret("nonexistent", "value", user)
      {:error, :not_found}
  """
  def update_secret(key, value, user, metadata \\ %{}) do
    with existing_secret when not is_nil(existing_secret) <- find_secret(key, nil),
         {:ok, :authorized} <-
           check_secret_access(user, key, "update", existing_secret.secret_type, existing_secret),
         latest_version <- existing_secret.version,
         new_version = latest_version + 1,
         {:ok, encrypted_value} <- Encryption.encrypt(value),
         changeset <-
           build_update_changeset(
             key,
             encrypted_value,
             new_version,
             metadata,
             existing_secret.secret_type,
             user
           ),
         {:ok, secret} <- Repo.insert(changeset),
         {:ok, _audit} <-
           log_secret_action("update", key, user, %{
             new_version: new_version,
             secret_type: existing_secret.secret_type
           }) do
      {:ok, secret}
    else
      nil -> {:error, :not_found}
      {:error, :unauthorized} -> {:error, :unauthorized}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Soft deletes a secret by marking all versions as deleted.

  ## Parameters
  - key: The secret identifier
  - user: The user deleting the secret (for audit logging)

  ## Examples
      iex> delete_secret("api_key", user)
      {:ok, :deleted}

      iex> delete_secret("nonexistent", user)
      {:error, :not_found}
  """
  def delete_secret(key, user) do
    with secrets when secrets != [] <-
           Repo.all(from s in Secret, where: s.key == ^key and is_nil(s.deleted_at)),
         # Check authorization using the first secret (all versions should have the same type/owner)
         first_secret <- List.first(secrets),
         {:ok, :authorized} <-
           check_secret_access(user, key, "delete", first_secret.secret_type, first_secret) do
      try do
        Repo.transaction(fn ->
          # Soft delete all versions of the secret
          Enum.each(secrets, fn secret ->
            changeset = Secret.delete_changeset(secret)
            Repo.update!(changeset)
          end)

          # Log the deletion
          case log_secret_action("delete", key, user, %{
                 versions_deleted: length(secrets),
                 secret_type: first_secret.secret_type
               }) do
            {:ok, _audit} -> :ok
            {:error, reason} -> Repo.rollback(reason)
          end
        end)

        {:ok, :deleted}
      rescue
        e -> {:error, e}
      end
    else
      {:error, :unauthorized} -> {:error, :unauthorized}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Lists all active (non-deleted) secrets for a user.
  Returns both role-based secrets (that the user has access to) and personal secrets (owned by the user).
  """
  def list_secrets(user, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    offset = Keyword.get(opts, :offset, 0)

    # Get role-based secrets (existing logic)
    role_based_secrets =
      Secret
      |> Secret.active_secrets()
      |> Secret.role_based_secrets()
      |> Secret.latest_versions()
      |> order_by([s], desc: s.updated_at)
      |> Repo.all()
      |> Enum.filter(fn secret ->
        Auth.can_access?(user, secret.key, "read")
      end)

    # Get personal secrets owned by the user
    personal_secrets =
      Secret
      |> Secret.active_secrets()
      |> Secret.personal_secrets_for_user(user.id)
      |> Secret.latest_versions()
      |> order_by([s], desc: s.updated_at)
      |> Repo.all()

    # Combine and sort all secrets
    all_authorized_secrets =
      (role_based_secrets ++ personal_secrets)
      |> Enum.sort_by(& &1.updated_at, {:desc, NaiveDateTime})
      |> Enum.drop(offset)
      |> Enum.take(limit)

    # Log the list action
    secret_keys = Enum.map(all_authorized_secrets, & &1.key)

    log_secret_action("list", "multiple", user, %{
      count: length(all_authorized_secrets),
      keys: secret_keys,
      role_based_count: length(role_based_secrets),
      personal_count: length(personal_secrets)
    })

    {:ok, Enum.map(all_authorized_secrets, &format_secret_summary/1)}
  end

  @doc """
  Gets all versions of a specific secret.
  """
  def get_secret_versions(key, user) do
    with secret when not is_nil(secret) <- find_secret(key, nil),
         {:ok, :authorized} <- check_secret_access(user, key, "read", secret.secret_type, secret),
         versions when versions != [] <-
           Secret
           |> Secret.active_secrets()
           |> where([s], s.key == ^key)
           |> order_by([s], desc: s.version)
           |> Repo.all() do
      log_secret_action("list", key, user, %{
        action_type: "versions",
        secret_type: secret.secret_type
      })

      {:ok, Enum.map(versions, &format_secret_version/1)}
    else
      nil -> {:error, :not_found}
      {:error, :unauthorized} -> {:error, :unauthorized}
      [] -> {:error, :not_found}
    end
  end

  # Private helper functions

  defp build_create_changeset(key, encrypted_value, metadata, secret_type, user) do
    attrs = %{
      key: key,
      value: encrypted_value,
      version: 1,
      metadata: Map.put(metadata, "created_by", user.username),
      secret_type: secret_type
    }

    # Add owner_id for personal secrets
    attrs =
      case secret_type do
        "personal" -> Map.put(attrs, :owner_id, user.id)
        _ -> attrs
      end

    Secret.changeset(%Secret{}, attrs)
  end

  defp build_update_changeset(key, encrypted_value, version, metadata, secret_type, user) do
    attrs = %{
      key: key,
      value: encrypted_value,
      version: version,
      metadata: Map.put(metadata, "updated_by", user.username),
      secret_type: secret_type
    }

    # Add owner_id for personal secrets
    attrs =
      case secret_type do
        "personal" -> Map.put(attrs, :owner_id, user.id)
        _ -> attrs
      end

    Secret.changeset(%Secret{}, attrs)
  end

  defp find_secret(key, nil) do
    # Get latest version
    Secret
    |> Secret.active_secrets()
    |> where([s], s.key == ^key)
    |> order_by([s], desc: s.version)
    |> limit(1)
    |> Repo.one()
  end

  defp find_secret(key, version) do
    # Get specific version
    Secret
    |> Secret.active_secrets()
    |> where([s], s.key == ^key and s.version == ^version)
    |> Repo.one()
  end

  # Authorization logic for both role-based and personal secrets
  defp check_secret_access(user, key, action, secret_type, secret \\ nil) do
    case secret_type do
      "personal" ->
        case action do
          "create" ->
            # Anyone can create personal secrets
            {:ok, :authorized}

          _ ->
            # For other actions, check if user owns the secret
            if secret && secret.owner_id == user.id do
              {:ok, :authorized}
            else
              {:error, :unauthorized}
            end
        end

      "role_based" ->
        # Use existing role-based authorization
        Auth.check_access(user, key, action)

      _ ->
        {:error, :unauthorized}
    end
  end

  defp log_secret_action(action, key, %User{} = user, metadata) do
    Audit.log_action(user, action, key, metadata)
  end

  defp log_secret_action(action, key, user_id, metadata) when is_integer(user_id) do
    Audit.log_action(user_id, action, key, metadata)
  end

  defp format_secret_summary(secret) do
    %{
      key: secret.key,
      version: secret.version,
      metadata: secret.metadata,
      secret_type: secret.secret_type,
      owner_id: secret.owner_id,
      created_at: secret.inserted_at,
      updated_at: secret.updated_at
    }
  end

  defp format_secret_version(secret) do
    %{
      version: secret.version,
      metadata: secret.metadata,
      secret_type: secret.secret_type,
      owner_id: secret.owner_id,
      created_at: secret.inserted_at,
      updated_at: secret.updated_at
    }
  end
end
