defmodule VaultLite.Role do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  schema "roles" do
    field :name, :string
    field :permissions, {:array, :string}, default: []

    belongs_to :user, VaultLite.User

    timestamps()
  end

  @valid_permissions ~w(read write delete admin)
  @valid_actions ~w(create read update delete)

  @doc """
  Changeset for creating a new role.
  """
  def changeset(role, attrs) do
    role
    |> cast(attrs, [:name, :permissions, :user_id])
    |> validate_required([:name, :permissions])
    |> VaultLite.Security.InputValidator.validate_role_name(:name)
    |> VaultLite.Security.InputValidator.validate_permissions(:permissions)
    |> unique_constraint([:name, :user_id], name: :roles_name_user_id_index)
  end

  @doc """
  Changeset for updating a role.
  """
  def update_changeset(role, attrs) do
    role
    |> cast(attrs, [:name, :permissions])
    |> validate_required([:name, :permissions])
    |> VaultLite.Security.InputValidator.validate_role_name(:name)
    |> VaultLite.Security.InputValidator.validate_permissions(:permissions)
  end

  @doc """
  Check if a role has a specific permission.
  """
  def has_permission?(%VaultLite.Role{permissions: permissions}, permission) do
    permission in permissions or "admin" in permissions
  end

  @doc """
  Check if a role can perform a specific action.
  Map actions to required permissions.
  """
  def can_perform_action?(%VaultLite.Role{} = role, action) do
    required_permission = map_action_to_permission(action)
    has_permission?(role, required_permission)
  end

  defp map_action_to_permission("create"), do: "write"
  defp map_action_to_permission("read"), do: "read"
  defp map_action_to_permission("update"), do: "write"
  defp map_action_to_permission("delete"), do: "delete"
  # Default to admin for unknown actions
  defp map_action_to_permission(_), do: "admin"

  @doc """
  Get all valid permissions.
  """
  def valid_permissions, do: @valid_permissions

  @doc """
  Get all valid actions.
  """
  def valid_actions, do: @valid_actions

  @doc """
  Query helper to get roles for a specific user.
  """
  def for_user(query, user_id) do
    from r in query, where: r.user_id == ^user_id
  end

  @doc """
  Query helper to get roles with specific permission.
  """
  def with_permission(query, permission) do
    from r in query, where: ^permission in r.permissions or "admin" in r.permissions
  end
end
