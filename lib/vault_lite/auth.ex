defmodule VaultLite.Auth do
  @moduledoc """
  The Auth context - manages role-based access control (RBAC) and authentication.

  This module provides comprehensive authentication and authorization with:
  - Role assignment and management
  - Path-based permission checking
  - Integration with Guardian JWT authentication
  - Support for wildcard patterns in secret paths
  """

  import Ecto.Query, warn: false

  alias VaultLite.Schema.AuditLog
  alias VaultLite.Schema.Role
  alias VaultLite.Schema.User
  alias VaultLite.Repo

  @doc """
  Creates a new user with the provided attributes.

  ## Parameters
  - attrs: Map containing user information (%{username: string, email: string, password: string})

  ## Examples
      iex> create_user(%{username: "john", email: "john@example.com", password: "password123"})
      {:ok, %User{}}

      iex> create_user(%{username: "", email: "invalid", password: "short"})
      {:error, %Ecto.Changeset{}}
  """
  def create_user(attrs) do
    changeset = User.changeset(%User{}, attrs)

    case Repo.insert(changeset) do
      {:ok, user} ->
        # Log user creation
        log_auth_action("create_user", user.id, %{
          username: user.username,
          email: user.email
        })

        {:ok, user}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Authenticates a user with username/email and password.

  ## Parameters
  - username_or_email: Username or email string
  - password: Password string

  ## Examples
      iex> authenticate_user("john", "password123")
      {:ok, %User{}}

      iex> authenticate_user("john", "wrongpassword")
      {:error, :invalid_credentials}
  """
  def authenticate_user(username_or_email, password) do
    user = get_user_by_username_or_email(username_or_email)

    cond do
      user && User.verify_password(user, password) ->
        log_auth_action("authenticate", user.id, %{
          login_method:
            if(String.contains?(username_or_email, "@"), do: "email", else: "username")
        })

        {:ok, user}

      user ->
        log_auth_action("failed_authentication", user.id, %{
          reason: "invalid_password",
          attempted_login: username_or_email
        })

        {:error, :invalid_credentials}

      true ->
        # Log failed authentication attempt without user_id
        log_auth_action("failed_authentication", nil, %{
          reason: "user_not_found",
          attempted_login: username_or_email
        })

        {:error, :invalid_credentials}
    end
  end

  @doc """
  Revokes a role from a user by role name.

  ## Parameters
  - user: The user to revoke the role from
  - role_name: Name of the role to revoke

  ## Examples
      iex> revoke_role(user, "temp_access")
      {:ok, :revoked}

      iex> revoke_role(user, "nonexistent")
      {:error, :not_found}
  """
  def revoke_role(%User{id: user_id}, role_name), do: revoke_role(user_id, role_name)

  def revoke_role(user_id, role_name) when is_integer(user_id) do
    case Repo.get_by(Role, user_id: user_id, name: role_name) do
      nil ->
        {:error, :not_found}

      role ->
        case Repo.delete(role) do
          {:ok, _} ->
            log_auth_action("revoke_role", user_id, %{
              role_name: role_name,
              permissions: role.permissions
            })

            {:ok, :revoked}

          {:error, changeset} ->
            {:error, changeset}
        end
    end
  end

  # Private helper function
  defp get_user_by_username_or_email(username_or_email) do
    cond do
      String.contains?(username_or_email, "@") ->
        Repo.get_by(User, email: username_or_email)

      true ->
        Repo.get_by(User, username: username_or_email)
    end
  end

  @doc """
  Assigns a role with specific permissions to a user.

  ## Parameters
  - user: The user to assign the role to (User struct or user_id)
  - role_data: Map containing role information (%{name: string, permissions: [string], path_patterns: [string] (optional)})

  ## Examples
      iex> assign_role(user, %{name: "api_admin", permissions: ["read", "write"]})
      {:ok, %Role{}}

      iex> assign_role(user, %{name: "path_role", permissions: ["read"], path_patterns: ["secrets/dev/*"]})
      {:ok, %Role{}}

      iex> assign_role(user, %{name: "", permissions: ["invalid"]})
      {:error, %Ecto.Changeset{}}
  """
  def assign_role(%User{id: user_id}, role_data), do: assign_role(user_id, role_data)

  def assign_role(user_id, role_data) when is_integer(user_id) do
    # Convert string keys to atom keys for consistency
    role_data = convert_keys_to_atoms(role_data)

    # Handle path patterns by encoding them in the role name
    role_attrs =
      case Map.get(role_data, :path_patterns) do
        nil ->
          role_data
          |> Map.delete(:path_patterns)
          |> Map.put(:user_id, user_id)

        path_patterns when is_list(path_patterns) ->
          # Store path patterns as role metadata in the name for now
          # In a full implementation, you might want a separate path_patterns field
          updated_name =
            if String.contains?(role_data.name, "path:") do
              role_data.name
            else
              case path_patterns do
                [single_pattern] -> "path:#{single_pattern}"
                _ -> "path:#{Enum.join(path_patterns, ",")}"
              end
            end

          role_data
          |> Map.delete(:path_patterns)
          |> Map.put(:name, updated_name)
          |> Map.put(:user_id, user_id)
      end

    changeset = Role.changeset(%Role{}, role_attrs)

    case Repo.insert(changeset) do
      {:ok, role} ->
        # Log role assignment
        log_auth_action("assign_role", user_id, %{
          role_name: role.name,
          permissions: role.permissions
        })

        {:ok, role}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  # Private helper to convert string keys to atom keys
  defp convert_keys_to_atoms(map) do
    map
    |> Enum.map(fn
      {key, value} when is_binary(key) -> {String.to_atom(key), value}
      {key, value} -> {key, value}
    end)
    |> Enum.into(%{})
  end

  @doc """
  Updates an existing role's permissions.

  ## Parameters
  - role_id: The ID of the role to update
  - permissions: New list of permissions
  - user_id: User making the change (for audit logging)

  ## Examples
      iex> update_role_permissions(1, ["read", "write", "delete"], admin_user_id)
      {:ok, %Role{}}
  """
  def update_role_permissions(role_id, permissions, user_id) do
    case Repo.get(Role, role_id) do
      nil ->
        {:error, :role_not_found}

      role ->
        changeset = Role.update_changeset(role, %{permissions: permissions})

        case Repo.update(changeset) do
          {:ok, updated_role} ->
            log_auth_action("update_role", user_id, %{
              role_id: role_id,
              old_permissions: role.permissions,
              new_permissions: permissions
            })

            {:ok, updated_role}

          {:error, changeset} ->
            {:error, changeset}
        end
    end
  end

  @doc """
  Removes a role from a user.

  ## Parameters
  - user: The user to remove the role from
  - role_name: Name of the role to remove

  ## Examples
      iex> remove_role(user, "temp_access")
      {:ok, :removed}

      iex> remove_role(user, "nonexistent")
      {:error, :role_not_found}
  """
  def remove_role(%User{id: user_id}, role_name), do: remove_role(user_id, role_name)

  def remove_role(user_id, role_name) when is_integer(user_id) do
    case Repo.get_by(Role, user_id: user_id, name: role_name) do
      nil ->
        {:error, :role_not_found}

      role ->
        case Repo.delete(role) do
          {:ok, _} ->
            log_auth_action("remove_role", user_id, %{
              role_name: role_name,
              permissions: role.permissions
            })

            {:ok, :removed}

          {:error, changeset} ->
            {:error, changeset}
        end
    end
  end

  @doc """
  Checks if a user has permission to perform an action on a secret key.
  Supports path-based patterns with wildcards.

  ## Parameters
  - user: The user requesting access (User struct or user_id)
  - secret_key: The secret key being accessed (supports wildcard patterns)
  - action: The action being performed ("create", "read", "update", "delete")

  ## Examples
      iex> check_access(user, "api/production/database", "read")
      {:ok, :authorized}

      iex> check_access(user, "api/production/database", "delete")
      {:error, :unauthorized}

      # With wildcard patterns
      iex> check_access(user, "api/*", "read")  # Checks if user can read any api/* secrets
      {:ok, :authorized}
  """
  def check_access(%User{} = user, secret_key, action),
    do: check_access(user.id, secret_key, action)

  def check_access(user_id, secret_key, action) when is_integer(user_id) do
    # Validate secret_key is not nil
    case secret_key do
      nil ->
        {:error, :invalid_secret_key}

      _ ->
        user_roles = get_user_roles(user_id)

        case user_roles do
          [] ->
            log_access_attempt(user_id, secret_key, action, :no_roles)
            {:error, :unauthorized}

          roles ->
            if has_required_permission?(roles, secret_key, action) do
              log_access_attempt(user_id, secret_key, action, :authorized)
              {:ok, :authorized}
            else
              log_access_attempt(user_id, secret_key, action, :insufficient_permissions)
              {:error, :unauthorized}
            end
        end
    end
  end

  @doc """
  Checks if a user can perform an action without logging the attempt.
  Useful for bulk operations or UI permission checks.

  ## Examples
      iex> can_access?(user, "database_password", "read")
      true

      iex> can_access?(user, "admin_secrets/*", "delete")
      false
  """
  def can_access?(%User{} = user, secret_key, action),
    do: can_access?(user.id, secret_key, action)

  def can_access?(user_id, secret_key, action) when is_integer(user_id) do
    user_roles = get_user_roles(user_id)
    has_required_permission?(user_roles, secret_key, action)
  end

  @doc """
  Gets all roles assigned to a user.

  ## Examples
      iex> get_user_roles(user_id)
      [%Role{name: "admin", permissions: ["admin"]}, ...]
  """
  def get_user_roles(%User{id: user_id}), do: get_user_roles(user_id)

  def get_user_roles(user_id) when is_integer(user_id) do
    Role
    |> Role.for_user(user_id)
    |> Repo.all()
  end

  @doc """
  Checks if a user has admin access.

  ## Parameters
  - user: The user to check (User struct or user_id)

  ## Examples
      iex> check_admin_access(admin_user)
      {:ok, :authorized}

      iex> check_admin_access(regular_user)
      {:error, :unauthorized}
  """
  def check_admin_access(%User{} = user), do: check_admin_access(user.id)

  def check_admin_access(user_id) when is_integer(user_id) do
    user_roles = get_user_roles(user_id)

    has_admin =
      Enum.any?(user_roles, fn role ->
        Enum.member?(role.permissions, "admin")
      end)

    if has_admin do
      {:ok, :authorized}
    else
      {:error, :unauthorized}
    end
  end

  @doc """
  Checks if a user has admin access without logging.

  ## Examples
      iex> is_admin?(admin_user)
      true

      iex> is_admin?(regular_user)
      false
  """
  def is_admin?(%User{} = user), do: is_admin?(user.id)

  def is_admin?(user_id) when is_integer(user_id) do
    user_roles = get_user_roles(user_id)

    Enum.any?(user_roles, fn role ->
      Enum.member?(role.permissions, "admin")
    end)
  end

  @doc """
  Checks if a user has a specific role by name.

  ## Parameters
  - user: The user to check (User struct or user_id)
  - role_name: Name of the role to check for

  ## Examples
      iex> has_role?(user, "admin")
      true

      iex> has_role?(user, "nonexistent_role")
      false
  """
  def has_role?(%User{} = user, role_name), do: has_role?(user.id, role_name)

  def has_role?(user_id, role_name) when is_integer(user_id) do
    user_roles = get_user_roles(user_id)

    Enum.any?(user_roles, fn role ->
      role.name == role_name
    end)
  end

  @doc """
  Gets all permissions for a user across all their roles.

  ## Examples
      iex> get_user_permissions(user_id)
      ["read", "write", "delete"]
  """
  def get_user_permissions(user_id) do
    user_id
    |> get_user_roles()
    |> Enum.flat_map(& &1.permissions)
    |> Enum.uniq()
  end

  @doc """
  Lists all users with a specific permission.

  ## Examples
      iex> list_users_with_permission("admin")
      [%User{username: "admin_user"}, ...]
  """
  def list_users_with_permission(permission) do
    query =
      from u in User,
        join: r in Role,
        on: r.user_id == u.id,
        where: ^permission in r.permissions or "admin" in r.permissions,
        distinct: u.id,
        preload: [:roles]

    Repo.all(query)
  end

  @doc """
  Creates a path-based role for accessing specific secret patterns.

  ## Parameters
  - user: User to assign the role to
  - path_pattern: Path pattern (e.g., "api/production/*", "database/*")
  - permissions: List of permissions for this path

  ## Examples
      iex> create_path_role(user, "api/production/*", ["read", "write"])
      {:ok, %Role{name: "path:api/production/*"}}
  """
  def create_path_role(user, path_pattern, permissions) do
    role_name = "path:#{path_pattern}"

    assign_role(user, %{
      name: role_name,
      permissions: permissions
    })
  end

  @doc """
  Lists all users in the system with their roles.

  ## Examples
      iex> list_all_users()
      [%User{username: "admin", roles: [...]}, ...]
  """
  def list_all_users do
    User
    |> User.active_users()
    |> Repo.all()
    |> Repo.preload(:roles)
  end

  @doc """
  Lists all users including inactive ones.

  ## Examples
      iex> list_all_users_including_inactive()
      [%User{username: "admin", active: true}, %User{username: "disabled", active: false}]
  """
  def list_all_users_including_inactive do
    User
    |> Repo.all()
    |> Repo.preload(:roles)
  end

  @doc """
  Gets a user by ID with preloaded roles.

  ## Examples
      iex> get_user_by_id(1)
      %User{id: 1, username: "admin", roles: [...]}

      iex> get_user_by_id(999)
      nil
  """
  def get_user_by_id(user_id) do
    User
    |> Repo.get(user_id)
    |> Repo.preload(:roles)
  end

  @doc """
  Updates a user's information.

  ## Parameters
  - user_id: ID of the user to update
  - attrs: Map of attributes to update
  - updated_by: ID of the user making the change (for audit logging)

  ## Examples
      iex> update_user(1, %{username: "new_username"}, admin_id)
      {:ok, %User{}}

      iex> update_user(1, %{username: ""}, admin_id)
      {:error, %Ecto.Changeset{}}
  """
  def update_user(user_id, attrs, updated_by) do
    case Repo.get(User, user_id) do
      nil ->
        {:error, :user_not_found}

      user ->
        changeset = User.update_changeset(user, attrs)

        case Repo.update(changeset) do
          {:ok, updated_user} ->
            log_auth_action("update_user", updated_by, %{
              updated_user_id: user_id,
              changes: Map.keys(changeset.changes)
            })

            {:ok, updated_user}

          {:error, changeset} ->
            {:error, changeset}
        end
    end
  end

  @doc """
  Deactivates a user account.

  ## Parameters
  - user_id: ID of the user to deactivate
  - deactivated_by: ID of the user performing the deactivation

  ## Examples
      iex> deactivate_user(user_id, admin_id)
      {:ok, %User{active: false}}
  """
  def deactivate_user(user_id, deactivated_by) do
    update_user(user_id, %{active: false}, deactivated_by)
  end

  @doc """
  Reactivates a user account.

  ## Parameters
  - user_id: ID of the user to reactivate
  - reactivated_by: ID of the user performing the reactivation

  ## Examples
      iex> reactivate_user(user_id, admin_id)
      {:ok, %User{active: true}}
  """
  def reactivate_user(user_id, reactivated_by) do
    update_user(user_id, %{active: true}, reactivated_by)
  end

  @doc """
  Changes a user's password.

  ## Parameters
  - user_id: ID of the user
  - new_password: New password
  - changed_by: ID of the user making the change

  ## Examples
      iex> change_user_password(user_id, "new_secure_password", admin_id)
      {:ok, %User{}}
  """
  def change_user_password(user_id, new_password, changed_by) do
    case Repo.get(User, user_id) do
      nil ->
        {:error, :user_not_found}

      user ->
        changeset = User.password_changeset(user, %{password: new_password})

        case Repo.update(changeset) do
          {:ok, updated_user} ->
            log_auth_action("change_password", changed_by, %{
              target_user_id: user_id
            })

            {:ok, updated_user}

          {:error, changeset} ->
            {:error, changeset}
        end
    end
  end

  @doc """
  Lists all unique role names in the system.

  ## Examples
      iex> list_all_role_names()
      ["admin", "read_only", "api_user"]
  """
  def list_all_role_names do
    Role
    |> Repo.all()
    |> Enum.map(& &1.name)
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc """
  Gets all roles with their associated users.

  ## Examples
      iex> list_roles_with_users()
      [%{name: "admin", permissions: ["admin"], users: [%User{}, ...]}, ...]
  """
  def list_roles_with_users do
    Role
    |> Repo.all()
    |> Repo.preload(:user)
    |> Enum.group_by(& &1.name)
    |> Enum.map(fn {name, roles} ->
      %{
        name: name,
        permissions: roles |> List.first() |> Map.get(:permissions, []),
        users: Enum.map(roles, & &1.user),
        user_count: length(roles)
      }
    end)
    |> Enum.sort_by(& &1.name)
  end

  # Private helper functions

  defp has_required_permission?(roles, secret_key, action) do
    required_permission = map_action_to_permission(action)

    Enum.any?(roles, fn role ->
      # Check if user has admin permission (can do anything)
      # Check if user has the required permission and path access
      "admin" in role.permissions or
        (required_permission in role.permissions and has_path_access?(role, secret_key))
    end)
  end

  defp has_path_access?(role, secret_key) do
    cond do
      # If role name doesn't start with "path:", it has access to all secrets
      not String.starts_with?(role.name, "path:") ->
        true

      # Extract path pattern from role name and check match
      String.starts_with?(role.name, "path:") ->
        path_pattern = String.replace_prefix(role.name, "path:", "")
        matches_path_pattern?(secret_key, path_pattern)

      true ->
        false
    end
  end

  defp matches_path_pattern?(secret_key, pattern) do
    cond do
      # Exact match
      secret_key == pattern ->
        true

      # Wildcard pattern matching
      String.ends_with?(pattern, "*") ->
        prefix = String.replace_suffix(pattern, "*", "")
        String.starts_with?(secret_key, prefix)

      # Pattern contains wildcards in the middle
      String.contains?(pattern, "*") ->
        regex_pattern =
          pattern
          |> String.replace("*", ".*")
          |> Regex.compile!()

        Regex.match?(regex_pattern, secret_key)

      true ->
        false
    end
  end

  defp map_action_to_permission("create"), do: "write"
  defp map_action_to_permission("read"), do: "read"
  defp map_action_to_permission("update"), do: "write"
  defp map_action_to_permission("delete"), do: "delete"
  defp map_action_to_permission("list"), do: "read"
  defp map_action_to_permission(_), do: "admin"

  defp log_auth_action(action, user_id, metadata) do
    audit_changeset = AuditLog.log_action(action, "auth_system", user_id, metadata)
    Repo.insert(audit_changeset)
  end

  defp log_access_attempt(user_id, secret_key, action, result) do
    metadata = %{
      action: action,
      result: to_string(result),
      attempted_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }

    audit_changeset = AuditLog.log_action("access_check", secret_key, user_id, metadata)
    Repo.insert(audit_changeset)
  end
end
