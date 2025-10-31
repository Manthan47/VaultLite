defmodule VaultLite.Security.Monitor do
  @moduledoc """
  Security monitoring and alerting system for VaultLite.

  This module provides:
  - Security event monitoring
  - Automatic alerting for suspicious activities
  - Security metrics collection
  - Integration with external monitoring systems
  """
  use GenServer

  require Logger

  import Ecto.Query

  alias VaultLite.Audit
  alias VaultLite.Schema.AuditLog
  alias VaultLite.Repo

  @doc """
  Starts the security monitor.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Reports a security event for monitoring.
  """
  def report_security_event(event_type, metadata \\ %{}) do
    GenServer.cast(__MODULE__, {:security_event, event_type, metadata})
  end

  @doc """
  Gets security metrics for the specified time period.
  """
  def get_security_metrics(hours_back \\ 24) do
    GenServer.call(__MODULE__, {:get_metrics, hours_back})
  end

  @doc """
  Checks if any security alerts are active.
  """
  def get_active_alerts do
    GenServer.call(__MODULE__, :get_active_alerts)
  end

  # GenServer implementation

  @impl true
  def init(_opts) do
    # Schedule periodic security checks
    schedule_security_check()

    state = %{
      security_events: [],
      active_alerts: [],
      metrics: %{},
      last_check: DateTime.utc_now()
    }

    {:ok, state}
  end

  @impl true
  def handle_cast({:security_event, event_type, metadata}, state) do
    event = %{
      type: event_type,
      metadata: metadata,
      timestamp: DateTime.utc_now()
    }

    # Log the security event
    log_security_event(event)

    # Check if this triggers any alerts
    new_alerts = check_for_alerts(event, state.active_alerts)

    # Update metrics
    updated_metrics = update_security_metrics(state.metrics, event)

    new_state = %{
      state
      | security_events: [event | Enum.take(state.security_events, 999)],
        active_alerts: new_alerts,
        metrics: updated_metrics
    }

    {:noreply, new_state}
  end

  @impl true
  def handle_call({:get_metrics, hours_back}, _from, state) do
    since = DateTime.add(DateTime.utc_now(), -hours_back * 3600, :second)
    metrics = calculate_security_metrics(since)
    {:reply, metrics, state}
  end

  @impl true
  def handle_call(:get_active_alerts, _from, state) do
    {:reply, state.active_alerts, state}
  end

  @impl true
  def handle_info(:security_check, state) do
    # Perform periodic security checks
    new_state = perform_security_check(state)

    # Schedule next check
    schedule_security_check()

    {:noreply, new_state}
  end

  # Private functions

  defp schedule_security_check do
    # Check every 5 minutes
    Process.send_after(self(), :security_check, 5 * 60 * 1000)
  end

  defp log_security_event(event) do
    Logger.warning("Security event detected",
      type: event.type,
      metadata: event.metadata,
      timestamp: event.timestamp
    )

    # Also log to audit system
    Audit.log_action(nil, "security_event", "system", %{
      event_type: event.type,
      metadata: event.metadata
    })
  end

  defp check_for_alerts(event, current_alerts) do
    new_alert =
      case event.type do
        :failed_login_burst ->
          check_failed_login_burst(event.metadata)

        :suspicious_ip_activity ->
          check_suspicious_ip(event.metadata)

        :admin_action ->
          check_admin_action(event.metadata)

        :bulk_operation ->
          check_bulk_operation(event.metadata)

        :injection_attempt ->
          check_injection_attempt(event.metadata)

        :rate_limit_exceeded ->
          check_rate_limit_pattern(event.metadata)

        _ ->
          nil
      end

    if new_alert do
      send_alert(new_alert)
      [new_alert | current_alerts]
    else
      current_alerts
    end
    |> Enum.reject(&alert_expired?/1)
  end

  defp check_failed_login_burst(metadata) do
    ip = metadata[:ip]

    if ip do
      # 3 minutes
      recent_failures = count_recent_failed_logins(ip, 3)

      if recent_failures >= get_config(:failed_login_alert_threshold, 5) do
        %{
          type: :failed_login_burst,
          severity: :high,
          ip: ip,
          count: recent_failures,
          created_at: DateTime.utc_now(),
          # 1 hour
          expires_at: DateTime.add(DateTime.utc_now(), 3600)
        }
      end
    end
  end

  defp check_suspicious_ip(metadata) do
    ip = metadata[:ip]

    if ip do
      %{
        type: :suspicious_ip,
        severity: :medium,
        ip: ip,
        activities: metadata[:activities] || [],
        created_at: DateTime.utc_now(),
        # 2 hours
        expires_at: DateTime.add(DateTime.utc_now(), 7200)
      }
    end
  end

  defp check_admin_action(metadata) do
    if get_config(:alert_on_admin_actions, true) do
      %{
        type: :admin_action,
        severity: :medium,
        user_id: metadata[:user_id],
        action: metadata[:action],
        created_at: DateTime.utc_now(),
        # 30 minutes
        expires_at: DateTime.add(DateTime.utc_now(), 1800)
      }
    end
  end

  defp check_bulk_operation(metadata) do
    if get_config(:alert_on_bulk_operations, true) do
      operation_count = metadata[:count] || 0

      if operation_count >= get_config(:bulk_operation_threshold, 10) do
        %{
          type: :bulk_operation,
          severity: :medium,
          user_id: metadata[:user_id],
          operation: metadata[:operation],
          count: operation_count,
          created_at: DateTime.utc_now(),
          # 1 hour
          expires_at: DateTime.add(DateTime.utc_now(), 3600)
        }
      end
    end
  end

  defp check_injection_attempt(metadata) do
    %{
      type: :injection_attempt,
      severity: :high,
      ip: metadata[:ip],
      pattern: metadata[:pattern],
      payload: metadata[:payload],
      created_at: DateTime.utc_now(),
      # 2 hours
      expires_at: DateTime.add(DateTime.utc_now(), 7200)
    }
  end

  defp check_rate_limit_pattern(metadata) do
    ip = metadata[:ip]

    if ip do
      # 1 hour
      rate_limit_count = count_recent_rate_limits(ip, 60)

      if rate_limit_count >= get_config(:rate_limit_alert_threshold, 3) do
        %{
          type: :persistent_rate_limiting,
          severity: :medium,
          ip: ip,
          count: rate_limit_count,
          created_at: DateTime.utc_now(),
          # 1 hour
          expires_at: DateTime.add(DateTime.utc_now(), 3600)
        }
      end
    end
  end

  defp alert_expired?(alert) do
    DateTime.compare(DateTime.utc_now(), alert.expires_at) == :gt
  end

  defp send_alert(alert) do
    Logger.error("Security alert triggered",
      type: alert.type,
      severity: alert.severity,
      details: Map.drop(alert, [:type, :severity])
    )

    # Send to external monitoring if configured
    send_to_external_monitoring(alert)

    # Send email/SMS alerts if configured
    send_notification_alert(alert)
  end

  defp send_to_external_monitoring(alert) do
    case get_config(:external_monitoring) do
      %{enabled: true, provider: :sentry} = config ->
        send_to_sentry(alert, config)

      %{enabled: true, provider: :datadog} = config ->
        send_to_datadog(alert, config)

      _ ->
        :ok
    end
  end

  defp send_to_sentry(alert, _config) do
    # Placeholder for Sentry integration
    Logger.debug("Would send alert to Sentry: #{inspect(alert)}")
  end

  defp send_to_datadog(alert, _config) do
    # Placeholder for DataDog integration
    Logger.debug("Would send alert to DataDog: #{inspect(alert)}")
  end

  defp send_notification_alert(alert) do
    if alert.severity in [:high, :critical] do
      # Send immediate notifications for high severity alerts
      send_email_alert(alert)
      send_slack_alert(alert)
    end
  end

  defp send_email_alert(alert) do
    # Placeholder for email alerting
    Logger.debug("Would send email alert: #{inspect(alert)}")
  end

  defp send_slack_alert(alert) do
    # Placeholder for Slack alerting
    Logger.debug("Would send Slack alert: #{inspect(alert)}")
  end

  defp update_security_metrics(metrics, event) do
    event_key = event.type
    current_count = Map.get(metrics, event_key, 0)
    Map.put(metrics, event_key, current_count + 1)
  end

  defp perform_security_check(state) do
    # Check for anomalous patterns in recent audit logs
    anomalies = detect_anomalies()

    # Update state with any new findings
    Enum.reduce(anomalies, state, fn anomaly, acc_state ->
      handle_cast({:security_event, anomaly.type, anomaly.metadata}, acc_state)
      # Extract the state from {:noreply, state}
      |> elem(1)
    end)
  end

  defp detect_anomalies do
    # 5 minutes
    since = DateTime.add(DateTime.utc_now(), -300)

    [
      detect_unusual_access_patterns(since),
      detect_bulk_operations(since),
      detect_after_hours_activity(since),
      detect_geographic_anomalies(since)
    ]
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
  end

  defp detect_unusual_access_patterns(_since) do
    # Check for unusual secret access patterns
    # This is a simplified implementation
    []
  end

  defp detect_bulk_operations(since) do
    # Check for bulk secret operations by single users
    query = """
    SELECT user_id, action, COUNT(*) as count
    FROM audit_logs
    WHERE timestamp >= $1 AND action IN ('create', 'update', 'delete')
    GROUP BY user_id, action
    HAVING COUNT(*) >= $2
    """

    threshold = get_config(:bulk_operation_detection_threshold, 20)

    case Repo.query(query, [since, threshold]) do
      {:ok, %{rows: rows}} ->
        Enum.map(rows, fn [user_id, action, count] ->
          %{
            type: :bulk_operation,
            metadata: %{
              user_id: user_id,
              action: action,
              count: count,
              timeframe: "5 minutes"
            }
          }
        end)

      _ ->
        []
    end
  end

  defp detect_after_hours_activity(since) do
    # Check for activity during configured off-hours
    current_hour = DateTime.utc_now().hour
    # 10 PM
    off_hours_start = get_config(:off_hours_start, 22)
    # 6 AM
    off_hours_end = get_config(:off_hours_end, 6)

    if is_off_hours?(current_hour, off_hours_start, off_hours_end) do
      # Check for any admin or high-privilege activity
      query = """
      SELECT DISTINCT user_id, action, secret_key
      FROM audit_logs
      WHERE timestamp >= $1 AND action IN ('delete', 'assign_role', 'purge_logs')
      """

      case Repo.query(query, [since]) do
        {:ok, %{rows: [_ | _] = rows}} ->
          [
            %{
              type: :after_hours_activity,
              metadata: %{
                activities: length(rows),
                hour: current_hour
              }
            }
          ]

        _ ->
          []
      end
    else
      []
    end
  end

  defp detect_geographic_anomalies(_since) do
    # Placeholder for geographic anomaly detection
    # Would require IP geolocation and user location tracking
    []
  end

  defp is_off_hours?(current_hour, start_hour, end_hour) when start_hour > end_hour do
    # Overnight period (e.g., 22:00 to 06:00)
    current_hour >= start_hour || current_hour <= end_hour
  end

  defp is_off_hours?(current_hour, start_hour, end_hour) do
    # Same day period
    current_hour >= start_hour && current_hour <= end_hour
  end

  defp calculate_security_metrics(since) do
    %{
      failed_logins: count_events_since("failed_authentication", since),
      successful_logins: count_events_since("authenticate", since),
      secret_accesses: count_events_since("read", since),
      secret_modifications: count_events_since(["create", "update", "delete"], since),
      admin_actions: count_admin_actions_since(since),
      rate_limit_violations: count_rate_limit_violations_since(since),
      unique_ips: count_unique_ips_since(since),
      security_events: count_security_events_since(since)
    }
  end

  defp count_events_since(action, since) when is_binary(action) do
    from(a in AuditLog,
      where: a.action == ^action and a.timestamp >= ^since
    )
    |> Repo.aggregate(:count, :id)
  end

  defp count_events_since(actions, since) when is_list(actions) do
    from(a in AuditLog,
      where: a.action in ^actions and a.timestamp >= ^since
    )
    |> Repo.aggregate(:count, :id)
  end

  defp count_admin_actions_since(since) do
    admin_actions = ["assign_role", "revoke_role", "purge_logs", "create_user"]
    count_events_since(admin_actions, since)
  end

  defp count_rate_limit_violations_since(since) do
    from(a in AuditLog,
      where:
        fragment("?->>'event_type' = ?", a.metadata, "rate_limit_exceeded") and
          a.timestamp >= ^since
    )
    |> Repo.aggregate(:count, :id)
  end

  defp count_unique_ips_since(since) do
    query = """
    SELECT COUNT(DISTINCT metadata->>'ip')
    FROM audit_logs
    WHERE timestamp >= $1 AND metadata->>'ip' IS NOT NULL
    """

    case Repo.query(query, [since]) do
      {:ok, %{rows: [[count]]}} -> count || 0
      _ -> 0
    end
  end

  defp count_security_events_since(since) do
    from(a in AuditLog,
      where: a.action == "security_event" and a.timestamp >= ^since
    )
    |> Repo.aggregate(:count, :id)
  end

  defp count_recent_failed_logins(ip, minutes) do
    since = DateTime.add(DateTime.utc_now(), -minutes * 60)

    from(a in AuditLog,
      where:
        a.action == "failed_authentication" and a.timestamp >= ^since and
          fragment("?->>'ip' = ?", a.metadata, ^ip)
    )
    |> Repo.aggregate(:count, :id)
  end

  defp count_recent_rate_limits(ip, minutes) do
    since = DateTime.add(DateTime.utc_now(), -minutes * 60)

    from(a in AuditLog,
      where:
        a.action == "security_event" and a.timestamp >= ^since and
          fragment("?->>'event_type' = ?", a.metadata, "rate_limit_exceeded") and
          fragment("?->>'ip' = ?", a.metadata, ^ip)
    )
    |> Repo.aggregate(:count, :id)
  end

  defp get_config(key, default \\ nil) do
    :vault_lite
    |> Application.get_env(:security, [])
    |> Keyword.get(:monitoring, [])
    |> Keyword.get(key, default)
  end
end
