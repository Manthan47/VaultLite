defmodule VaultLite.Schema.SecretShare do
  @moduledoc """
  Secret share schema and functions for managing secret sharing.
  """
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  @permission_levels ["read_only", "editable"]

  schema "secret_shares" do
    field :secret_key, :string
    field :permission_level, :string
    field :shared_at, :utc_datetime
    field :expires_at, :utc_datetime
    field :active, :boolean, default: true

    belongs_to :owner, VaultLite.Schema.User, foreign_key: :owner_id
    belongs_to :shared_with, VaultLite.Schema.User, foreign_key: :shared_with_id

    timestamps()
  end

  @doc """
  Changeset for creating and updating a secret share.
  """
  def changeset(secret_share, attrs) do
    secret_share
    |> cast(attrs, [
      :secret_key,
      :owner_id,
      :shared_with_id,
      :permission_level,
      :shared_at,
      :expires_at,
      :active
    ])
    |> validate_required([:secret_key, :owner_id, :shared_with_id, :permission_level, :shared_at])
    |> validate_inclusion(:permission_level, @permission_levels,
      message: "must be either 'read_only' or 'editable'"
    )
    |> validate_different_users()
    |> unique_constraint([:secret_key, :shared_with_id],
      name: :secret_shares_unique_share,
      message: "secret is already shared with this user"
    )
  end

  @doc """
  Query helper to filter active shares only.
  """
  def active_shares(query) do
    from s in query, where: s.active == true
  end

  @doc """
  Query helper to filter by secret key.
  """
  def by_secret(query, secret_key) do
    from s in query, where: s.secret_key == ^secret_key
  end

  @doc """
  Query helper to filter by user who received the share.
  """
  def by_shared_with(query, user_id) do
    from s in query, where: s.shared_with_id == ^user_id
  end

  @doc """
  Query helper to filter by owner (user who shared the secret).
  """
  def by_owner(query, user_id) do
    from s in query, where: s.owner_id == ^user_id
  end

  @doc """
  Query helper to filter by permission level.
  """
  def with_permission(query, permission_level) do
    from s in query, where: s.permission_level == ^permission_level
  end

  @doc """
  Query helper to filter by expiration status.
  """
  def not_expired(query) do
    now = DateTime.utc_now()
    from s in query, where: is_nil(s.expires_at) or s.expires_at > ^now
  end

  # Private validation functions

  defp validate_different_users(changeset) do
    owner_id = get_field(changeset, :owner_id)
    shared_with_id = get_field(changeset, :shared_with_id)

    if owner_id && shared_with_id && owner_id == shared_with_id do
      add_error(changeset, :shared_with_id, "cannot share secret with yourself")
    else
      changeset
    end
  end
end
