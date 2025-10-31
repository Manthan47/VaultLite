defmodule VaultLiteWeb.AuditController do
  @moduledoc """
  Controller for managing audit logs.
  """
  use VaultLiteWeb, :controller

  alias Guardian.Plug
  alias VaultLite.Audit
  alias VaultLite.Auth

  action_fallback VaultLiteWeb.FallbackController

  @doc """
  Get audit logs with filtering options.
  Requires admin permissions.
  GET /api/audit/logs
  """
  def logs(conn, params) do
    user = Plug.current_resource(conn)

    # Check if user has admin permissions
    with {:ok, :authorized} <- Auth.check_admin_access(user) do
      # Parse query parameters
      opts = parse_query_params(params)

      case Audit.get_audit_logs(opts) do
        {:ok, logs} ->
          json(conn, %{
            status: "success",
            data: logs,
            pagination: build_pagination_info(params, length(logs))
          })

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, :unauthorized} ->
        conn
        |> put_status(:forbidden)
        |> json(%{
          status: "error",
          message: "Admin access required"
        })
    end
  end

  @doc """
  Get audit trail for a specific secret.
  Requires read access to the secret.
  GET /api/audit/secrets/:key
  """
  def secret_trail(conn, %{"key" => secret_key} = params) do
    user = Plug.current_resource(conn)

    # Check if user can access this secret
    with {:ok, :authorized} <- Auth.check_access(user, secret_key, "read") do
      opts = parse_query_params(params)

      case Audit.get_secret_audit_trail(secret_key, opts) do
        {:ok, logs} ->
          json(conn, %{
            status: "success",
            data: %{
              secret_key: secret_key,
              audit_trail: logs
            },
            pagination: build_pagination_info(params, length(logs))
          })

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, :unauthorized} ->
        conn
        |> put_status(:forbidden)
        |> json(%{
          status: "error",
          message: "Access denied for secret: #{secret_key}"
        })
    end
  end

  @doc """
  Get audit trail for a specific user.
  Requires admin permissions or user accessing their own logs.
  GET /api/audit/users/:user_id
  """
  def user_trail(conn, %{"user_id" => user_id_str} = params) do
    current_user = Plug.current_resource(conn)

    case Integer.parse(user_id_str) do
      {user_id, ""} ->
        # Check if user is admin or accessing their own logs
        authorized =
          case Auth.check_admin_access(current_user) do
            {:ok, :authorized} -> true
            _ -> current_user.id == user_id
          end

        if authorized do
          opts = parse_query_params(params)

          case Audit.get_user_audit_trail(user_id, opts) do
            {:ok, logs} ->
              json(conn, %{
                status: "success",
                data: %{
                  user_id: user_id,
                  audit_trail: logs
                },
                pagination: build_pagination_info(params, length(logs))
              })

            {:error, reason} ->
              {:error, reason}
          end
        else
          conn
          |> put_status(:forbidden)
          |> json(%{
            status: "error",
            message: "Access denied for user audit trail"
          })
        end

      _ ->
        conn
        |> put_status(:bad_request)
        |> json(%{
          status: "error",
          message: "Invalid user ID"
        })
    end
  end

  @doc """
  Get audit statistics for monitoring and reporting.
  Requires admin permissions.
  GET /api/audit/statistics
  """
  def statistics(conn, params) do
    user = Plug.current_resource(conn)

    with {:ok, :authorized} <- Auth.check_admin_access(user) do
      # Parse date range parameters
      opts = parse_date_range(params)

      case Audit.get_audit_statistics(opts) do
        {:ok, stats} ->
          json(conn, %{
            status: "success",
            data: stats
          })

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, :unauthorized} ->
        conn
        |> put_status(:forbidden)
        |> json(%{
          status: "error",
          message: "Admin access required"
        })
    end
  end

  @doc """
  Purge old audit logs based on retention policy.
  Requires admin permissions.
  DELETE /api/audit/purge
  """
  def purge(conn, params) do
    user = Plug.current_resource(conn)

    with {:ok, :authorized} <- Auth.check_admin_access(user) do
      days_to_keep =
        case Map.get(params, "days_to_keep") do
          nil ->
            365

          days_str when is_binary(days_str) ->
            case Integer.parse(days_str) do
              {days, ""} when days > 0 -> days
              _ -> 365
            end

          days when is_integer(days) and days > 0 ->
            days

          _ ->
            365
        end

      case Audit.purge_old_logs(days_to_keep) do
        {:ok, count} ->
          # Log the purge action
          Audit.log_action(user, "purge", "audit_logs", %{
            days_to_keep: days_to_keep,
            logs_purged: count
          })

          json(conn, %{
            status: "success",
            data: %{
              message: "Successfully purged old audit logs",
              days_to_keep: days_to_keep,
              logs_purged: count
            }
          })

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, :unauthorized} ->
        conn
        |> put_status(:forbidden)
        |> json(%{
          status: "error",
          message: "Admin access required"
        })
    end
  end

  # Private helper functions

  defp parse_query_params(params) do
    []
    |> maybe_add_param(:user_id, params["user_id"])
    |> maybe_add_param(:secret_key, params["secret_key"])
    |> maybe_add_param(:action, params["action"])
    |> maybe_add_param(:limit, params["limit"])
    |> maybe_add_param(:offset, params["offset"])
    |> parse_date_range(params)
  end

  defp parse_date_range(params) when is_map(params) do
    []
    |> maybe_add_date_param(:start_date, params["start_date"])
    |> maybe_add_date_param(:end_date, params["end_date"])
  end

  defp parse_date_range(opts, params) when is_list(opts) and is_map(params) do
    opts
    |> maybe_add_date_param(:start_date, params["start_date"])
    |> maybe_add_date_param(:end_date, params["end_date"])
  end

  defp maybe_add_param(opts, _key, nil), do: opts

  defp maybe_add_param(opts, key, value) when key in [:limit, :offset] do
    case Integer.parse(to_string(value)) do
      {int_value, ""} when int_value >= 0 -> Keyword.put(opts, key, int_value)
      _ -> opts
    end
  end

  defp maybe_add_param(opts, key, value) when is_binary(value) and value != "" do
    case key do
      :user_id ->
        case Integer.parse(value) do
          {user_id, ""} -> Keyword.put(opts, key, user_id)
          _ -> opts
        end

      _ ->
        Keyword.put(opts, key, value)
    end
  end

  defp maybe_add_param(opts, _key, _value), do: opts

  defp maybe_add_date_param(opts, _key, nil), do: opts

  defp maybe_add_date_param(opts, key, date_str) when is_binary(date_str) do
    case DateTime.from_iso8601(date_str) do
      {:ok, datetime, _offset} -> Keyword.put(opts, key, datetime)
      _ -> opts
    end
  end

  defp maybe_add_date_param(opts, _key, _value), do: opts

  defp build_pagination_info(params, count) do
    limit = parse_int_param(params["limit"], 100)
    offset = parse_int_param(params["offset"], 0)
    page = div(offset, limit) + 1

    %{
      page: page,
      limit: limit,
      offset: offset,
      count: count,
      has_more: count == limit
    }
  end

  defp parse_int_param(nil, default), do: default

  defp parse_int_param(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int_value, ""} when int_value >= 0 -> int_value
      _ -> default
    end
  end

  defp parse_int_param(value, _default) when is_integer(value) and value >= 0, do: value
  defp parse_int_param(_value, default), do: default
end
