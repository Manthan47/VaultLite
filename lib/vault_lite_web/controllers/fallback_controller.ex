defmodule VaultLiteWeb.FallbackController do
  use VaultLiteWeb, :controller

  @doc """
  Called when a controller action returns an error tuple
  """
  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> json(%{
      status: "error",
      message: "Resource not found"
    })
  end

  def call(conn, {:error, :unauthorized}) do
    conn
    |> put_status(:unauthorized)
    |> json(%{
      status: "error",
      message: "Access denied"
    })
  end

  def call(conn, {:error, :forbidden}) do
    conn
    |> put_status(:forbidden)
    |> json(%{
      status: "error",
      message: "Insufficient permissions"
    })
  end

  def call(conn, {:error, changeset = %Ecto.Changeset{}}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      status: "error",
      errors: translate_changeset_errors(changeset)
    })
  end

  def call(conn, {:error, reason}) when is_binary(reason) do
    conn
    |> put_status(:bad_request)
    |> json(%{
      status: "error",
      message: reason
    })
  end

  def call(conn, {:error, reason}) do
    conn
    |> put_status(:internal_server_error)
    |> json(%{
      status: "error",
      message: "Internal server error",
      details: inspect(reason)
    })
  end

  defp translate_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
