defmodule VaultLiteWeb.BootstrapController do
  use VaultLiteWeb, :controller

  alias VaultLite.{User, Role, Repo}
  alias Ecto.Changeset

  action_fallback VaultLiteWeb.FallbackController

  @doc """
  Bootstrap endpoint for creating the first admin user.
  This endpoint only works when no users exist in the system.
  """
  def setup(conn, %{"admin" => admin_params}) do
    # Check if any users exist - if they do, bootstrap is not allowed
    case Repo.aggregate(User, :count, :id) do
      0 ->
        create_initial_admin(conn, admin_params)

      _count ->
        conn
        |> put_status(:forbidden)
        |> json(%{
          status: "error",
          message: "Bootstrap setup not allowed - users already exist",
          hint: "Use regular user registration or admin management commands"
        })
    end
  end

  def setup(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{
      status: "error",
      message: "Missing required parameter: admin",
      example: %{
        admin: %{
          username: "admin",
          email: "admin@example.com",
          password: "secure_password"
        }
      }
    })
  end

  @doc """
  Check if the system needs bootstrap setup
  """
  def status(conn, _params) do
    user_count = Repo.aggregate(User, :count, :id)

    case user_count do
      0 ->
        json(conn, %{
          status: "needs_bootstrap",
          message: "No users found. System requires initial admin setup.",
          setup_endpoint: "/api/bootstrap/setup",
          user_count: 0
        })

      count ->
        json(conn, %{
          status: "already_configured",
          message: "System is already configured with users.",
          user_count: count,
          bootstrap_available: false
        })
    end
  end

  defp create_initial_admin(conn, admin_params) do
    # Validate required fields
    required_fields = ["username", "email", "password"]
    missing_fields = Enum.filter(required_fields, &is_nil(admin_params[&1]))

    if not Enum.empty?(missing_fields) do
      conn
      |> put_status(:bad_request)
      |> json(%{
        status: "error",
        message: "Missing required fields",
        missing_fields: missing_fields
      })
    else
      # Create admin user within a transaction
      Repo.transaction(fn ->
        # Create user
        user_attrs = %{
          username: admin_params["username"],
          email: admin_params["email"],
          password: admin_params["password"],
          active: true
        }

        case User.changeset(%User{}, user_attrs) |> Repo.insert() do
          {:ok, user} ->
            # Create admin role
            role_attrs = %{
              name: "bootstrap_admin",
              permissions: ["admin", "read", "write", "delete"],
              path_patterns: ["*"],
              user_id: user.id
            }

            case Role.changeset(%Role{}, role_attrs) |> Repo.insert() do
              {:ok, _role} ->
                # Return success response
                {user, :success}

              {:error, role_changeset} ->
                Repo.rollback({:role_error, role_changeset})
            end

          {:error, user_changeset} ->
            Repo.rollback({:user_error, user_changeset})
        end
      end)
      |> case do
        {:ok, {user, :success}} ->
          conn
          |> put_status(:created)
          |> json(%{
            status: "success",
            message: "Initial admin user created successfully",
            data: %{
              user: %{
                id: user.id,
                username: user.username,
                email: user.email
              },
              next_steps: [
                "Login using POST /api/auth/login",
                "Change the admin password immediately",
                "Create additional users and roles as needed"
              ]
            }
          })

        {:error, {:user_error, changeset}} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{
            status: "error",
            message: "Failed to create admin user",
            errors: translate_changeset_errors(changeset)
          })

        {:error, {:role_error, changeset}} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{
            status: "error",
            message: "Failed to create admin role",
            errors: translate_changeset_errors(changeset)
          })
      end
    end
  end

  defp translate_changeset_errors(changeset) do
    Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
