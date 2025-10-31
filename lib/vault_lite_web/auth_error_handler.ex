defmodule VaultLiteWeb.AuthErrorHandler do
  @moduledoc """
  Handles authentication errors for VaultLite.
  """
  import Plug.Conn
  import Phoenix.Controller

  @behaviour Guardian.Plug.ErrorHandler

  @impl Guardian.Plug.ErrorHandler
  def auth_error(conn, {type, _reason}, _opts) do
    body = %{error: to_string(type), message: auth_error_message(type)}

    conn
    |> put_status(401)
    |> put_resp_content_type("application/json")
    |> json(body)
  end

  defp auth_error_message(:invalid_token), do: "Invalid authentication token"
  defp auth_error_message(:unauthenticated), do: "Authentication required"
  defp auth_error_message(:no_resource_found), do: "User not found"
  defp auth_error_message(_), do: "Authentication failed"
end
