defmodule VaultLiteWeb.SecretController do
  use VaultLiteWeb, :controller

  alias VaultLite.Secrets
  alias Guardian.Plug

  action_fallback VaultLiteWeb.FallbackController

  @doc """
  Create a new secret
  POST /api/secrets
  """
  def create(conn, %{"key" => key, "value" => value} = params) do
    user = Plug.current_resource(conn)
    metadata = Map.get(params, "metadata", %{})

    case Secrets.create_secret(key, value, user, metadata) do
      {:ok, secret} ->
        conn
        |> put_status(:created)
        |> json(%{
          status: "success",
          data: %{
            key: secret.key,
            version: secret.version,
            metadata: secret.metadata,
            created_at: secret.inserted_at
          }
        })

      {:error, reason} ->
        {:error, reason}
    end
  end

  def create(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{
      status: "error",
      message: "Missing required parameters: key and value"
    })
  end

  @doc """
  Get a secret (latest version by default)
  GET /api/secrets/:key
  """
  def show(conn, %{"key" => key}) do
    user = Plug.current_resource(conn)

    case Secrets.get_secret(key, user) do
      {:ok, secret} ->
        json(conn, %{
          status: "success",
          data: %{
            key: secret.key,
            value: secret.value,
            version: secret.version,
            metadata: secret.metadata,
            created_at: secret.inserted_at,
            updated_at: secret.updated_at
          }
        })

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get a specific version of a secret
  GET /api/secrets/:key/versions/:version
  """
  def show_version(conn, %{"key" => key, "version" => version_str}) do
    user = Plug.current_resource(conn)

    case Integer.parse(version_str) do
      {version, ""} when version > 0 ->
        case Secrets.get_secret(key, user, version) do
          {:ok, secret} ->
            json(conn, %{
              status: "success",
              data: %{
                key: secret.key,
                value: secret.value,
                version: secret.version,
                metadata: secret.metadata,
                created_at: secret.inserted_at,
                updated_at: secret.updated_at
              }
            })

          {:error, reason} ->
            {:error, reason}
        end

      _ ->
        conn
        |> put_status(:bad_request)
        |> json(%{
          status: "error",
          message: "Invalid version number"
        })
    end
  end

  @doc """
  Update a secret (creates new version)
  PUT /api/secrets/:key
  """
  def update(conn, %{"key" => key, "value" => value} = params) do
    user = Plug.current_resource(conn)
    metadata = Map.get(params, "metadata", %{})

    case Secrets.update_secret(key, value, user, metadata) do
      {:ok, secret} ->
        json(conn, %{
          status: "success",
          data: %{
            key: secret.key,
            version: secret.version,
            metadata: secret.metadata,
            updated_at: secret.inserted_at
          }
        })

      {:error, reason} ->
        {:error, reason}
    end
  end

  def update(conn, %{"key" => _key}) do
    conn
    |> put_status(:bad_request)
    |> json(%{
      status: "error",
      message: "Missing required parameter: value"
    })
  end

  @doc """
  Delete a secret (soft delete all versions)
  DELETE /api/secrets/:key
  """
  def delete(conn, %{"key" => key}) do
    user = Plug.current_resource(conn)

    case Secrets.delete_secret(key, user) do
      {:ok, _} ->
        conn
        |> put_status(:no_content)
        |> json(%{
          status: "success",
          message: "Secret deleted successfully"
        })

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  List all accessible secrets
  GET /api/secrets
  """
  def index(conn, params) do
    user = Plug.current_resource(conn)
    page = Map.get(params, "page", "1") |> String.to_integer()
    limit = Map.get(params, "limit", "20") |> String.to_integer()
    offset = (page - 1) * limit

    {:ok, secrets} = Secrets.list_secrets(user, limit: limit, offset: offset)

    json(conn, %{
      status: "success",
      data: secrets,
      pagination: %{
        page: page,
        limit: limit,
        count: length(secrets)
      }
    })
  end

  @doc """
  Get all versions of a secret
  GET /api/secrets/:key/versions
  """
  def versions(conn, %{"key" => key}) do
    user = Plug.current_resource(conn)

    case Secrets.get_secret_versions(key, user) do
      {:ok, versions} ->
        json(conn, %{
          status: "success",
          data: versions
        })

      {:error, reason} ->
        {:error, reason}
    end
  end
end
