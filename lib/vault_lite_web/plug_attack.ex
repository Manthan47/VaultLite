defmodule VaultLiteWeb.PlugAttack do
  use PlugAttack

  # Throttle login requests - 10 per minute per IP
  rule "throttle login requests", conn do
    if conn.method == "POST" and conn.path_info == ["api", "auth", "login"] do
      throttle(conn.remote_ip,
        period: 60_000,
        limit: 10,
        storage: {PlugAttack.Storage.Ets, VaultLite.PlugAttackStorage}
      )
    end
  end

  # Throttle registration requests - 5 per minute per IP
  rule "throttle register requests", conn do
    if conn.method == "POST" and conn.path_info == ["api", "auth", "register"] do
      throttle(conn.remote_ip,
        period: 60_000,
        limit: 5,
        storage: {PlugAttack.Storage.Ets, VaultLite.PlugAttackStorage}
      )
    end
  end

  # General API throttling - 100 requests per minute per IP
  rule "throttle api requests", conn do
    if match?(["api" | _], conn.path_info) do
      throttle(conn.remote_ip,
        period: 60_000,
        limit: 100,
        storage: {PlugAttack.Storage.Ets, VaultLite.PlugAttackStorage}
      )
    end
  end

  # Handle rate limit exceeded
  def block_action(conn, _data, _opts) do
    conn
    |> Plug.Conn.send_resp(429, "Rate limit exceeded")
    |> Plug.Conn.halt()
  end

  # Allow requests that don't exceed rate limits
  def allow_action(conn, _data, _opts) do
    conn
  end
end
