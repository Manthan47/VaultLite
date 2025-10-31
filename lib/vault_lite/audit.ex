defmodule VaultLite.Audit do
  @moduledoc """
  Context module for audit logging in VaultLite.

  Provides functions to log all secret operations for auditability and compliance.
  Supports both database storage and optional external logging systems.
  """
  import Ecto.Query

  alias VaultLite.AuditLog
  alias VaultLite.Repo
  alias VaultLite.User

  require Logger

  @doc """
  Logs an action performed on a secret.

  ## Parameters
  - `user`: The user performing the action (can be User struct or user_id)
  - `action`: The action performed (create, read, update, delete, list)
  - `secret_key`: The key of the secret being accessed
  - `metadata`: Optional additional context (default: %{})

  ## Examples
      iex> log_action(user, "create", "api_key", %{version: 1})
      {:ok, %AuditLog{}}

      iex> log_action(123, "read", "database_password")
      {:ok, %AuditLog{}}
  """
  def log_action(user, action, secret_key, metadata \\ %{})

  def log_action(%User{id: user_id}, action, secret_key, metadata) do
    log_action(user_id, action, secret_key, metadata)
  end

  def log_action(user_id, action, secret_key, metadata) when is_integer(user_id) do
    # Enhance metadata with additional context
    enhanced_metadata =
      metadata
      |> Map.put(:logged_at, DateTime.utc_now())
      |> Map.put(:application, "vault_lite")

    # Create audit log changeset
    changeset = AuditLog.log_action(action, secret_key, user_id, enhanced_metadata)

    # Store in database
    case Repo.insert(changeset) do
      {:ok, audit_log} = result ->
        # Log to application logger
        log_to_application_logger(audit_log)

        # Send to external logging if configured
        send_to_external_logging(audit_log)

        result

      {:error, changeset} = error ->
        dbg(changeset)
        Logger.error("Failed to create audit log: #{inspect(changeset.errors)}")
        error
    end
  end

  def log_action(nil, action, secret_key, metadata) do
    # For system operations without a specific user
    log_action(:system, action, secret_key, metadata)
  end

  def log_action(:system, action, secret_key, metadata) do
    enhanced_metadata =
      metadata
      |> Map.put(:logged_at, DateTime.utc_now())
      |> Map.put(:application, "vault_lite")
      |> Map.put(:user_type, "system")

    changeset = AuditLog.log_action(action, secret_key, nil, enhanced_metadata)

    case Repo.insert(changeset) do
      {:ok, audit_log} = result ->
        log_to_application_logger(audit_log)
        send_to_external_logging(audit_log)
        result

      {:error, changeset} = error ->
        Logger.error("Failed to create system audit log: #{inspect(changeset.errors)}")
        error
    end
  end

  @doc """
  Retrieves audit logs with various filtering options.

  ## Options
  - `:user_id` - Filter by user ID
  - `:secret_key` - Filter by exact secret key match
  - `:secret_key_contains` - Filter by secret keys containing the given string
  - `:action` - Filter by action type
  - `:start_date` - Filter by start date
  - `:end_date` - Filter by end date
  - `:limit` - Limit number of results (default: 100)
  - `:offset` - Offset for pagination (default: 0)

  ## Examples
      iex> get_audit_logs(user_id: 123, limit: 50)
      {:ok, [%AuditLog{}, ...]}

      iex> get_audit_logs(secret_key: "api_key", action: "read")
      {:ok, [%AuditLog{}, ...]}

      iex> get_audit_logs(secret_key_contains: "password")
      {:ok, [%AuditLog{}, ...]}
  """
  def get_audit_logs(opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    offset = Keyword.get(opts, :offset, 0)

    query =
      AuditLog
      |> AuditLog.recent_first()
      |> limit(^limit)
      |> offset(^offset)
      |> apply_filters(opts)

    logs = Repo.all(query)
    {:ok, logs}
  rescue
    e ->
      Logger.error("Failed to retrieve audit logs: #{inspect(e)}")
      {:error, :database_error}
  end

  @doc """
  Gets audit logs for a specific secret key.
  """
  def get_secret_audit_trail(secret_key, opts \\ []) do
    opts = Keyword.put(opts, :secret_key, secret_key)
    get_audit_logs(opts)
  end

  @doc """
  Gets audit logs for a specific user.
  """
  def get_user_audit_trail(user_id, opts \\ []) do
    opts = Keyword.put(opts, :user_id, user_id)
    get_audit_logs(opts)
  end

  @doc """
  Gets audit statistics for reporting and monitoring.

  ## Examples
      iex> get_audit_statistics()
      {:ok, %{
        total_logs: 1250,
        actions: %{"create" => 300, "read" => 800, "update" => 100, "delete" => 50},
        top_secrets: [%{secret_key: "api_key", access_count: 150}, %{secret_key: "db_password", access_count: 120}],
        active_users: 45
      }}
  """
  def get_audit_statistics(opts \\ []) do
    start_date = Keyword.get(opts, :start_date)
    end_date = Keyword.get(opts, :end_date)

    base_query = build_date_filtered_query(start_date, end_date)

    stats = %{
      total_logs: get_total_logs(base_query),
      actions: get_action_counts(base_query),
      top_secrets: get_top_secrets(base_query),
      active_users: get_active_users(base_query)
    }

    {:ok, stats}
  rescue
    e ->
      Logger.error("Failed to get audit statistics: #{inspect(e)}")
      {:error, :database_error}
  end

  @doc """
  Purges old audit logs based on retention policy.

  ## Parameters
  - `days_to_keep`: Number of days of logs to retain (default: 365)

  ## Examples
      iex> purge_old_logs(90)
      {:ok, 150}  # 150 logs deleted
  """
  def purge_old_logs(days_to_keep \\ 365) do
    cutoff_date =
      DateTime.utc_now()
      |> DateTime.add(-days_to_keep, :day)
      |> DateTime.truncate(:second)

    {count, _} =
      from(a in AuditLog, where: a.timestamp < ^cutoff_date)
      |> Repo.delete_all()

    Logger.info("Purged #{count} audit logs older than #{days_to_keep} days")
    {:ok, count}
  rescue
    e ->
      Logger.error("Failed to purge old audit logs: #{inspect(e)}")
      {:error, :database_error}
  end

  # Private helper functions

  defp apply_filters(query, opts) do
    Enum.reduce(opts, query, fn
      {:user_id, user_id}, acc ->
        AuditLog.for_user(acc, user_id)

      {:secret_key, secret_key}, acc ->
        AuditLog.for_secret(acc, secret_key)

      {:secret_key_contains, search_term}, acc ->
        from a in acc, where: like(a.secret_key, ^"%#{search_term}%")

      {:action, action}, acc ->
        AuditLog.for_action(acc, action)

      {:start_date, start_date}, acc ->
        from a in acc, where: a.timestamp >= ^start_date

      {:end_date, end_date}, acc ->
        from a in acc, where: a.timestamp <= ^end_date

      {:metadata_key, {key, value}}, acc ->
        AuditLog.with_metadata(acc, key, value)

      _, acc ->
        acc
    end)
  end

  defp build_date_filtered_query(nil, nil), do: AuditLog

  defp build_date_filtered_query(start_date, nil) do
    from a in AuditLog, where: a.timestamp >= ^start_date
  end

  defp build_date_filtered_query(nil, end_date) do
    from a in AuditLog, where: a.timestamp <= ^end_date
  end

  defp build_date_filtered_query(start_date, end_date) do
    AuditLog.between_dates(AuditLog, start_date, end_date)
  end

  defp get_total_logs(query) do
    Repo.aggregate(query, :count, :id)
  end

  defp get_action_counts(query) do
    query
    |> group_by([a], a.action)
    |> select([a], {a.action, count(a.id)})
    |> Repo.all()
    |> Enum.into(%{})
  end

  defp get_top_secrets(query, limit \\ 10) do
    query
    |> group_by([a], a.secret_key)
    |> select([a], {a.secret_key, count(a.id)})
    |> order_by([a], desc: count(a.id))
    |> limit(^limit)
    |> Repo.all()
    |> Enum.map(fn {secret_key, count} ->
      %{secret_key: secret_key, access_count: count}
    end)
  end

  defp get_active_users(query) do
    query
    |> where([a], not is_nil(a.user_id))
    |> distinct([a], a.user_id)
    |> Repo.aggregate(:count, :user_id)
  end

  defp log_to_application_logger(audit_log) do
    user_info = if audit_log.user_id, do: "user_id=#{audit_log.user_id}", else: "system"

    Logger.info("AUDIT: #{user_info} action=#{audit_log.action} secret=#{audit_log.secret_key}",
      audit_log_id: audit_log.id,
      user_id: audit_log.user_id,
      action: audit_log.action,
      secret_key: audit_log.secret_key,
      timestamp: audit_log.timestamp,
      metadata: audit_log.metadata
    )
  end

  defp send_to_external_logging(audit_log) do
    # Check if external logging is configured
    case Application.get_env(:vault_lite, :external_logging) do
      %{enabled: true} = config ->
        case config[:provider] do
          :sentry -> send_to_sentry(audit_log, config)
          :datadog -> send_to_datadog(audit_log, config)
          :elastic -> send_to_elasticsearch(audit_log, config)
          _ -> :ok
        end

      _ ->
        :ok
    end
  rescue
    e ->
      Logger.warning("Failed to send audit log to external service: #{inspect(e)}")
      :ok
  end

  defp send_to_sentry(audit_log, _config) do
    # Placeholder for Sentry integration
    # In a real implementation, you would use Sentry.capture_message/2
    Logger.debug("Would send audit log #{audit_log.id} to Sentry")

    # Example Sentry integration:
    # Sentry.capture_message("Audit Log",
    #   level: :info,
    #   tags: %{action: audit_log.action, secret_key: audit_log.secret_key},
    #   extra: %{
    #     audit_log_id: audit_log.id,
    #     user_id: audit_log.user_id,
    #     timestamp: audit_log.timestamp,
    #     metadata: audit_log.metadata
    #   }
    # )
  end

  defp send_to_datadog(audit_log, _config) do
    # Placeholder for DataDog integration
    Logger.debug("Would send audit log #{audit_log.id} to DataDog")
  end

  defp send_to_elasticsearch(audit_log, _config) do
    # Placeholder for Elasticsearch integration
    Logger.debug("Would send audit log #{audit_log.id} to Elasticsearch")
  end
end
