defmodule VaultLiteWeb.AuditControllerTest do
  use VaultLiteWeb.ConnCase, async: true
  import Mox

  alias VaultLite.{Auth, Audit, Guardian}

  # Set up mocks
  setup :verify_on_exit!

  setup %{conn: conn} do
    # Create admin user for testing
    {:ok, admin_user} =
      Auth.create_user(%{
        username: "admin",
        email: "admin@example.com",
        password: "password123"
      })

    # Assign admin role
    {:ok, _role} =
      Auth.assign_role(admin_user, %{
        name: "admin",
        permissions: ["read", "write", "delete", "admin"],
        path_patterns: ["*"]
      })

    # Create regular user for testing
    {:ok, regular_user} =
      Auth.create_user(%{
        username: "regular",
        email: "regular@example.com",
        password: "password123"
      })

    {:ok, _role} =
      Auth.assign_role(regular_user, %{
        name: "user",
        permissions: ["read", "write"],
        path_patterns: ["secrets/user/*"]
      })

    # Generate tokens
    {:ok, admin_token, _claims} = Guardian.encode_and_sign(admin_user)
    {:ok, regular_token, _claims} = Guardian.encode_and_sign(regular_user)

    # Create some test audit logs
    {:ok, _log1} = Audit.log_action(admin_user, "create", "test_secret1", %{"version" => 1})
    {:ok, _log2} = Audit.log_action(regular_user, "read", "test_secret1", %{"version" => 1})
    {:ok, _log3} = Audit.log_action(admin_user, "update", "test_secret1", %{"version" => 2})
    {:ok, _log4} = Audit.log_action(regular_user, "create", "test_secret2", %{"version" => 1})
    {:ok, _log5} = Audit.log_action(nil, "system", "cleanup")

    admin_conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer #{admin_token}")

    regular_conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer #{regular_token}")

    %{
      admin_conn: admin_conn,
      regular_conn: regular_conn,
      admin_user: admin_user,
      regular_user: regular_user
    }
  end

  describe "GET /api/audit/logs" do
    test "returns all audit logs for admin", %{admin_conn: conn} do
      conn = get(conn, ~p"/api/audit/logs")

      assert %{
               "status" => "success",
               "data" => logs,
               "pagination" => %{
                 "limit" => 50,
                 "offset" => 0,
                 "total" => total
               }
             } = json_response(conn, 200)

      assert is_list(logs)
      # At least our test logs
      assert total >= 5
      assert length(logs) >= 5
    end

    test "filters logs by user_id", %{admin_conn: conn, regular_user: regular_user} do
      conn = get(conn, ~p"/api/audit/logs?user_id=#{regular_user.id}")

      assert %{
               "status" => "success",
               "data" => logs
             } = json_response(conn, 200)

      # Should only return logs for regular_user
      user_ids = Enum.map(logs, & &1["user_id"])
      assert Enum.all?(user_ids, &(&1 == regular_user.id))
    end

    test "filters logs by secret_key", %{admin_conn: conn} do
      conn = get(conn, ~p"/api/audit/logs?secret_key=test_secret1")

      assert %{
               "status" => "success",
               "data" => logs
             } = json_response(conn, 200)

      # Should only return logs for test_secret1
      secret_keys = Enum.map(logs, & &1["secret_key"])
      assert Enum.all?(secret_keys, &(&1 == "test_secret1"))
    end

    test "filters logs by action", %{admin_conn: conn} do
      conn = get(conn, ~p"/api/audit/logs?action=create")

      assert %{
               "status" => "success",
               "data" => logs
             } = json_response(conn, 200)

      # Should only return create actions
      actions = Enum.map(logs, & &1["action"])
      assert Enum.all?(actions, &(&1 == "create"))
    end

    test "supports pagination", %{admin_conn: conn} do
      conn = get(conn, ~p"/api/audit/logs?limit=2&offset=0")

      assert %{
               "status" => "success",
               "data" => logs,
               "pagination" => %{
                 "limit" => 2,
                 "offset" => 0,
                 "total" => _total
               }
             } = json_response(conn, 200)

      assert length(logs) == 2
    end

    test "combines multiple filters", %{admin_conn: conn, regular_user: regular_user} do
      conn = get(conn, ~p"/api/audit/logs?user_id=#{regular_user.id}&action=create")

      assert %{
               "status" => "success",
               "data" => logs
             } = json_response(conn, 200)

      # Should only return create actions by regular_user
      assert Enum.all?(logs, fn log ->
               log["user_id"] == regular_user.id && log["action"] == "create"
             end)
    end

    test "validates date range filters", %{admin_conn: conn} do
      now = DateTime.utc_now() |> DateTime.to_iso8601()
      one_hour_ago = DateTime.utc_now() |> DateTime.add(-3600, :second) |> DateTime.to_iso8601()

      conn = get(conn, ~p"/api/audit/logs?start_date=#{one_hour_ago}&end_date=#{now}")

      assert %{
               "status" => "success",
               "data" => _logs
             } = json_response(conn, 200)
    end

    test "returns error for invalid date format", %{admin_conn: conn} do
      conn = get(conn, ~p"/api/audit/logs?start_date=invalid-date")

      assert %{
               "status" => "error",
               "message" => "Invalid date format"
             } = json_response(conn, 422)
    end

    test "denies access to non-admin users", %{regular_conn: conn} do
      conn = get(conn, ~p"/api/audit/logs")

      assert %{
               "status" => "error",
               "message" => "Insufficient permissions"
             } = json_response(conn, 403)
    end

    test "requires authentication" do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")

      conn = get(conn, ~p"/api/audit/logs")

      assert %{
               "error" => "unauthenticated"
             } = json_response(conn, 401)
    end
  end

  describe "GET /api/audit/secrets/:key" do
    test "returns audit trail for specific secret", %{admin_conn: conn} do
      conn = get(conn, ~p"/api/audit/secrets/test_secret1")

      assert %{
               "status" => "success",
               "data" => logs,
               "pagination" => %{
                 "limit" => 50,
                 "offset" => 0,
                 "total" => _total
               }
             } = json_response(conn, 200)

      assert is_list(logs)
      # All logs should be for test_secret1
      secret_keys = Enum.map(logs, & &1["secret_key"])
      assert Enum.all?(secret_keys, &(&1 == "test_secret1"))
    end

    test "supports pagination", %{admin_conn: conn} do
      conn = get(conn, ~p"/api/audit/secrets/test_secret1?limit=1")

      assert %{
               "status" => "success",
               "data" => logs,
               "pagination" => %{
                 "limit" => 1,
                 "offset" => 0,
                 "total" => _total
               }
             } = json_response(conn, 200)

      assert length(logs) == 1
    end

    test "returns empty list for non-existent secret", %{admin_conn: conn} do
      conn = get(conn, ~p"/api/audit/secrets/non_existent_secret")

      assert %{
               "status" => "success",
               "data" => [],
               "pagination" => %{
                 "total" => 0
               }
             } = json_response(conn, 200)
    end

    test "allows regular users to access secrets they have read permission for", %{
      regular_conn: conn
    } do
      # Assuming regular user has read access to secrets they created
      conn = get(conn, ~p"/api/audit/secrets/test_secret2")

      # This might return 200 or 403 depending on RBAC implementation
      # Let's assume it returns 200 for secrets the user has access to
      response = json_response(conn, 200)
      assert %{"status" => "success"} = response
    end

    test "denies access to secrets user has no permission for", %{regular_conn: conn} do
      # Try to access a secret the regular user shouldn't have access to
      conn = get(conn, ~p"/api/audit/secrets/admin_only_secret")

      assert %{
               "status" => "error",
               "message" => "Insufficient permissions"
             } = json_response(conn, 403)
    end
  end

  describe "GET /api/audit/users/:user_id" do
    test "admin can access any user's audit trail", %{
      admin_conn: conn,
      regular_user: regular_user
    } do
      conn = get(conn, ~p"/api/audit/users/#{regular_user.id}")

      assert %{
               "status" => "success",
               "data" => logs,
               "pagination" => %{
                 "limit" => 50,
                 "offset" => 0,
                 "total" => _total
               }
             } = json_response(conn, 200)

      assert is_list(logs)
      # All logs should be for the specified user
      user_ids = Enum.map(logs, & &1["user_id"])
      assert Enum.all?(user_ids, &(&1 == regular_user.id))
    end

    test "users can access their own audit trail", %{
      regular_conn: conn,
      regular_user: regular_user
    } do
      conn = get(conn, ~p"/api/audit/users/#{regular_user.id}")

      assert %{
               "status" => "success",
               "data" => logs
             } = json_response(conn, 200)

      assert is_list(logs)
    end

    test "users cannot access other users' audit trails", %{
      regular_conn: conn,
      admin_user: admin_user
    } do
      conn = get(conn, ~p"/api/audit/users/#{admin_user.id}")

      assert %{
               "status" => "error",
               "message" => "Insufficient permissions"
             } = json_response(conn, 403)
    end

    test "supports pagination", %{admin_conn: conn, regular_user: regular_user} do
      conn = get(conn, ~p"/api/audit/users/#{regular_user.id}?limit=1")

      assert %{
               "status" => "success",
               "data" => logs,
               "pagination" => %{
                 "limit" => 1,
                 "offset" => 0,
                 "total" => _total
               }
             } = json_response(conn, 200)

      assert length(logs) <= 1
    end

    test "filters by action and secret_key", %{admin_conn: conn, regular_user: regular_user} do
      conn =
        get(conn, ~p"/api/audit/users/#{regular_user.id}?action=create&secret_key=test_secret2")

      assert %{
               "status" => "success",
               "data" => logs
             } = json_response(conn, 200)

      assert Enum.all?(logs, fn log ->
               log["user_id"] == regular_user.id &&
                 log["action"] == "create" &&
                 log["secret_key"] == "test_secret2"
             end)
    end

    test "returns empty list for non-existent user", %{admin_conn: conn} do
      conn = get(conn, ~p"/api/audit/users/999999")

      assert %{
               "status" => "success",
               "data" => [],
               "pagination" => %{
                 "total" => 0
               }
             } = json_response(conn, 200)
    end
  end

  describe "GET /api/audit/statistics" do
    test "returns comprehensive statistics for admin", %{admin_conn: conn} do
      conn = get(conn, ~p"/api/audit/statistics")

      assert %{
               "status" => "success",
               "data" => %{
                 "total_logs" => total_logs,
                 "actions" => actions,
                 "top_secrets" => top_secrets,
                 "active_users" => active_users
               }
             } = json_response(conn, 200)

      assert is_integer(total_logs)
      # At least our test logs
      assert total_logs >= 5

      assert is_map(actions)
      assert Map.has_key?(actions, "create")
      assert Map.has_key?(actions, "read")

      assert is_list(top_secrets)

      if length(top_secrets) > 0 do
        top_secret = List.first(top_secrets)
        assert Map.has_key?(top_secret, "secret_key")
        assert Map.has_key?(top_secret, "access_count")
      end

      assert is_integer(active_users)
      # At least admin and regular user
      assert active_users >= 2
    end

    test "filters statistics by date range", %{admin_conn: conn} do
      now = DateTime.utc_now() |> DateTime.to_iso8601()
      one_hour_ago = DateTime.utc_now() |> DateTime.add(-3600, :second) |> DateTime.to_iso8601()

      conn = get(conn, ~p"/api/audit/statistics?start_date=#{one_hour_ago}&end_date=#{now}")

      assert %{
               "status" => "success",
               "data" => %{
                 "total_logs" => _total_logs,
                 "actions" => _actions,
                 "top_secrets" => _top_secrets,
                 "active_users" => _active_users
               }
             } = json_response(conn, 200)
    end

    test "returns error for invalid date format", %{admin_conn: conn} do
      conn = get(conn, ~p"/api/audit/statistics?start_date=invalid-date")

      assert %{
               "status" => "error",
               "message" => "Invalid date format"
             } = json_response(conn, 422)
    end

    test "denies access to non-admin users", %{regular_conn: conn} do
      conn = get(conn, ~p"/api/audit/statistics")

      assert %{
               "status" => "error",
               "message" => "Insufficient permissions"
             } = json_response(conn, 403)
    end
  end

  describe "DELETE /api/audit/purge" do
    test "purges old audit logs for admin", %{admin_conn: conn} do
      conn = delete(conn, ~p"/api/audit/purge?days_to_keep=90")

      assert %{
               "status" => "success",
               "message" => message,
               "data" => %{
                 "deleted_count" => deleted_count,
                 "days_kept" => 90
               }
             } = json_response(conn, 200)

      assert is_binary(message)
      assert is_integer(deleted_count)
      assert deleted_count >= 0
    end

    test "uses default retention period when not specified", %{admin_conn: conn} do
      conn = delete(conn, ~p"/api/audit/purge")

      assert %{
               "status" => "success",
               "data" => %{
                 "deleted_count" => _deleted_count,
                 # Default value
                 "days_kept" => 365
               }
             } = json_response(conn, 200)
    end

    test "validates days_to_keep parameter", %{admin_conn: conn} do
      conn = delete(conn, ~p"/api/audit/purge?days_to_keep=invalid")

      assert %{
               "status" => "error",
               "message" => "Invalid days_to_keep parameter"
             } = json_response(conn, 422)
    end

    test "validates minimum retention period", %{admin_conn: conn} do
      conn = delete(conn, ~p"/api/audit/purge?days_to_keep=0")

      assert %{
               "status" => "error",
               "message" => "Minimum retention period is 1 day"
             } = json_response(conn, 422)
    end

    test "denies access to non-admin users", %{regular_conn: conn} do
      conn = delete(conn, ~p"/api/audit/purge")

      assert %{
               "status" => "error",
               "message" => "Insufficient permissions"
             } = json_response(conn, 403)
    end
  end

  describe "error handling" do
    test "handles invalid pagination parameters", %{admin_conn: conn} do
      conn = get(conn, ~p"/api/audit/logs?limit=invalid")

      assert %{
               "status" => "error",
               "message" => "Invalid pagination parameters"
             } = json_response(conn, 422)
    end

    test "handles limit exceeding maximum", %{admin_conn: conn} do
      conn = get(conn, ~p"/api/audit/logs?limit=1000")

      assert %{
               "status" => "error",
               "message" => "Limit cannot exceed 100"
             } = json_response(conn, 422)
    end

    test "handles negative offset", %{admin_conn: conn} do
      conn = get(conn, ~p"/api/audit/logs?offset=-1")

      assert %{
               "status" => "error",
               "message" => "Invalid pagination parameters"
             } = json_response(conn, 422)
    end

    test "handles malformed user_id parameter", %{admin_conn: conn} do
      conn = get(conn, ~p"/api/audit/logs?user_id=invalid")

      assert %{
               "status" => "error",
               "message" => "Invalid user_id parameter"
             } = json_response(conn, 422)
    end
  end

  describe "rate limiting" do
    # Note: This would require setting up rate limiting configuration for tests
    @tag :skip
    test "respects rate limits for audit endpoints" do
      # Implementation would depend on PlugAttack configuration
    end
  end
end
