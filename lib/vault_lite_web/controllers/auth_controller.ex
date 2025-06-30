defmodule VaultLiteWeb.AuthController do
  use VaultLiteWeb, :controller

  alias VaultLite.{User, Repo, Guardian}
  alias Ecto.Changeset
  import VaultLiteWeb.AuthPlug, only: [log_out_user: 1, log_in_user: 2]

  action_fallback VaultLiteWeb.FallbackController

  @doc """
  User registration endpoint
  """
  def register(conn, %{"user" => user_params}) do
    changeset = User.changeset(%User{}, user_params)

    case Repo.insert(changeset) do
      {:ok, user} ->
        {:ok, token, _claims} = Guardian.encode_and_sign(user)

        conn
        |> put_status(:created)
        |> json(%{
          status: "success",
          data: %{
            token: token,
            user: %{
              id: user.id,
              username: user.username,
              email: user.email
            }
          }
        })

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          status: "error",
          errors: Changeset.traverse_errors(changeset, &translate_error/1)
        })
    end
  end

  @doc """
  User login endpoint
  """
  def login(conn, %{"identifier" => identifier, "password" => password}) do
    case Guardian.authenticate_user(identifier, password) do
      {:ok, user, token} ->
        # {:ok, token, _claims} = Guardian.encode_and_sign(user)

        json(conn, %{
          status: "success",
          data: %{
            token: token,
            user: %{
              id: user.id,
              username: user.username,
              email: user.email
            }
          }
        })

      {:error, :invalid_credentials} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{
          status: "error",
          message: "Invalid credentials"
        })
    end
  end

  def login(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{
      status: "error",
      message: "Missing required parameters: identifier and password"
    })
  end

  @doc """
  LiveView login endpoint - handles session-based authentication
  """
  def liveview_login(conn, %{"identifier" => identifier, "password" => password}) do
    case VaultLite.Auth.authenticate_user(identifier, password) do
      {:ok, user} ->
        conn
        |> log_in_user(user)
        |> put_flash(:info, "Welcome back, #{user.username}!")
        |> redirect(to: "/dashboard")

      {:error, :invalid_credentials} ->
        conn
        |> put_flash(:error, "Invalid username/email or password")
        |> redirect(to: "/login")
    end
  end

  @doc """
  User logout endpoint - handles both API and LiveView logout
  """
  def logout(conn, _params) do
    conn = log_out_user(conn)

    case get_format(conn) do
      "json" ->
        json(conn, %{status: "success", message: "Logged out successfully"})

      _ ->
        conn
        |> put_flash(:info, "Logged out successfully.")
        |> redirect(to: "/login")
    end
  end

  defp translate_error({msg, opts}) do
    # Translate error messages if you have gettext configured
    # For now, just return the error message
    if count = opts[:count] do
      Gettext.dngettext(VaultLiteWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(VaultLiteWeb.Gettext, "errors", msg, opts)
    end
  end
end
