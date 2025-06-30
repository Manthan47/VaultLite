defmodule VaultLiteWeb.Plugs.SecurityHeaders do
  @moduledoc """
  Comprehensive security headers plug for VaultLite.

  Adds essential security headers to protect against:
  - XSS attacks
  - Clickjacking
  - MIME type sniffing
  - Content type confusion
  - Insecure connections (HSTS)
  - Referrer leakage
  """

  import Plug.Conn
  require Logger

  @doc """
  Initializes the plug with configuration options.
  """
  def init(opts), do: opts

  @doc """
  Adds comprehensive security headers to all responses.
  """
  def call(conn, _opts) do
    conn
    |> put_hsts_header()
    |> put_content_security_policy()
    |> put_x_frame_options()
    |> put_x_content_type_options()
    |> put_x_xss_protection()
    |> put_referrer_policy()
    |> put_permissions_policy()
    |> put_expect_ct_header()
    |> put_x_permitted_cross_domain_policies()
    |> remove_server_header()
  end

  # HTTP Strict Transport Security (HSTS)
  defp put_hsts_header(conn) do
    if get_config(:hsts_enabled, true) do
      # 1 year
      max_age = get_config(:hsts_max_age, 31_536_000)
      include_subdomains = get_config(:hsts_include_subdomains, true)
      preload = get_config(:hsts_preload, false)

      hsts_value = build_hsts_value(max_age, include_subdomains, preload)
      put_resp_header(conn, "strict-transport-security", hsts_value)
    else
      conn
    end
  end

  # Content Security Policy (CSP)
  defp put_content_security_policy(conn) do
    if get_config(:csp_enabled, true) do
      csp = get_config(:csp, default_csp())
      put_resp_header(conn, "content-security-policy", csp)
    else
      conn
    end
  end

  # X-Frame-Options
  defp put_x_frame_options(conn) do
    frame_options = get_config(:x_frame_options, "DENY")
    put_resp_header(conn, "x-frame-options", frame_options)
  end

  # X-Content-Type-Options
  defp put_x_content_type_options(conn) do
    put_resp_header(conn, "x-content-type-options", "nosniff")
  end

  # X-XSS-Protection
  defp put_x_xss_protection(conn) do
    xss_protection = get_config(:x_xss_protection, "1; mode=block")
    put_resp_header(conn, "x-xss-protection", xss_protection)
  end

  # Referrer Policy
  defp put_referrer_policy(conn) do
    referrer_policy = get_config(:referrer_policy, "strict-origin-when-cross-origin")
    put_resp_header(conn, "referrer-policy", referrer_policy)
  end

  # Permissions Policy (Feature Policy)
  defp put_permissions_policy(conn) do
    if get_config(:permissions_policy_enabled, true) do
      permissions_policy = get_config(:permissions_policy, default_permissions_policy())
      put_resp_header(conn, "permissions-policy", permissions_policy)
    else
      conn
    end
  end

  # Expect-CT (Certificate Transparency)
  defp put_expect_ct_header(conn) do
    if get_config(:expect_ct_enabled, false) do
      # 24 hours
      max_age = get_config(:expect_ct_max_age, 86_400)
      enforce = get_config(:expect_ct_enforce, false)
      report_uri = get_config(:expect_ct_report_uri, nil)

      expect_ct_value = build_expect_ct_value(max_age, enforce, report_uri)
      put_resp_header(conn, "expect-ct", expect_ct_value)
    else
      conn
    end
  end

  # X-Permitted-Cross-Domain-Policies
  defp put_x_permitted_cross_domain_policies(conn) do
    put_resp_header(conn, "x-permitted-cross-domain-policies", "none")
  end

  # Remove server identification header
  defp remove_server_header(conn) do
    delete_resp_header(conn, "server")
  end

  # Helper functions

  defp build_hsts_value(max_age, include_subdomains, preload) do
    base = "max-age=#{max_age}"

    base
    |> add_if(include_subdomains, "; includeSubDomains")
    |> add_if(preload, "; preload")
  end

  defp build_expect_ct_value(max_age, enforce, report_uri) do
    base = "max-age=#{max_age}"

    base
    |> add_if(enforce, ", enforce")
    |> add_if(report_uri, ", report-uri=\"#{report_uri}\"")
  end

  defp add_if(string, true, addition), do: string <> addition
  defp add_if(string, false, _addition), do: string
  defp add_if(string, nil, _addition), do: string
  defp add_if(string, value, addition) when not is_nil(value), do: string <> addition
  defp add_if(string, _value, _addition), do: string

  defp default_csp do
    """
    default-src 'self'; \
    script-src 'self' 'unsafe-inline' 'unsafe-eval'; \
    style-src 'self' 'unsafe-inline'; \
    img-src 'self' data: https:; \
    font-src 'self' https:; \
    connect-src 'self'; \
    media-src 'self'; \
    object-src 'none'; \
    child-src 'none'; \
    frame-src 'none'; \
    worker-src 'none'; \
    frame-ancestors 'none'; \
    form-action 'self'; \
    base-uri 'self'; \
    manifest-src 'self'
    """
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp default_permissions_policy do
    """
    accelerometer=(), \
    ambient-light-sensor=(), \
    autoplay=(), \
    battery=(), \
    camera=(), \
    cross-origin-isolated=(), \
    display-capture=(), \
    document-domain=(), \
    encrypted-media=(), \
    execution-while-not-rendered=(), \
    execution-while-out-of-viewport=(), \
    fullscreen=(), \
    geolocation=(), \
    gyroscope=(), \
    keyboard-map=(), \
    magnetometer=(), \
    microphone=(), \
    midi=(), \
    navigation-override=(), \
    payment=(), \
    picture-in-picture=(), \
    publickey-credentials-get=(), \
    screen-wake-lock=(), \
    sync-xhr=(), \
    usb=(), \
    web-share=(), \
    xr-spatial-tracking=()
    """
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp get_config(key, default) do
    :vault_lite
    |> Application.get_env(:security, [])
    |> Keyword.get(:security_headers, [])
    |> Keyword.get(key, default)
  end
end
