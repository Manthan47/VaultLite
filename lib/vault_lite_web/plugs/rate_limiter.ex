defmodule VaultLiteWeb.Plugs.RateLimiter do
  @moduledoc """
  Enhanced rate limiting with user-based and adaptive throttling capabilities.

  Features:
  - IP-based rate limiting
  - User-based rate limiting
  - Adaptive throttling based on system load
  - Security event monitoring
  - Automatic IP blocking for abuse
  """

  import Plug.Conn

  require Logger

  @scanner_patterns [
    # Path traversal
    ~r/\.\./,
    # SQL injection
    ~r/\bselect\b.*\bfrom\b/i,
    # XSS attempts
    ~r/<script/i,
    # Bot detection
    ~r/bot|crawler|spider/i
  ]

  @injection_patterns [
    # SQL injection
    ~r/['"]\s*(or|and)\s*['"]/i,
    # XSS
    ~r/<script|javascript:/i,
    # Path traversal
    ~r/\.\./,
    # Null byte injection
    ~r/\x00/
  ]

  @doc """
  Initializes the plug with configuration options.
  """
  def init(opts), do: opts

  @doc """
  Enhanced rate limiting check that considers both IP and user.
  """
  def call(conn, _opts) do
    conn
    |> check_ip_reputation()
    |> check_user_rate_limits()
    |> check_endpoint_specific_limits()
    |> monitor_security_events()
  end

  # Check IP reputation and apply blocking if needed
  defp check_ip_reputation(conn) do
    ip = get_client_ip(conn)

    case get_ip_status(ip) do
      :blocked ->
        conn
        |> send_rate_limit_response("IP temporarily blocked due to abuse")
        |> halt()

      :suspicious ->
        # Reduce rate limits for suspicious IPs
        apply_reduced_limits(conn, ip)

      :normal ->
        conn
    end
  end

  # Check user-specific rate limits
  defp check_user_rate_limits(conn) do
    case get_current_user(conn) do
      nil ->
        # No user context, rely on IP-based limiting
        conn

      user ->
        # Apply user-based rate limiting
        check_user_limits(conn, user)
    end
  end

  # Check endpoint-specific rate limits
  defp check_endpoint_specific_limits(conn) do
    endpoint = get_endpoint_key(conn)
    limits = get_endpoint_limits(endpoint)

    if limits do
      apply_endpoint_limits(conn, endpoint, limits)
    else
      conn
    end
  end

  # Monitor security events and adapt limits
  defp monitor_security_events(conn) do
    case detect_security_events(conn) do
      :normal ->
        conn

      :potential_attack ->
        log_security_event(conn, "Potential attack detected")
        apply_emergency_limits(conn)

      :confirmed_attack ->
        log_security_event(conn, "Attack confirmed")
        block_ip_temporarily(conn)
    end
  end

  # Helper functions

  defp get_client_ip(conn) do
    case get_req_header(conn, "x-forwarded-for") do
      [forwarded_ip | _] ->
        forwarded_ip
        |> String.split(",")
        |> List.first()
        |> String.trim()

      [] ->
        case conn.remote_ip do
          {a, b, c, d} ->
            "#{a}.#{b}.#{c}.#{d}"

          {a, b, c, d, e, f, g, h} ->
            "#{a}:#{b}:#{c}:#{d}:#{e}:#{f}:#{g}:#{h}"
            ## TODO: Check on this
            # ip -> to_string(ip)
        end
    end
  end

  defp get_current_user(conn) do
    Guardian.Plug.current_resource(conn)
  rescue
    _ -> nil
  end

  defp get_ip_status(ip) do
    cache_key = "ip_status:#{ip}"

    case :ets.lookup(:rate_limit_cache, cache_key) do
      [{^cache_key, status, timestamp}] ->
        # 1 hour cache
        if System.system_time(:second) - timestamp < 3600 do
          status
        else
          :normal
        end

      [] ->
        # Check recent failure count
        failure_count = get_ip_failure_count(ip)

        cond do
          failure_count >= get_config(:block_threshold, 10) -> :blocked
          failure_count >= get_config(:suspicious_threshold, 5) -> :suspicious
          true -> :normal
        end
    end
  end

  defp get_ip_failure_count(ip) do
    # Count recent failed requests from this IP
    cache_key = "ip_failures:#{ip}"

    case :ets.lookup(:rate_limit_cache, cache_key) do
      [{^cache_key, count, _timestamp}] -> count
      [] -> 0
    end
  end

  defp apply_reduced_limits(conn, ip) do
    # Reduce rate limits for suspicious IPs
    reduced_limits = %{
      requests_per_minute: get_config(:suspicious_rate_limit, 10),
      burst_allowance: get_config(:suspicious_burst_limit, 2)
    }

    if check_rate_limit(ip, reduced_limits) do
      conn
    else
      increment_ip_failures(ip)
      send_rate_limit_response(conn, "Rate limit exceeded for suspicious IP")
    end
  end

  defp check_user_limits(conn, user) do
    user_limits = get_user_rate_limits(user)
    user_key = "user:#{user.id}"

    if check_rate_limit(user_key, user_limits) do
      conn
    else
      log_user_rate_limit_exceeded(user)
      send_rate_limit_response(conn, "User rate limit exceeded")
    end
  end

  defp get_endpoint_key(conn) do
    method = conn.method
    path = Enum.join(conn.path_info, "/")
    "#{method}:/#{path}"
  end

  defp get_endpoint_limits(endpoint) do
    endpoint_configs = get_config(:endpoint_limits, %{})

    # Check for exact match first
    case Map.get(endpoint_configs, endpoint) do
      nil ->
        # Check for pattern matches
        Enum.find_value(endpoint_configs, fn {pattern, limits} ->
          if String.contains?(pattern, "*") && endpoint_matches_pattern?(endpoint, pattern) do
            limits
          end
        end)

      limits ->
        limits
    end
  end

  defp endpoint_matches_pattern?(endpoint, pattern) do
    regex_pattern =
      pattern
      |> String.replace("*", ".*")
      |> Regex.compile!()

    Regex.match?(regex_pattern, endpoint)
  end

  defp apply_endpoint_limits(conn, endpoint, limits) do
    if check_rate_limit(endpoint, limits) do
      conn
    else
      send_rate_limit_response(conn, "Endpoint rate limit exceeded")
    end
  end

  defp detect_security_events(conn) do
    suspicious_indicators = [
      check_rapid_requests(conn),
      check_scanner_patterns(conn),
      check_injection_attempts(conn),
      check_authentication_failures(conn)
    ]

    case Enum.count(suspicious_indicators, & &1) do
      0 -> :normal
      1 -> :potential_attack
      _ -> :confirmed_attack
    end
  end

  defp check_rapid_requests(conn) do
    ip = get_client_ip(conn)
    window_seconds = 10
    threshold = get_config(:rapid_request_threshold, 50)

    request_count = count_recent_requests(ip, window_seconds)
    request_count > threshold
  end

  defp check_scanner_patterns(conn) do
    path = Enum.join(conn.path_info, "/")
    user_agent = get_req_header(conn, "user-agent") |> List.first() || ""

    Enum.any?(@scanner_patterns, fn pattern ->
      Regex.match?(pattern, path) || Regex.match?(pattern, user_agent)
    end)
  end

  defp check_injection_attempts(conn) do
    query_string = conn.query_string
    body_params = conn.body_params

    all_input = [query_string | Map.values(body_params)]

    Enum.any?(all_input, fn input ->
      if is_binary(input) do
        Enum.any?(@injection_patterns, &Regex.match?(&1, input))
      else
        false
      end
    end)
  end

  defp check_authentication_failures(conn) do
    ip = get_client_ip(conn)
    window_minutes = 5
    threshold = get_config(:auth_failure_threshold, 5)

    failure_count = count_auth_failures(ip, window_minutes)
    failure_count > threshold
  end

  defp apply_emergency_limits(conn) do
    ip = get_client_ip(conn)

    emergency_limits = %{
      requests_per_minute: get_config(:emergency_rate_limit, 5),
      burst_allowance: 1
    }

    if check_rate_limit(ip, emergency_limits) do
      conn
    else
      send_rate_limit_response(conn, "Emergency rate limit activated")
    end
  end

  defp block_ip_temporarily(conn) do
    ip = get_client_ip(conn)
    cache_key = "ip_status:#{ip}"
    timestamp = System.system_time(:second)

    # Block IP for configured duration
    :ets.insert(:rate_limit_cache, {cache_key, :blocked, timestamp})

    conn
    |> send_rate_limit_response("IP temporarily blocked due to abuse")
    |> halt()
  end

  defp check_rate_limit(key, limits) do
    current_time = System.system_time(:second)
    requests_per_minute = Map.get(limits, :requests_per_minute, 60)
    # seconds
    window = 60

    cache_key = "rate_limit:#{key}"

    case :ets.lookup(:rate_limit_cache, cache_key) do
      [{^cache_key, count, last_reset}] ->
        if current_time - last_reset > window do
          # Reset window
          :ets.insert(:rate_limit_cache, {cache_key, 1, current_time})
          true
        else
          if count < requests_per_minute do
            # Increment counter
            :ets.insert(:rate_limit_cache, {cache_key, count + 1, last_reset})
            true
          else
            false
          end
        end

      [] ->
        # First request in window
        :ets.insert(:rate_limit_cache, {cache_key, 1, current_time})
        true
    end
  end

  defp get_user_rate_limits(user) do
    case has_admin_role?(user) do
      true ->
        %{
          requests_per_minute: get_config(:admin_rate_limit, 300),
          burst_allowance: get_config(:admin_burst_limit, 50)
        }

      false ->
        %{
          requests_per_minute: get_config(:user_rate_limit, 100),
          burst_allowance: get_config(:user_burst_limit, 10)
        }
    end
  end

  defp has_admin_role?(user) do
    VaultLite.Auth.check_admin_access(user) == {:ok, :authorized}
  rescue
    _ -> false
  end

  defp increment_ip_failures(ip) do
    cache_key = "ip_failures:#{ip}"
    current_time = System.system_time(:second)

    case :ets.lookup(:rate_limit_cache, cache_key) do
      [{^cache_key, count, _timestamp}] ->
        :ets.insert(:rate_limit_cache, {cache_key, count + 1, current_time})

      [] ->
        :ets.insert(:rate_limit_cache, {cache_key, 1, current_time})
    end
  end

  defp count_recent_requests(ip, window_seconds) do
    # This would typically query a time-series database
    # For now, we'll use a simple ETS-based approach
    cache_key = "request_count:#{ip}"

    case :ets.lookup(:rate_limit_cache, cache_key) do
      [{^cache_key, count, timestamp}] ->
        if System.system_time(:second) - timestamp < window_seconds do
          count
        else
          0
        end

      [] ->
        0
    end
  end

  defp count_auth_failures(ip, window_minutes) do
    # Count authentication failures for this IP in the time window
    cache_key = "auth_failures:#{ip}"
    window_seconds = window_minutes * 60

    case :ets.lookup(:rate_limit_cache, cache_key) do
      [{^cache_key, count, timestamp}] ->
        if System.system_time(:second) - timestamp < window_seconds do
          count
        else
          0
        end

      [] ->
        0
    end
  end

  defp send_rate_limit_response(conn, message) do
    conn
    |> put_status(429)
    |> put_resp_content_type("application/json")
    |> send_resp(
      429,
      Jason.encode!(%{
        error: "rate_limit_exceeded",
        message: message,
        retry_after: resolve_retry_after()
      })
    )
    |> halt()
  end

  defp resolve_retry_after() do
    DateTime.utc_now()
    |> DateTime.add(get_config(:retry_after_seconds, 60), :second)
    |> DateTime.to_unix()
  end

  defp log_security_event(conn, event) do
    ip = get_client_ip(conn)
    user = get_current_user(conn)

    Logger.warning("Security event detected",
      event: event,
      ip: ip,
      user_id: user && user.id,
      path: conn.request_path,
      method: conn.method,
      user_agent: get_req_header(conn, "user-agent") |> List.first()
    )

    # Also log to audit system if available
    if user do
      VaultLite.Audit.log_action(user, "security_event", "system", %{
        event: event,
        ip: ip,
        path: conn.request_path
      })
    end
  end

  defp log_user_rate_limit_exceeded(user) do
    Logger.info("User rate limit exceeded",
      user_id: user.id,
      username: user.username
    )

    VaultLite.Audit.log_action(user, "rate_limit_exceeded", "system", %{
      limit_type: "user_rate_limit"
    })
  end

  defp get_config(key, default) do
    :vault_lite
    |> Application.get_env(:security, [])
    |> Keyword.get(:rate_limiting, [])
    |> Keyword.get(key, default)
  end
end
