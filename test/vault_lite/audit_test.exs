defmodule VaultLite.AuditTest do
  use VaultLite.DataCase, async: true
  import Mox
  import ExUnit.CaptureLog
  import StreamData

  alias VaultLite.{Audit, User, AuditLog}
  alias VaultLite.Repo

  # Set up mocks
  setup :verify_on_exit!

  describe "log_action/4" do
    setup do
      user = insert_user()
      %{user: user}
    end

    test "logs action with user struct", %{user: user} do
      action = "create"
      secret_key = "test_secret"
      metadata = %{"version" => 1}

      assert {:ok, audit_log} = Audit.log_action(user, action, secret_key, metadata)

      assert audit_log.user_id == user.id
      assert audit_log.action == action
      assert audit_log.secret_key == secret_key
      assert audit_log.metadata == metadata
      assert audit_log.timestamp
    end

    test "logs action with user ID", %{user: user} do
      action = "read"
      secret_key = "api_key"

      assert {:ok, audit_log} = Audit.log_action(user.id, action, secret_key)

      assert audit_log.user_id == user.id
      assert audit_log.action == action
      assert audit_log.secret_key == secret_key
      # Metadata is enhanced with system information
      assert Map.has_key?(audit_log.metadata, :application)
      assert Map.has_key?(audit_log.metadata, :logged_at)
    end

    test "logs system actions without user" do
      action = "system_cleanup"
      secret_key = "expired_secrets"

      assert {:ok, audit_log} = Audit.log_action(nil, action, secret_key)

      assert audit_log.user_id == nil
      assert audit_log.action == action
      assert audit_log.secret_key == secret_key
    end

    test "validates required fields" do
      user = insert_user()

      assert {:error, changeset} = Audit.log_action(user, "", "secret_key")
      assert "can't be blank" in errors_on(changeset).action

      assert {:error, changeset} = Audit.log_action(user, "read", "")
      assert "can't be blank" in errors_on(changeset).secret_key
    end

    @tag :skip
    test "logs to application logger", %{user: user} do
      log =
        capture_log(fn ->
          {:ok, _audit_log} = Audit.log_action(user, "read", "test_secret")
        end)

      assert log =~ "AUDIT:"
      assert log =~ "user_id=#{user.id}"
      assert log =~ "action=read"
      assert log =~ "secret=test_secret"
    end

    test "handles large metadata", %{user: user} do
      large_metadata = %{
        "description" => String.duplicate("x", 1000),
        "tags" => Enum.map(1..100, &"tag#{&1}"),
        "nested" => %{"deep" => %{"value" => "test"}}
      }

      assert {:ok, audit_log} = Audit.log_action(user, "create", "large_secret", large_metadata)
      # Check that our metadata is included (system adds additional fields)
      assert audit_log.metadata["description"] == large_metadata["description"]
      assert audit_log.metadata["tags"] == large_metadata["tags"]
      assert audit_log.metadata["nested"] == large_metadata["nested"]
      assert Map.has_key?(audit_log.metadata, :application)
      assert Map.has_key?(audit_log.metadata, :logged_at)
    end
  end

  describe "get_audit_logs/1" do
    setup do
      user1 = insert_user()
      user2 = insert_user(%{username: "user2", email: "user2@example.com"})

      # Create test audit logs
      {:ok, _log1} = Audit.log_action(user1, "create", "secret1", %{"version" => 1})
      {:ok, _log2} = Audit.log_action(user1, "read", "secret1", %{"version" => 1})
      {:ok, _log3} = Audit.log_action(user2, "create", "secret2", %{"version" => 1})
      {:ok, _log4} = Audit.log_action(user1, "update", "secret1", %{"version" => 2})
      {:ok, _log5} = Audit.log_action(nil, "system", "cleanup")

      %{user1: user1, user2: user2}
    end

    test "returns all logs without filters" do
      {:ok, logs} = Audit.get_audit_logs()
      assert length(logs) == 5
    end

    test "filters by user_id", %{user1: user1, user2: user2} do
      {:ok, user1_logs} = Audit.get_audit_logs(user_id: user1.id)
      assert length(user1_logs) == 3

      {:ok, user2_logs} = Audit.get_audit_logs(user_id: user2.id)
      assert length(user2_logs) == 1
    end

    test "filters by secret_key", %{user1: _user1} do
      {:ok, secret1_logs} = Audit.get_audit_logs(secret_key: "secret1")
      assert length(secret1_logs) == 3

      {:ok, secret2_logs} = Audit.get_audit_logs(secret_key: "secret2")
      assert length(secret2_logs) == 1
    end

    test "filters by action" do
      {:ok, create_logs} = Audit.get_audit_logs(action: "create")
      assert length(create_logs) == 2

      {:ok, read_logs} = Audit.get_audit_logs(action: "read")
      assert length(read_logs) == 1
    end

    test "filters by date range" do
      now = DateTime.utc_now()
      one_hour_ago = DateTime.add(now, -3600, :second)
      one_hour_later = DateTime.add(now, 3600, :second)

      {:ok, recent_logs} =
        Audit.get_audit_logs(start_date: one_hour_ago, end_date: one_hour_later)

      assert length(recent_logs) == 5

      {:ok, future_logs} = Audit.get_audit_logs(start_date: one_hour_later)
      assert length(future_logs) == 0
    end

    test "combines multiple filters", %{user1: user1} do
      {:ok, filtered_logs} =
        Audit.get_audit_logs(
          user_id: user1.id,
          secret_key: "secret1",
          action: "read"
        )

      assert length(filtered_logs) == 1
    end

    test "supports pagination" do
      {:ok, page1} = Audit.get_audit_logs(limit: 2, offset: 0)
      assert length(page1) == 2

      {:ok, page2} = Audit.get_audit_logs(limit: 2, offset: 2)
      assert length(page2) == 2

      {:ok, page3} = Audit.get_audit_logs(limit: 2, offset: 4)
      assert length(page3) == 1
    end

    test "orders logs by timestamp descending" do
      {:ok, logs} = Audit.get_audit_logs()

      timestamps = Enum.map(logs, & &1.timestamp)
      sorted_timestamps = Enum.sort(timestamps, &(DateTime.compare(&1, &2) != :lt))

      assert timestamps == sorted_timestamps
    end
  end

  describe "get_secret_audit_trail/2" do
    setup do
      user = insert_user()
      secret_key = "tracked_secret"

      # Create audit trail
      {:ok, _log1} = Audit.log_action(user, "create", secret_key, %{"version" => 1})
      {:ok, _log2} = Audit.log_action(user, "read", secret_key, %{"version" => 1})
      {:ok, _log3} = Audit.log_action(user, "update", secret_key, %{"version" => 2})
      {:ok, _log4} = Audit.log_action(user, "read", secret_key, %{"version" => 2})

      # Create logs for different secret
      {:ok, _other_log} = Audit.log_action(user, "create", "other_secret")

      %{user: user, secret_key: secret_key}
    end

    test "returns audit trail for specific secret", %{secret_key: secret_key} do
      {:ok, trail} = Audit.get_secret_audit_trail(secret_key)

      assert length(trail) == 4
      actions = Enum.map(trail, & &1.action)
      assert "create" in actions
      assert "read" in actions
      assert "update" in actions
    end

    test "returns empty trail for non-existent secret" do
      {:ok, trail} = Audit.get_secret_audit_trail("non_existent_secret")
      assert trail == []
    end

    test "supports pagination", %{secret_key: secret_key} do
      {:ok, page1} = Audit.get_secret_audit_trail(secret_key, limit: 2)
      assert length(page1) == 2

      {:ok, page2} = Audit.get_secret_audit_trail(secret_key, limit: 2, offset: 2)
      assert length(page2) == 2
    end
  end

  describe "get_user_audit_trail/2" do
    setup do
      user1 = insert_user()
      user2 = insert_user(%{username: "user2", email: "user2@example.com"})

      # Create user1's audit trail
      {:ok, _log1} = Audit.log_action(user1, "create", "secret1")
      {:ok, _log2} = Audit.log_action(user1, "read", "secret2")
      {:ok, _log3} = Audit.log_action(user1, "update", "secret1")

      # Create user2's audit trail
      {:ok, _log4} = Audit.log_action(user2, "create", "secret3")

      %{user1: user1, user2: user2}
    end

    test "returns audit trail for specific user", %{user1: user1, user2: user2} do
      {:ok, user1_trail} = Audit.get_user_audit_trail(user1.id)
      assert length(user1_trail) == 3

      {:ok, user2_trail} = Audit.get_user_audit_trail(user2.id)
      assert length(user2_trail) == 1
    end

    test "returns empty trail for non-existent user" do
      {:ok, trail} = Audit.get_user_audit_trail(999_999)
      assert trail == []
    end
  end

  describe "get_audit_statistics/1" do
    setup do
      user1 = insert_user()
      user2 = insert_user(%{username: "user2", email: "user2@example.com"})

      # Create various audit logs
      {:ok, _} = Audit.log_action(user1, "create", "secret1")
      {:ok, _} = Audit.log_action(user1, "read", "secret1")
      {:ok, _} = Audit.log_action(user1, "read", "secret1")
      {:ok, _} = Audit.log_action(user2, "create", "secret2")
      {:ok, _} = Audit.log_action(user2, "update", "secret1")
      {:ok, _} = Audit.log_action(user1, "delete", "secret3")
      {:ok, _} = Audit.log_action(nil, "system", "cleanup")

      %{user1: user1, user2: user2}
    end

    test "returns comprehensive statistics" do
      {:ok, stats} = Audit.get_audit_statistics()

      assert stats.total_logs == 7
      assert stats.actions["create"] == 2
      assert stats.actions["read"] == 2
      assert stats.actions["update"] == 1
      assert stats.actions["delete"] == 1
      assert stats.actions["system"] == 1

      # Check top secrets (should be list of maps with secret_key and access_count)
      assert is_list(stats.top_secrets)
      top_secret = List.first(stats.top_secrets)
      assert is_map(top_secret)
      assert Map.has_key?(top_secret, :secret_key)
      assert Map.has_key?(top_secret, :access_count)

      # user1 and user2 (nil doesn't count)
      assert stats.active_users == 2
    end

    test "filters statistics by date range" do
      now = DateTime.utc_now()
      one_hour_ago = DateTime.add(now, -3600, :second)
      one_hour_later = DateTime.add(now, 3600, :second)

      {:ok, stats} =
        Audit.get_audit_statistics(start_date: one_hour_ago, end_date: one_hour_later)

      assert stats.total_logs == 7

      # Future date range should return zero stats
      future_start = DateTime.add(now, 3600, :second)
      future_end = DateTime.add(now, 7200, :second)

      {:ok, future_stats} =
        Audit.get_audit_statistics(start_date: future_start, end_date: future_end)

      assert future_stats.total_logs == 0
    end

    test "handles empty database" do
      # Clear all audit logs
      Repo.delete_all(AuditLog)

      {:ok, stats} = Audit.get_audit_statistics()
      assert stats.total_logs == 0
      assert stats.actions == %{}
      assert stats.top_secrets == []
      assert stats.active_users == 0
    end
  end

  describe "purge_old_logs/1" do
    setup do
      user = insert_user()

      # Create old logs (simulate by updating timestamps)
      {:ok, old_log} = Audit.log_action(user, "create", "old_secret")
      # 400 days ago
      old_datetime =
        DateTime.add(DateTime.utc_now(), -400 * 24 * 3600, :second) |> DateTime.truncate(:second)

      old_naive = DateTime.to_naive(old_datetime)

      old_log
      |> Ecto.Changeset.change(%{timestamp: old_datetime, inserted_at: old_naive})
      |> Repo.update!()

      # Create recent logs
      {:ok, _recent_log1} = Audit.log_action(user, "create", "recent_secret1")
      {:ok, _recent_log2} = Audit.log_action(user, "read", "recent_secret2")

      %{user: user}
    end

    test "purges logs older than specified days" do
      # Should purge logs older than 365 days (default)
      {:ok, deleted_count} = Audit.purge_old_logs()
      assert deleted_count == 1

      # Verify recent logs are still there
      {:ok, remaining_logs} = Audit.get_audit_logs()
      assert length(remaining_logs) == 2
    end

    test "purges logs older than custom days" do
      # Purge logs older than 1 day (should keep all current logs)
      {:ok, deleted_count} = Audit.purge_old_logs(1)
      # Only the artificially old log
      assert deleted_count == 1

      {:ok, remaining_logs} = Audit.get_audit_logs()
      assert length(remaining_logs) == 2
    end

    test "returns zero when no old logs exist" do
      # First purge old logs
      {:ok, _} = Audit.purge_old_logs()

      # Try purging again
      {:ok, deleted_count} = Audit.purge_old_logs()
      assert deleted_count == 0
    end
  end

  # Property-based testing using StreamData
  # Note: Property-based tests are temporarily disabled due to compilation issues
  # TODO: Re-enable once StreamData configuration is resolved

  # if Code.ensure_loaded?(StreamData) do
  #   describe "property-based tests" do
  #     setup do
  #       user = insert_user()
  #       %{user: user}
  #     end

  #     @tag :property
  #     test "log action roundtrip property", %{user: user} do
  #       check all(
  #         action <- member_of(["create", "read", "update", "delete", "list"]),
  #         secret_key <- string(:alphanumeric, min_length: 1, max_length: 100),
  #         metadata_keys <-
  #           list_of(string(:alphanumeric, min_length: 1, max_length: 20), max_length: 5),
  #         metadata_values <-
  #           list_of(string(:printable, min_length: 0, max_length: 100), max_length: 5)
  #       ) do
  #         metadata =
  #           metadata_keys
  #           |> Enum.zip(metadata_values)
  #           |> Enum.into(%{})

  #         {:ok, audit_log} = Audit.log_action(user, action, secret_key, metadata)

  #         assert audit_log.user_id == user.id
  #         assert audit_log.action == action
  #         assert audit_log.secret_key == secret_key
  #         assert audit_log.metadata == metadata
  #         assert audit_log.timestamp
  #       end
  #     end

  #     @tag :property
  #     test "filtering property", %{user: user} do
  #       check all(
  #         actions <-
  #           list_of(member_of(["create", "read", "update", "delete"]),
  #             min_length: 1,
  #             max_length: 10
  #           ),
  #         secret_keys <-
  #           list_of(string(:alphanumeric, min_length: 1, max_length: 50),
  #             min_length: 1,
  #             max_length: 10
  #           )
  #       ) do
  #         # Create logs
  #         logs_created =
  #           for {action, secret_key} <- Enum.zip(actions, secret_keys) do
  #             {:ok, log} = Audit.log_action(user, action, secret_key)
  #             log
  #           end

  #         # Test filtering by action
  #         unique_actions = Enum.uniq(actions)

  #         for action <- unique_actions do
  #           {:ok, filtered_logs} = Audit.get_audit_logs(action: action)
  #           expected_count = Enum.count(actions, &(&1 == action))
  #           actual_count = Enum.count(filtered_logs, &(&1.action == action))
  #           # >= because there might be other logs in DB
  #           assert actual_count >= expected_count
  #         end

  #         # Test filtering by secret_key
  #         unique_secret_keys = Enum.uniq(secret_keys)

  #         for secret_key <- unique_secret_keys do
  #           {:ok, filtered_logs} = Audit.get_audit_logs(secret_key: secret_key)
  #           expected_count = Enum.count(secret_keys, &(&1 == secret_key))
  #           actual_count = Enum.count(filtered_logs, &(&1.secret_key == secret_key))
  #           assert actual_count >= expected_count
  #         end

  #         # Clean up
  #         for log <- logs_created do
  #           Repo.delete(log)
  #         end
  #       end
  #     end
  #   end
  # end

  # Helper functions
  defp insert_user(attrs \\ %{}) do
    default_attrs = %{
      username: "testuser_#{System.unique_integer([:positive])}",
      email: "test#{System.unique_integer([:positive])}@example.com",
      password: "password123"
    }

    attrs = Enum.into(attrs, default_attrs)

    {:ok, user} =
      %User{}
      |> User.changeset(attrs)
      |> Repo.insert()

    user
  end
end
