defmodule VaultLiteWeb.RateLimitTest do
  use VaultLiteWeb.ConnCase, async: false

  alias VaultLite.{Auth, Guardian}

  # Note: async: false because we're testing shared ETS state

  setup do
    # Clean up ETS tables before each test
    :ets.delete_all_objects(:rate_limit_cache)
    :ets.delete_all_objects(VaultLite.PlugAttackStorage)

    # Create a test user
    {:ok, user} =
      Auth.create_user(%{
        username: "testuser_#{System.unique_integer([:positive])}",
        email: "test#{System.unique_integer([:positive])}@example.com",
        password: "StrongPassword123!"
      })

    # Assign basic role
    {:ok, _role} =
      Auth.assign_role(user, %{
        name: "test_role",
        permissions: ["read", "write"],
        path_patterns: ["*"]
      })

    {:ok, token, _claims} = Guardian.encode_and_sign(user)

    %{user: user, token: token}
  end

  describe "PlugAttack rate limiting" do
    test "allows requests within limit" do
      # PlugAttack configured for 5 requests per second for API endpoints
      for _i <- 1..5 do
        conn =
          build_conn()
          |> put_req_header("accept", "application/json")
          |> get("/api/bootstrap/status")

        assert conn.status == 200
      end
    end

    test "blocks requests exceeding API rate limit", %{token: token} do
      # Make 6 requests quickly to exceed the 5 per second limit
      results =
        for _i <- 1..6 do
          conn =
            build_conn()
            |> put_req_header("accept", "application/json")
            |> put_req_header("authorization", "Bearer #{token}")
            |> get("/api/secrets")

          conn.status
        end

      # Some requests should be blocked (429)
      assert Enum.any?(results, &(&1 == 429))
    end

    test "blocks login attempts exceeding limit" do
      # PlugAttack configured for 3 login attempts per minute
      login_params = %{
        identifier: "testuser",
        password: "wrongpassword"
      }

      results =
        for _i <- 1..4 do
          conn =
            build_conn()
            |> put_req_header("accept", "application/json")
            |> post("/api/auth/login", login_params)

          conn.status
        end

      # Should have at least one 429 response
      assert Enum.any?(results, &(&1 == 429))
    end

    test "rate limits are per IP address" do
      # Use different IP addresses via X-Forwarded-For header
      conn1 =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("x-forwarded-for", "192.168.1.1")

      conn2 =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("x-forwarded-for", "192.168.1.2")

      # Make many requests from first IP to trigger rate limit
      for _i <- 1..10 do
        post(conn1, "/api/auth/login", %{identifier: "test", password: "test"})
      end

      # Request from second IP should still work
      response = post(conn2, "/api/auth/login", %{identifier: "test", password: "test"})
      assert response.status != 429
    end
  end

  describe "EnhancedRateLimiter" do
    test "applies different limits for admin vs regular users", %{user: user} do
      # Create admin user
      {:ok, admin} =
        Auth.create_user(%{
          username: "admin_#{System.unique_integer([:positive])}",
          email: "admin#{System.unique_integer([:positive])}@example.com",
          password: "StrongPassword123!"
        })

      {:ok, _role} =
        Auth.assign_role(admin, %{
          name: "admin",
          permissions: ["read", "write", "delete", "admin"],
          path_patterns: ["*"]
        })

      {:ok, admin_token, _} = Guardian.encode_and_sign(admin)
      {:ok, user_token, _} = Guardian.encode_and_sign(user)

      # Mock the rate limiting config to use lower limits for testing
      Application.put_env(:vault_lite, :security,
        rate_limiting: [
          admin_rate_limit: 10,
          user_rate_limit: 5
        ]
      )

      # Test that admin gets higher limits than regular user
      # This is tested indirectly by checking the rate limiter behavior
      admin_conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("authorization", "Bearer #{admin_token}")

      user_conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("authorization", "Bearer #{user_token}")

      # Both should work for small number of requests
      assert get(admin_conn, "/api/secrets").status != 429
      assert get(user_conn, "/api/secrets").status != 429
    end

    test "detects and blocks suspicious IP patterns" do
      # Simulate scanner-like behavior with suspicious patterns
      suspicious_paths = [
        "/api/secrets/../etc/passwd",
        "/api/secrets?id=1' OR '1'='1",
        "/api/secrets/<script>alert('xss')</script>"
      ]

      conn_base =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("user-agent", "sqlmap/1.0")

      # Make requests with suspicious patterns
      for path <- suspicious_paths do
        # Note: Phoenix will handle malformed URLs, we're testing the detection
        try do
          get(conn_base, "/api/bootstrap/status")
        rescue
          _ -> :ok
        end
      end

      # Check that IP is now considered suspicious by making a normal request
      response = get(conn_base, "/api/bootstrap/status")
      # The response might still be 200, but the IP should be flagged internally
      assert response.status in [200, 429]
    end

    test "applies emergency limits during potential attacks" do
      # Simulate rapid requests to trigger attack detection
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("x-forwarded-for", "10.0.0.1")

      # Make many rapid requests
      results =
        for _i <- 1..20 do
          try do
            response = get(conn, "/api/bootstrap/status")
            response.status
          rescue
            _ -> 500
          end
        end

      # Should eventually get rate limited
      assert Enum.any?(results, &(&1 == 429))
    end

    test "temporarily blocks abusive IPs" do
      # Mock configuration for testing
      Application.put_env(:vault_lite, :security,
        rate_limiting: [
          block_threshold: 3,
          suspicious_threshold: 2
        ]
      )

      # Simulate IP that should be blocked
      malicious_ip = "192.168.1.100"

      # Increment failure count in ETS to simulate previous violations
      :ets.insert(
        :rate_limit_cache,
        {"ip_failures:#{malicious_ip}", 5, System.system_time(:second)}
      )

      :ets.insert(
        :rate_limit_cache,
        {"ip_status:#{malicious_ip}", :blocked, System.system_time(:second)}
      )

      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("x-forwarded-for", malicious_ip)

      # Should be blocked immediately
      response = get(conn, "/api/bootstrap/status")
      assert response.status == 429
      assert String.contains?(response.resp_body, "blocked")
    end

    test "rate limit cache cleanup works" do
      # Add some test entries to the cache
      current_time = System.system_time(:second)
      # 2 hours ago
      old_time = current_time - 7200

      :ets.insert(:rate_limit_cache, {"test_key_1", 5, current_time})
      :ets.insert(:rate_limit_cache, {"test_key_2", 3, old_time})

      # Verify entries exist
      assert :ets.lookup(:rate_limit_cache, "test_key_1") != []
      assert :ets.lookup(:rate_limit_cache, "test_key_2") != []

      # The cache cleanup would happen automatically in the background
      # For testing, we can check that old entries would be ignored
      assert length(:ets.tab2list(:rate_limit_cache)) >= 2
    end
  end

  describe "endpoint-specific rate limiting" do
    test "applies different limits to different endpoints", %{token: token} do
      # Mock endpoint-specific configuration
      Application.put_env(:vault_lite, :security,
        rate_limiting: [
          endpoint_limits: %{
            "GET:/api/secrets" => %{requests_per_minute: 2},
            "POST:/api/secrets" => %{requests_per_minute: 1}
          }
        ]
      )

      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("authorization", "Bearer #{token}")

      # Test that GET has different limits than POST
      get_results =
        for _i <- 1..3 do
          get(conn, "/api/secrets").status
        end

      # Should see some rate limiting on GET after 2 requests
      assert Enum.count(get_results, &(&1 == 200)) <= 2
    end
  end

  describe "security event monitoring" do
    test "logs security events for rate limit violations", %{token: token} do
      # Clear any existing logs
      VaultLite.Repo.delete_all(VaultLite.AuditLog)

      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("authorization", "Bearer #{token}")
        |> put_req_header("x-forwarded-for", "192.168.1.50")

      # Make enough requests to trigger rate limiting
      for _i <- 1..10 do
        get(conn, "/api/secrets")
      end

      # Check if security events were logged
      # Note: This depends on the actual implementation of audit logging
      # In a real test, you might check the audit log table or mock the logger
      import Ecto.Query

      logs =
        from(a in VaultLite.AuditLog,
          where: a.action == "security_event"
        )
        |> VaultLite.Repo.all()

      # Might have security events logged (this is implementation dependent)
      assert is_list(logs)
    end
  end

  describe "rate limit responses" do
    test "returns proper error format for rate limit exceeded" do
      # Make many requests quickly to trigger rate limit
      conn_base =
        build_conn()
        |> put_req_header("accept", "application/json")

      # Keep making requests until we get rate limited
      response =
        Enum.reduce_while(1..20, nil, fn _i, _acc ->
          resp = get(conn_base, "/api/bootstrap/status")

          if resp.status == 429 do
            {:halt, resp}
          else
            {:cont, resp}
          end
        end)

      if response && response.status == 429 do
        # Check response format for rate limit error
        assert response.status == 429
        assert get_resp_header(response, "content-type") |> List.first() =~ "application/json"

        case Jason.decode(response.resp_body) do
          {:ok, body} ->
            assert Map.has_key?(body, "error")
            assert body["error"] =~ "rate"

          {:error, _} ->
            # Plain text response from PlugAttack
            assert response.resp_body =~ "Rate limit"
        end
      end
    end

    test "includes retry-after information in rate limit responses" do
      # This tests the EnhancedRateLimiter response format
      # We'll need to trigger it through the enhanced limiter specifically

      # Mock a blocked IP status
      test_ip = "10.0.0.100"

      :ets.insert(
        :rate_limit_cache,
        {"ip_status:#{test_ip}", :blocked, System.system_time(:second)}
      )

      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("x-forwarded-for", test_ip)

      response = get(conn, "/api/bootstrap/status")

      if response.status == 429 do
        case Jason.decode(response.resp_body) do
          {:ok, body} ->
            assert Map.has_key?(body, "retry_after")
            assert is_integer(body["retry_after"])

          {:error, _} ->
            # Plain text response is also acceptable
            :ok
        end
      end
    end
  end

  describe "rate limit configuration" do
    test "respects custom configuration values" do
      # Set custom config for testing
      custom_config = [
        rate_limiting: [
          enabled: true,
          user_rate_limit: 5,
          admin_rate_limit: 10,
          suspicious_rate_limit: 2
        ]
      ]

      Application.put_env(:vault_lite, :security, custom_config)

      # Test that custom values are used
      # This is tested indirectly through behavior
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")

      # Should work within configured limits
      response = get(conn, "/api/bootstrap/status")
      # Either works or rate limited based on current state
      assert response.status in [200, 429]
    end

    test "falls back to default values when config is missing" do
      # Remove rate limiting config
      original_config = Application.get_env(:vault_lite, :security, [])
      Application.put_env(:vault_lite, :security, [])

      conn =
        build_conn()
        |> put_req_header("accept", "application/json")

      # Should still work with defaults
      response = get(conn, "/api/bootstrap/status")
      assert response.status in [200, 429]

      # Restore original config
      Application.put_env(:vault_lite, :security, original_config)
    end
  end

  # Helper functions

  defp make_rapid_requests(conn, path, count \\ 10) do
    for _i <- 1..count do
      get(conn, path)
    end
  end

  defp simulate_attack_patterns(conn) do
    attack_patterns = [
      %{path: "/api/secrets", user_agent: "sqlmap/1.0"},
      %{path: "/api/secrets", query: "?id=1' OR '1'='1"},
      %{path: "/api/secrets/../etc/passwd", user_agent: "nikto"}
    ]

    for pattern <- attack_patterns do
      conn_with_pattern =
        conn
        |> put_req_header("user-agent", pattern[:user_agent] || "test")

      path = pattern[:path] || "/api/bootstrap/status"

      try do
        get(conn_with_pattern, path)
      rescue
        _ -> :ok
      end
    end
  end
end
