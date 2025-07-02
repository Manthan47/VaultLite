defmodule VaultLite.Secret do
  @moduledoc """
  Secret schema and functions for managing secrets.
  """
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  schema "secrets" do
    field :key, :string
    # Encrypted secret data
    field :value, :binary
    field :version, :integer, default: 1
    field :metadata, :map, default: %{}
    field :deleted_at, :utc_datetime
    # Secret type: "role_based" or "personal"
    field :secret_type, :string, default: "role_based"

    # Owner for personal secrets
    belongs_to :owner, VaultLite.User, foreign_key: :owner_id

    timestamps()
  end

  @valid_secret_types ["role_based", "personal"]

  @doc """
  Changeset for creating a new secret.
  """
  def changeset(secret, attrs) do
    secret
    |> cast(attrs, [:key, :value, :version, :metadata, :secret_type, :owner_id])
    |> validate_required([:key, :value, :secret_type])
    |> validate_inclusion(:secret_type, @valid_secret_types,
      message: "must be either 'role_based' or 'personal'"
    )
    |> validate_owner_id_for_personal_secrets()
    |> VaultLite.Security.InputValidator.validate_secret_key(:key)
    |> VaultLite.Security.InputValidator.validate_secret_value(:value)
    |> VaultLite.Security.InputValidator.validate_metadata(:metadata)
    |> validate_number(:version, greater_than: 0)
    |> unique_constraint([:key, :version], name: :secrets_key_version_index)
  end

  @doc """
  Changeset for updating a secret (creates new version).
  """
  def update_changeset(secret, attrs) do
    secret
    |> cast(attrs, [:value, :version, :metadata])
    |> validate_required([:value, :version])
    |> validate_number(:version, greater_than: 0)
  end

  @doc """
  Changeset for soft deleting a secret.
  """
  def delete_changeset(secret, attrs \\ %{}) do
    secret
    |> cast(attrs, [:deleted_at])
    |> put_change(:deleted_at, DateTime.utc_now() |> DateTime.truncate(:second))
  end

  @doc """
  Query helper to filter out deleted secrets.
  """
  def active_secrets(query) do
    from s in query, where: is_nil(s.deleted_at)
  end

  @doc """
  Query helper to get latest version of each secret.
  """
  def latest_versions(query) do
    from s in query,
      distinct: s.key,
      order_by: [desc: s.version]
  end

  @doc """
  Query helper to filter by secret type.
  """
  def by_secret_type(query, secret_type) do
    from s in query, where: s.secret_type == ^secret_type
  end

  @doc """
  Query helper to filter personal secrets by owner.
  """
  def by_owner(query, owner_id) do
    from s in query, where: s.owner_id == ^owner_id
  end

  @doc """
  Query helper to get role-based secrets.
  """
  def role_based_secrets(query) do
    from s in query, where: s.secret_type == "role_based"
  end

  @doc """
  Query helper to get personal secrets for a specific user.
  """
  def personal_secrets_for_user(query, user_id) do
    from s in query,
      where: s.secret_type == "personal" and s.owner_id == ^user_id
  end

  # Private validation functions

  defp validate_owner_id_for_personal_secrets(changeset) do
    secret_type = get_field(changeset, :secret_type)
    owner_id = get_field(changeset, :owner_id)

    case secret_type do
      "personal" when is_nil(owner_id) ->
        add_error(changeset, :owner_id, "is required for personal secrets")

      "role_based" when not is_nil(owner_id) ->
        add_error(changeset, :owner_id, "should not be set for role-based secrets")

      _ ->
        changeset
    end
  end
end
