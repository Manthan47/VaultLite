defmodule VaultLiteWeb.RoleController do
  @moduledoc """
  Controller for managing roles and role assignments.
  """
  use VaultLiteWeb, :controller

  alias Guardian.Plug
  alias VaultLite.Auth
  alias VaultLite.Role
  alias VaultLite.Repo

  action_fallback VaultLiteWeb.FallbackController

  @doc """
  Create a new role
  POST /api/roles
  """
  def create(conn, %{"role" => role_params}) do
    user = Plug.current_resource(conn)

    # Check if user has admin permission to create roles
    case Auth.can_access?(user, "*", "admin") do
      true ->
        changeset = Role.changeset(%Role{}, role_params)

        case Repo.insert(changeset) do
          {:ok, role} ->
            conn
            |> put_status(:created)
            |> json(%{
              status: "success",
              data: %{
                id: role.id,
                name: role.name,
                permissions: role.permissions,
                path_patterns: role.path_patterns,
                user_id: role.user_id,
                created_at: role.inserted_at
              }
            })

          {:error, changeset} ->
            {:error, changeset}
        end

      false ->
        {:error, :forbidden}
    end
  end

  def create(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{
      status: "error",
      message: "Missing required parameter: role"
    })
  end

  @doc """
  Assign a role to a user
  POST /api/roles/assign
  """
  def assign(conn, %{"user_id" => user_id, "role_data" => role_data}) do
    current_user = Plug.current_resource(conn)

    # Check if current user has admin permission
    case Auth.can_access?(current_user, "*", "admin") do
      true ->
        case Auth.assign_role(user_id, role_data) do
          {:ok, role} ->
            json(conn, %{
              status: "success",
              data: %{
                id: role.id,
                name: role.name,
                permissions: role.permissions,
                # path_patterns: role.path_patterns,
                user_id: role.user_id,
                created_at: role.inserted_at
              }
            })

          {:error, reason} ->
            {:error, reason}
        end

      false ->
        {:error, :forbidden}
    end
  end

  def assign(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{
      status: "error",
      message: "Missing required parameters: user_id and role_data"
    })
  end

  @doc """
  List all roles (admin only)
  GET /api/roles
  """
  def index(conn, _params) do
    user = Plug.current_resource(conn)

    # Check if user has admin permission
    case Auth.can_access?(user, "*", "admin") do
      true ->
        roles =
          Role
          |> Repo.all()
          |> Repo.preload(:user)

        json(conn, %{
          status: "success",
          data:
            Enum.map(roles, fn role ->
              %{
                id: role.id,
                name: role.name,
                permissions: role.permissions,
                path_patterns: role.path_patterns,
                user_id: role.user_id,
                user:
                  if(role.user,
                    do: %{
                      id: role.user.id,
                      username: role.user.username,
                      email: role.user.email
                    }
                  ),
                created_at: role.inserted_at
              }
            end)
        })

      false ->
        {:error, :forbidden}
    end
  end

  @doc """
  Get a specific role (admin only)
  GET /api/roles/:id
  """
  def show(conn, %{"id" => id}) do
    user = Plug.current_resource(conn)

    # Check if user has admin permission
    case Auth.can_access?(user, "*", "admin") do
      true ->
        case Repo.get(Role, id) |> Repo.preload(:user) do
          nil ->
            {:error, :not_found}

          role ->
            json(conn, %{
              status: "success",
              data: %{
                id: role.id,
                name: role.name,
                permissions: role.permissions,
                path_patterns: role.path_patterns,
                user_id: role.user_id,
                user:
                  if(role.user,
                    do: %{
                      id: role.user.id,
                      username: role.user.username,
                      email: role.user.email
                    }
                  ),
                created_at: role.inserted_at
              }
            })
        end

      false ->
        {:error, :forbidden}
    end
  end
end
