#!/usr/bin/env elixir

# Rate Limiting Test Script for VaultLite
# Usage: elixir test_rate_limiting.exs
# Make sure VaultLite is running on localhost:4000

Mix.install([
  {:httpoison, "~> 2.0"},
  {:jason, "~> 1.4"}
])

defmodule RateLimitTester do
  @moduledoc """
  Interactive rate limiting test suite for VaultLite.

  This script tests various rate limiting scenarios against a running VaultLite instance.
  """

  @base_url "http://localhost:4000"
  @default_headers [
    {"Content-Type", "application/json"},
    {"Accept", "application/json"}
  ]

  def run do
    IO.puts("\n🧪 VaultLite Rate Limiting Test Suite")
    IO.puts("====================================\n")

    IO.puts("Testing against: #{@base_url}")
    IO.puts("Make sure VaultLite is running!\n")

    # Check if server is running
    case HTTPoison.get("#{@base_url}/api/bootstrap/status") do
      {:ok, %{status_code: 200}} ->
        IO.puts("✅ Server is running\n")
        run_tests()

      {:error, reason} ->
        IO.puts("❌ Server not responding: #{inspect(reason)}")
        IO.puts("Please start VaultLite with: mix phx.server")
        System.halt(1)
    end
  end

  defp run_tests do
    IO.puts("🔍 Running rate limiting tests...\n")

    test_basic_api_rate_limiting()
    test_login_rate_limiting()
    test_registration_rate_limiting()
    test_different_ips()
    test_admin_vs_user_limits()
    test_security_patterns()

    IO.puts("\n✅ Rate limiting tests completed!")
    IO.puts("Check your VaultLite logs for security events and rate limit violations.")
  end

  # Test 1: Basic API Rate Limiting
  defp test_basic_api_rate_limiting do
    IO.puts("📊 Test 1: Basic API Rate Limiting")
    IO.puts("Making rapid requests to /api/bootstrap/status...")

    results = make_rapid_requests("/api/bootstrap/status", 15)

    success_count = Enum.count(results, fn {status, _} -> status == 200 end)
    rate_limited_count = Enum.count(results, fn {status, _} -> status == 429 end)

    IO.puts("  📈 Results:")
    IO.puts("    Successful requests: #{success_count}")
    IO.puts("    Rate limited requests: #{rate_limited_count}")

    if rate_limited_count > 0 do
      IO.puts("    ✅ Rate limiting is working!")
    else
      IO.puts("    ⚠️  No rate limiting detected - might need more requests")
    end

    IO.puts("")
    # Wait before next test
    Process.sleep(2000)
  end

  # Test 2: Login Rate Limiting
  defp test_login_rate_limiting do
    IO.puts("🔐 Test 2: Login Rate Limiting")
    IO.puts("Testing failed login attempts...")

    login_data = %{
      identifier: "nonexistent_user",
      password: "wrong_password"
    }

    results = make_rapid_requests("/api/auth/login", 8, "POST", login_data)

    success_count = Enum.count(results, fn {status, _} -> status in [200, 401, 422] end)
    rate_limited_count = Enum.count(results, fn {status, _} -> status == 429 end)

    IO.puts("  📈 Results:")
    IO.puts("    Login attempts processed: #{success_count}")
    IO.puts("    Rate limited attempts: #{rate_limited_count}")

    if rate_limited_count > 0 do
      IO.puts("    ✅ Login rate limiting is working!")
    else
      IO.puts("    ⚠️  No login rate limiting detected")
    end

    IO.puts("")
    Process.sleep(2000)
  end

  # Test 3: Registration Rate Limiting
  defp test_registration_rate_limiting do
    IO.puts("📝 Test 3: Registration Rate Limiting")
    IO.puts("Testing registration attempts...")

    results =
      for i <- 1..6 do
        user_data = %{
          user: %{
            username: "testuser#{i}_#{System.unique_integer([:positive])}",
            email: "test#{i}#{System.unique_integer([:positive])}@example.com",
            password: "StrongPassword123!"
          }
        }

        case make_request("/api/auth/register", "POST", user_data) do
          {:ok, %{status_code: code}} -> {code, nil}
          {:error, reason} -> {:error, reason}
        end
      end

    success_count = Enum.count(results, fn {status, _} -> status in [200, 201, 422] end)
    rate_limited_count = Enum.count(results, fn {status, _} -> status == 429 end)

    IO.puts("  📈 Results:")
    IO.puts("    Registration attempts processed: #{success_count}")
    IO.puts("    Rate limited attempts: #{rate_limited_count}")

    if rate_limited_count > 0 do
      IO.puts("    ✅ Registration rate limiting is working!")
    else
      IO.puts("    ⚠️  No registration rate limiting detected")
    end

    IO.puts("")
    Process.sleep(2000)
  end

  # Test 4: Different IP Addresses
  defp test_different_ips do
    IO.puts("🌐 Test 4: IP-based Rate Limiting")
    IO.puts("Testing with different IP addresses...")

    # Test with IP 1
    ip1_headers = @default_headers ++ [{"X-Forwarded-For", "192.168.1.10"}]
    ip1_results = make_rapid_requests("/api/bootstrap/status", 10, "GET", nil, ip1_headers)

    # Test with IP 2
    ip2_headers = @default_headers ++ [{"X-Forwarded-For", "192.168.1.20"}]
    ip2_results = make_rapid_requests("/api/bootstrap/status", 10, "GET", nil, ip2_headers)

    ip1_rate_limited = Enum.count(ip1_results, fn {status, _} -> status == 429 end)
    ip2_rate_limited = Enum.count(ip2_results, fn {status, _} -> status == 429 end)

    IO.puts("  📈 Results:")
    IO.puts("    IP 192.168.1.10 rate limited: #{ip1_rate_limited}")
    IO.puts("    IP 192.168.1.20 rate limited: #{ip2_rate_limited}")

    if ip1_rate_limited > 0 and ip2_rate_limited == 0 do
      IO.puts("    ✅ IP-based rate limiting is working correctly!")
    else
      IO.puts("    ⚠️  IP isolation may not be working as expected")
    end

    IO.puts("")
    Process.sleep(2000)
  end

  # Test 5: Admin vs User Limits (if we have tokens)
  defp test_admin_vs_user_limits do
    IO.puts("👑 Test 5: Admin vs User Rate Limits")
    IO.puts("This test requires valid tokens - skipping for now")
    IO.puts("To test manually:")
    IO.puts("  1. Get admin and user JWT tokens")
    IO.puts("  2. Make requests with Authorization: Bearer <token>")
    IO.puts("  3. Compare rate limit behavior")
    IO.puts("")
  end

  # Test 6: Security Pattern Detection
  defp test_security_patterns do
    IO.puts("🛡️  Test 6: Security Pattern Detection")
    IO.puts("Testing suspicious request patterns...")

    # Test with suspicious user agent
    suspicious_headers =
      @default_headers ++
        [
          {"User-Agent", "sqlmap/1.0"},
          {"X-Forwarded-For", "10.0.0.100"}
        ]

    # Make some suspicious requests
    paths = [
      "/api/bootstrap/status",
      "/api/bootstrap/status?id=1'%20OR%20'1'='1",
      "/api/bootstrap/status"
    ]

    results =
      for path <- paths do
        case HTTPoison.get("#{@base_url}#{path}", suspicious_headers) do
          {:ok, %{status_code: code}} -> {code, nil}
          {:error, reason} -> {:error, reason}
        end
      end

    rate_limited_count = Enum.count(results, fn {status, _} -> status == 429 end)
    blocked_count = Enum.count(results, fn {status, _} -> status in [403, 429] end)

    IO.puts("  📈 Results:")
    IO.puts("    Blocked/Rate limited requests: #{blocked_count}")

    if blocked_count > 0 do
      IO.puts("    ✅ Security pattern detection is working!")
    else
      IO.puts("    ⚠️  No security blocking detected")
    end

    IO.puts("")
  end

  # Helper function to make rapid requests
  defp make_rapid_requests(path, count, method \\ "GET", body \\ nil, headers \\ @default_headers) do
    IO.write("    Making #{count} rapid requests... ")

    results =
      for _i <- 1..count do
        case make_request(path, method, body, headers) do
          {:ok, %{status_code: code, body: response_body}} ->
            {code, response_body}

          {:error, reason} ->
            {:error, reason}
        end
      end

    IO.puts("done!")
    results
  end

  # Helper function to make a request
  defp make_request(path, method \\ "GET", body \\ nil, headers \\ @default_headers) do
    url = "#{@base_url}#{path}"
    encoded_body = if body, do: Jason.encode!(body), else: ""

    case String.upcase(method) do
      "GET" -> HTTPoison.get(url, headers)
      "POST" -> HTTPoison.post(url, encoded_body, headers)
      "PUT" -> HTTPoison.put(url, encoded_body, headers)
      "DELETE" -> HTTPoison.delete(url, headers)
    end
  end

  # Show help information
  def help do
    IO.puts("""
    VaultLite Rate Limiting Test Script
    ==================================

    This script tests the rate limiting functionality of VaultLite.

    Prerequisites:
    1. VaultLite must be running on localhost:4000
    2. Start with: mix phx.server

    What this script tests:
    • Basic API rate limiting
    • Login attempt rate limiting
    • Registration rate limiting
    • IP-based rate limiting
    • Security pattern detection

    Usage:
    elixir test_rate_limiting.exs

    For manual testing, you can also use curl:

    # Test basic rate limiting
    for i in {1..10}; do curl -s -o /dev/null -w "%{http_code} " http://localhost:4000/api/bootstrap/status; done

    # Test login rate limiting
    for i in {1..10}; do curl -s -o /dev/null -w "%{http_code} " -X POST -H "Content-Type: application/json" -d '{"identifier":"test","password":"wrong"}' http://localhost:4000/api/auth/login; done
    """)
  end
end

# Parse command line arguments
case System.argv() do
  ["--help"] ->
    RateLimitTester.help()

  ["-h"] ->
    RateLimitTester.help()

  [] ->
    RateLimitTester.run()

  _ ->
    IO.puts("Usage: elixir test_rate_limiting.exs [--help]")
    System.halt(1)
end
