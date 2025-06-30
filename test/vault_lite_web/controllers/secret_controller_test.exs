defmodule VaultLiteWeb.SecretControllerTest do
  use VaultLiteWeb.ConnCase, async: true
  import Mox

  alias VaultLite.{Auth, Secrets, Guardian}

  # Set up mocks
  setup :verify_on_exit!

  setup %{conn: conn} do
    # Create test user and get JWT token
    {:ok, user} =
      Auth.create_user(%{
        username: "testuser_#{System.unique_integer([:positive])}",
        email: "test#{System.unique_integer([:positive])}@example.com",
        password: "password123"
      })

    # Assign appropriate role for testing
    {:ok, _role} =
      Auth.assign_role(user, %{
        name: "test_role",
        permissions: ["read", "write", "delete"],
        # Allow access to all secrets for testing
        path_patterns: ["*"]
      })

    {:ok, token, _claims} = Guardian.encode_and_sign(user)

    authenticated_conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer #{token}")

    %{conn: authenticated_conn, user: user, token: token}
  end

  describe "POST /api/secrets" do
    test "creates secret with valid data", %{conn: conn} do
      secret_params = %{
        "key" => "test_secret",
        "value" => "secret_value_123",
        "metadata" => %{
          "environment" => "test",
          "description" => "Test secret"
        }
      }

      conn = post(conn, ~p"/api/secrets", secret_params)

      assert %{
               "status" => "success",
               "data" => %{
                 "key" => "test_secret",
                 "version" => 1,
                 "metadata" => %{
                   "environment" => "test",
                   "description" => "Test secret"
                 }
               }
             } = json_response(conn, 201)
    end

    test "returns error with invalid data", %{conn: conn} do
      invalid_params = %{
        "key" => "",
        "value" => "secret_value"
      }

      conn = post(conn, ~p"/api/secrets", invalid_params)

      assert %{
               "status" => "error",
               "errors" => %{
                 "key" => ["can't be blank"]
               }
             } = json_response(conn, 422)
    end

    test "returns error for duplicate key", %{conn: conn} do
      secret_params = %{
        "key" => "duplicate_secret",
        "value" => "value1"
      }

      # Create first secret
      post(conn, ~p"/api/secrets", secret_params)

      # Try to create duplicate
      conn = post(conn, ~p"/api/secrets", secret_params)

      assert %{
               "status" => "error",
               "errors" => %{
                 "key" => ["has already been taken"]
               }
             } = json_response(conn, 422)
    end

    test "requires authentication", %{conn: _conn} do
      # Remove authentication header
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")

      secret_params = %{
        "key" => "test_secret",
        "value" => "secret_value"
      }

      conn = post(conn, ~p"/api/secrets", secret_params)

      assert %{
               "error" => "unauthenticated"
             } = json_response(conn, 401)
    end
  end

  describe "GET /api/secrets/:key" do
    setup %{conn: conn, user: user} do
      # Create a test secret
      {:ok, _secret} =
        Secrets.create_secret("test_get_secret", "secret_value", user, %{
          "environment" => "test"
        })

      %{conn: conn, user: user}
    end

    test "retrieves existing secret", %{conn: conn} do
      conn = get(conn, ~p"/api/secrets/test_get_secret")

      assert %{
               "status" => "success",
               "data" => %{
                 "key" => "test_get_secret",
                 "value" => "secret_value",
                 "version" => 1,
                 "metadata" => %{
                   "environment" => "test"
                 }
               }
             } = json_response(conn, 200)
    end

    test "returns 404 for non-existent secret", %{conn: conn} do
      conn = get(conn, ~p"/api/secrets/non_existent")

      assert %{
               "status" => "error",
               "message" => "Secret not found"
             } = json_response(conn, 404)
    end

    test "requires authentication", %{} do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")

      conn = get(conn, ~p"/api/secrets/test_get_secret")

      assert %{
               "error" => "unauthenticated"
             } = json_response(conn, 401)
    end
  end

  describe "PUT /api/secrets/:key" do
    setup %{conn: conn, user: user} do
      # Create a test secret
      {:ok, _secret} = Secrets.create_secret("test_update_secret", "original_value", user)

      %{conn: conn, user: user}
    end

    test "updates existing secret", %{conn: conn} do
      update_params = %{
        "value" => "updated_value",
        "metadata" => %{
          "updated_by" => "test",
          "reason" => "Security rotation"
        }
      }

      conn = put(conn, ~p"/api/secrets/test_update_secret", update_params)

      assert %{
               "status" => "success",
               "data" => %{
                 "key" => "test_update_secret",
                 "version" => 2,
                 "metadata" => %{
                   "updated_by" => "test",
                   "reason" => "Security rotation"
                 }
               }
             } = json_response(conn, 200)
    end

    test "returns 404 for non-existent secret", %{conn: conn} do
      update_params = %{
        "value" => "new_value"
      }

      conn = put(conn, ~p"/api/secrets/non_existent", update_params)

      assert %{
               "status" => "error",
               "message" => "Secret not found"
             } = json_response(conn, 404)
    end

    test "validates value is provided", %{conn: conn} do
      invalid_params = %{
        "metadata" => %{"test" => "value"}
      }

      conn = put(conn, ~p"/api/secrets/test_update_secret", invalid_params)

      assert %{
               "status" => "error",
               "errors" => %{
                 "value" => ["can't be blank"]
               }
             } = json_response(conn, 422)
    end
  end

  describe "DELETE /api/secrets/:key" do
    setup %{conn: conn, user: user} do
      # Create a test secret
      {:ok, _secret} = Secrets.create_secret("test_delete_secret", "value_to_delete", user)

      %{conn: conn, user: user}
    end

    test "deletes existing secret", %{conn: conn} do
      conn = delete(conn, ~p"/api/secrets/test_delete_secret")

      assert %{
               "status" => "success",
               "message" => "Secret deleted successfully"
             } = json_response(conn, 200)

      # Verify secret is no longer accessible
      conn = build_authenticated_conn()
      conn = get(conn, ~p"/api/secrets/test_delete_secret")
      assert json_response(conn, 404)
    end

    test "returns 404 for non-existent secret", %{conn: conn} do
      conn = delete(conn, ~p"/api/secrets/non_existent")

      assert %{
               "status" => "error",
               "message" => "Secret not found"
             } = json_response(conn, 404)
    end

    test "returns 404 for already deleted secret", %{conn: conn} do
      # Delete the secret first
      delete(conn, ~p"/api/secrets/test_delete_secret")

      # Try to delete again
      conn = build_authenticated_conn()
      conn = delete(conn, ~p"/api/secrets/test_delete_secret")

      assert %{
               "status" => "error",
               "message" => "Secret not found"
             } = json_response(conn, 404)
    end
  end

  describe "GET /api/secrets" do
    setup %{conn: conn, user: user} do
      # Create multiple test secrets
      {:ok, _secret1} = Secrets.create_secret("list_secret_1", "value1", user)
      {:ok, _secret2} = Secrets.create_secret("list_secret_2", "value2", user)
      {:ok, _secret3} = Secrets.create_secret("list_secret_3", "value3", user)

      %{conn: conn, user: user}
    end

    test "lists all accessible secrets", %{conn: conn} do
      conn = get(conn, ~p"/api/secrets")

      assert %{
               "status" => "success",
               "data" => secrets,
               "pagination" => %{
                 "page" => 1,
                 "limit" => 50,
                 "count" => count
               }
             } = json_response(conn, 200)

      assert is_list(secrets)
      # At least our test secrets
      assert count >= 3

      secret_keys = Enum.map(secrets, & &1["key"])
      assert "list_secret_1" in secret_keys
      assert "list_secret_2" in secret_keys
      assert "list_secret_3" in secret_keys
    end

    test "supports pagination", %{conn: conn} do
      conn = get(conn, ~p"/api/secrets?page=1&limit=2")

      assert %{
               "status" => "success",
               "data" => secrets,
               "pagination" => %{
                 "page" => 1,
                 "limit" => 2,
                 "count" => _count
               }
             } = json_response(conn, 200)

      assert length(secrets) == 2
    end

    test "validates pagination parameters", %{conn: conn} do
      conn = get(conn, ~p"/api/secrets?page=0&limit=1000")

      assert %{
               "status" => "error",
               "message" => "Invalid pagination parameters"
             } = json_response(conn, 422)
    end
  end

  describe "GET /api/secrets/:key/versions" do
    setup %{conn: conn, user: user} do
      # Create a secret with multiple versions
      {:ok, _secret} = Secrets.create_secret("versioned_secret", "v1", user)
      {:ok, _secret} = Secrets.update_secret("versioned_secret", "v2", user)
      {:ok, _secret} = Secrets.update_secret("versioned_secret", "v3", user)

      %{conn: conn, user: user}
    end

    test "returns all versions of a secret", %{conn: conn} do
      conn = get(conn, ~p"/api/secrets/versioned_secret/versions")

      assert %{
               "status" => "success",
               "data" => versions
             } = json_response(conn, 200)

      assert length(versions) == 3
      version_numbers = Enum.map(versions, & &1["version"])
      # Should be in descending order
      assert version_numbers == [3, 2, 1]
    end

    test "returns 404 for non-existent secret", %{conn: conn} do
      conn = get(conn, ~p"/api/secrets/non_existent/versions")

      assert %{
               "status" => "error",
               "message" => "Secret not found"
             } = json_response(conn, 404)
    end
  end

  describe "GET /api/secrets/:key/versions/:version" do
    setup %{conn: conn, user: user} do
      # Create a secret with multiple versions
      {:ok, _secret} = Secrets.create_secret("specific_version_secret", "version_1_value", user)
      {:ok, _secret} = Secrets.update_secret("specific_version_secret", "version_2_value", user)

      %{conn: conn, user: user}
    end

    test "returns specific version of a secret", %{conn: conn} do
      conn = get(conn, ~p"/api/secrets/specific_version_secret/versions/1")

      assert %{
               "status" => "success",
               "data" => %{
                 "key" => "specific_version_secret",
                 "value" => "version_1_value",
                 "version" => 1
               }
             } = json_response(conn, 200)
    end

    test "returns different value for different version", %{conn: conn} do
      conn = get(conn, ~p"/api/secrets/specific_version_secret/versions/2")

      assert %{
               "status" => "success",
               "data" => %{
                 "key" => "specific_version_secret",
                 "value" => "version_2_value",
                 "version" => 2
               }
             } = json_response(conn, 200)
    end

    test "returns 404 for invalid version", %{conn: conn} do
      conn = get(conn, ~p"/api/secrets/specific_version_secret/versions/999")

      assert %{
               "status" => "error",
               "message" => "Secret version not found"
             } = json_response(conn, 404)
    end

    test "returns 404 for non-existent secret", %{conn: conn} do
      conn = get(conn, ~p"/api/secrets/non_existent/versions/1")

      assert %{
               "status" => "error",
               "message" => "Secret not found"
             } = json_response(conn, 404)
    end
  end

  describe "authorization" do
    setup %{} do
      # Create user without permissions
      {:ok, limited_user} =
        Auth.create_user(%{
          username: "limiteduser",
          email: "limited@example.com",
          password: "password123"
        })

      # Assign limited role
      {:ok, _role} =
        Auth.assign_role(limited_user, %{
          name: "limited_role",
          permissions: ["read"],
          # Limited access
          path_patterns: ["secrets/dev/*"]
        })

      {:ok, token, _claims} = Guardian.encode_and_sign(limited_user)

      limited_conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("authorization", "Bearer #{token}")

      %{limited_conn: limited_conn, limited_user: limited_user}
    end

    test "denies access to unauthorized secrets", %{limited_conn: conn} do
      # Try to access a secret outside allowed path pattern
      conn = get(conn, ~p"/api/secrets/secrets/prod/database")

      assert %{
               "status" => "error",
               "message" => "Insufficient permissions"
             } = json_response(conn, 403)
    end

    test "denies write operations with read-only permissions", %{limited_conn: conn} do
      secret_params = %{
        "key" => "secrets/dev/test",
        "value" => "test_value"
      }

      conn = post(conn, ~p"/api/secrets", secret_params)

      assert %{
               "status" => "error",
               "message" => "Insufficient permissions"
             } = json_response(conn, 403)
    end
  end

  describe "rate limiting" do
    # Note: This would require setting up rate limiting configuration for tests
    # For now, we'll skip this as it requires additional setup
    @tag :skip
    test "respects rate limits" do
      # Implementation would depend on PlugAttack configuration
    end
  end

  describe "error handling" do
    test "handles malformed JSON", %{} do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer valid_token")

      conn = post(conn, ~p"/api/secrets", "{invalid json}")

      assert %{
               "status" => "error",
               "message" => "Invalid JSON"
             } = json_response(conn, 400)
    end

    test "handles invalid JWT token", %{} do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("authorization", "Bearer invalid_token")

      conn = get(conn, ~p"/api/secrets/test")

      assert %{
               "error" => "unauthenticated"
             } = json_response(conn, 401)
    end
  end

  # Helper functions
  defp build_authenticated_conn do
    {:ok, user} =
      Auth.create_user(%{
        username: "helperuser_#{System.unique_integer()}",
        email: "helper#{System.unique_integer()}@example.com",
        password: "password123"
      })

    {:ok, _role} =
      Auth.assign_role(user, %{
        name: "helper_role",
        permissions: ["read", "write", "delete"],
        path_patterns: ["*"]
      })

    {:ok, token, _claims} = Guardian.encode_and_sign(user)

    build_conn()
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", "Bearer #{token}")
  end
end
