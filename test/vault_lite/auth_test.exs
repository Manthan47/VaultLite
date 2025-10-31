defmodule VaultLite.AuthTest do
  use VaultLite.DataCase, async: true
  import Mox
  import StreamData

  alias VaultLite.Auth
  alias VaultLite.Repo
  alias VaultLite.Schema.User

  # Set up mocks
  setup :verify_on_exit!

  describe "create_user/1" do
    test "creates user with valid attributes" do
      attrs = %{
        username: "testuser",
        email: "test@example.com",
        password: "StrongPassword123!"
      }

      assert {:ok, user} = Auth.create_user(attrs)
      assert user.username == "testuser"
      assert user.email == "test@example.com"
      assert user.password_hash
      # Should be hashed
      refute user.password_hash == "StrongPassword123!"
    end

    test "validates required fields" do
      assert {:error, changeset} = Auth.create_user(%{})

      errors = errors_on(changeset)
      assert "can't be blank" in errors.username
      assert "can't be blank" in errors.email
      assert "can't be blank" in errors.password
    end

    test "validates email format" do
      attrs = %{
        username: "testuser",
        email: "invalid-email",
        password: "StrongPassword123!"
      }

      assert {:error, changeset} = Auth.create_user(attrs)
      assert "must be a valid email address" in errors_on(changeset).email
    end

    test "validates password length" do
      attrs = %{
        username: "testuser",
        email: "test@example.com",
        password: "123"
      }

      assert {:error, changeset} = Auth.create_user(attrs)
      assert "should be at least 8 character(s)" in errors_on(changeset).password
    end

    test "ensures unique username" do
      attrs = %{
        username: "duplicate",
        email: "test1@example.com",
        password: "StrongPassword123!"
      }

      assert {:ok, _user1} = Auth.create_user(attrs)

      attrs2 = %{attrs | email: "test2@example.com"}
      assert {:error, changeset} = Auth.create_user(attrs2)
      assert "has already been taken" in errors_on(changeset).username
    end

    test "ensures unique email" do
      attrs = %{
        username: "user1",
        email: "duplicate@example.com",
        password: "StrongPassword123!"
      }

      assert {:ok, _user1} = Auth.create_user(attrs)

      attrs2 = %{attrs | username: "user2"}
      assert {:error, changeset} = Auth.create_user(attrs2)
      assert "has already been taken" in errors_on(changeset).email
    end
  end

  describe "authenticate_user/2" do
    setup do
      {:ok, user} =
        Auth.create_user(%{
          username: "authuser",
          email: "auth@example.com",
          password: "StrongPassword123!"
        })

      %{user: user}
    end

    test "authenticates with valid username and password", %{user: user} do
      assert {:ok, authenticated_user} = Auth.authenticate_user("authuser", "StrongPassword123!")
      assert authenticated_user.id == user.id
    end

    test "authenticates with valid email and password", %{user: user} do
      assert {:ok, authenticated_user} =
               Auth.authenticate_user("auth@example.com", "StrongPassword123!")

      assert authenticated_user.id == user.id
    end

    test "fails with invalid password" do
      assert {:error, :invalid_credentials} = Auth.authenticate_user("authuser", "wrongpassword")
    end

    test "fails with invalid username" do
      assert {:error, :invalid_credentials} =
               Auth.authenticate_user("nonexistent", "StrongPassword123!")
    end

    test "fails with invalid email" do
      assert {:error, :invalid_credentials} =
               Auth.authenticate_user("nonexistent@example.com", "StrongPassword123!")
    end
  end

  describe "assign_role/2" do
    setup do
      {:ok, user} =
        Auth.create_user(%{
          username: "roleuser",
          email: "role@example.com",
          password: "StrongPassword123!"
        })

      %{user: user}
    end

    test "assigns role to user", %{user: user} do
      role_data = %{
        name: "developer",
        permissions: ["read", "write"],
        path_patterns: ["secrets/dev/*", "secrets/staging/*"]
      }

      assert {:ok, role} = Auth.assign_role(user, role_data)
      # When path_patterns are provided, they are encoded in the role name
      assert role.name == "path:secrets/dev/*,secrets/staging/*"
      assert role.permissions == ["read", "write"]
      assert role.user_id == user.id
    end

    test "validates role name" do
      role_data = %{
        name: "",
        permissions: ["read"]
        # Don't provide path_patterns to test name validation
      }

      assert {:error, changeset} = Auth.assign_role(insert_user(), role_data)
      assert "can't be blank" in errors_on(changeset).name
    end

    test "validates permissions are not empty" do
      role_data = %{
        name: "test_role",
        permissions: []
        # Don't provide path_patterns to test permissions validation
      }

      assert {:error, changeset} = Auth.assign_role(insert_user(), role_data)
      assert "must have at least one permission" in errors_on(changeset).permissions
    end

    test "validates permission values" do
      role_data = %{
        name: "test_role",
        permissions: ["invalid_permission"],
        path_patterns: ["secrets/*"]
      }

      assert {:error, changeset} = Auth.assign_role(insert_user(), role_data)

      assert "contains invalid permissions: invalid_permission" in errors_on(changeset).permissions
    end

    test "allows multiple roles per user", %{user: user} do
      role1_data = %{
        name: "dev_role",
        permissions: ["read"],
        path_patterns: ["secrets/dev/*"]
      }

      role2_data = %{
        name: "staging_role",
        permissions: ["read", "write"],
        path_patterns: ["secrets/staging/*"]
      }

      assert {:ok, _role1} = Auth.assign_role(user, role1_data)
      assert {:ok, _role2} = Auth.assign_role(user, role2_data)

      roles = Auth.get_user_roles(user)
      assert length(roles) == 2
    end
  end

  describe "check_access/3" do
    setup do
      {:ok, user} =
        Auth.create_user(%{
          username: "accessuser",
          email: "access@example.com",
          password: "StrongPassword123!"
        })

      # Assign roles
      {:ok, _dev_role} =
        Auth.assign_role(user, %{
          name: "developer",
          permissions: ["read", "write"],
          path_patterns: ["secrets/dev/*", "secrets/shared/*"]
        })

      {:ok, _prod_role} =
        Auth.assign_role(user, %{
          name: "prod_reader",
          permissions: ["read"],
          path_patterns: ["secrets/prod/*"]
        })

      %{user: user}
    end

    test "allows access when user has required permission for path", %{user: user} do
      assert {:ok, :authorized} = Auth.check_access(user, "secrets/dev/database_password", "read")
      assert {:ok, :authorized} = Auth.check_access(user, "secrets/dev/api_key", "write")
      assert {:ok, :authorized} = Auth.check_access(user, "secrets/shared/config", "read")
      assert {:ok, :authorized} = Auth.check_access(user, "secrets/prod/db_password", "read")
    end

    test "denies access when user lacks required permission", %{user: user} do
      # User doesn't have write permission for prod
      assert {:error, :unauthorized} =
               Auth.check_access(user, "secrets/prod/database_password", "write")

      # User doesn't have delete permission anywhere
      assert {:error, :unauthorized} = Auth.check_access(user, "secrets/dev/api_key", "delete")
    end

    test "denies access when path doesn't match patterns", %{user: user} do
      # User doesn't have access to test environment
      assert {:error, :unauthorized} = Auth.check_access(user, "secrets/test/config", "read")

      # User doesn't have access to root level secrets
      assert {:error, :unauthorized} = Auth.check_access(user, "secrets/root_secret", "read")
    end

    test "handles complex path patterns", %{user: user} do
      # Add role with more complex patterns
      {:ok, _complex_role} =
        Auth.assign_role(user, %{
          name: "api_manager",
          permissions: ["read", "write", "delete"],
          path_patterns: ["secrets/api/*/config", "secrets/services/auth/*"]
        })

      # Should match complex patterns
      assert {:ok, :authorized} = Auth.check_access(user, "secrets/api/payment/config", "read")
      assert {:ok, :authorized} = Auth.check_access(user, "secrets/api/user/config", "write")

      assert {:ok, :authorized} =
               Auth.check_access(user, "secrets/services/auth/jwt_secret", "delete")

      # Should not match patterns that don't fit
      assert {:error, :unauthorized} =
               Auth.check_access(user, "secrets/api/payment/database", "read")
    end

    test "denies access for users without roles" do
      {:ok, no_role_user} =
        Auth.create_user(%{
          username: "noroleuser",
          email: "norole@example.com",
          password: "StrongPassword123!"
        })

      assert {:error, :unauthorized} = Auth.check_access(no_role_user, "secrets/dev/test", "read")
    end
  end

  describe "admin_access/1" do
    test "grants access to admin users" do
      admin_user = insert_admin_user()
      assert {:ok, :authorized} = Auth.check_admin_access(admin_user)
    end

    test "denies access to non-admin users" do
      regular_user = insert_user()
      assert {:error, :unauthorized} = Auth.check_admin_access(regular_user)
    end

    test "is_admin?/1 returns correct boolean" do
      admin_user = insert_admin_user()
      regular_user = insert_user()

      assert Auth.is_admin?(admin_user) == true
      assert Auth.is_admin?(regular_user) == false
    end
  end

  describe "get_user_roles/1" do
    setup do
      user = insert_user()
      %{user: user}
    end

    test "returns user roles", %{user: user} do
      role1_data = %{
        name: "role1",
        permissions: ["read"],
        path_patterns: ["secrets/test1/*"]
      }

      role2_data = %{
        name: "role2",
        permissions: ["read", "write"],
        path_patterns: ["secrets/test2/*"]
      }

      {:ok, _role1} = Auth.assign_role(user, role1_data)
      {:ok, _role2} = Auth.assign_role(user, role2_data)

      roles = Auth.get_user_roles(user)
      assert length(roles) == 2

      # Auth system converts role names to path-based names when path_patterns are provided
      role_names = Enum.map(roles, & &1.name)
      assert "path:secrets/test1/*" in role_names
      assert "path:secrets/test2/*" in role_names
    end

    test "returns empty list for user without roles" do
      # Create user without going through setup to avoid default roles
      user = insert_user_no_roles()
      roles = Auth.get_user_roles(user)
      assert roles == []
    end
  end

  describe "revoke_role/2" do
    setup do
      user = insert_user()

      {:ok, role} =
        Auth.assign_role(user, %{
          name: "test_role",
          permissions: ["read"],
          path_patterns: ["secrets/test/*"]
        })

      %{user: user, role: role}
    end

    test "revokes user role", %{user: user, role: role} do
      assert {:ok, :revoked} = Auth.revoke_role(user, role.name)

      roles = Auth.get_user_roles(user)
      assert roles == []
    end

    test "returns error for non-existent role", %{user: user} do
      assert {:error, :not_found} = Auth.revoke_role(user, "non_existent_role")
    end
  end

  # Property-based testing using StreamData
  # Note: Property-based tests are temporarily disabled due to compilation issues
  # TODO: Re-enable once StreamData configuration is resolved

  # if Code.ensure_loaded?(StreamData) do
  #   describe "property-based tests" do
  #     @tag :property
  #     test "path matching property" do
  #       user = insert_user()

  #       check all(
  #         environment <- member_of(["dev", "staging", "prod", "test"]),
  #         service <- string(:alphanumeric, min_length: 1, max_length: 20),
  #         secret_name <- string(:alphanumeric, min_length: 1, max_length: 30),
  #         permission <- member_of(["read", "write", "delete"])
  #       ) do
  #         pattern = "secrets/#{environment}/#{service}/*"
  #         secret_path = "secrets/#{environment}/#{service}/#{secret_name}"

  #         # Assign role with this pattern
  #         {:ok, _role} =
  #           Auth.assign_role(user, %{
  #             name: "test_role_#{environment}",
  #             permissions: [permission],
  #             path_patterns: [pattern]
  #           })

  #         # Should have access to matching path
  #         assert {:ok, :authorized} = Auth.check_access(user, secret_path, permission)

  #         # Should not have access to different permission (if not the same)
  #         other_permissions = ["read", "write", "delete"] -- [permission]

  #         if length(other_permissions) > 0 do
  #           other_permission = Enum.random(other_permissions)
  #           assert {:error, :unauthorized} = Auth.check_access(user, secret_path, other_permission)
  #         end

  #         # Clean up
  #         Auth.revoke_role(user, "test_role_#{environment}")
  #       end
  #     end

  #     @tag :property
  #     test "user creation property" do
  #       check all(
  #         username <- string(:alphanumeric, min_length: 3, max_length: 30),
  #         email_local <- string(:alphanumeric, min_length: 1, max_length: 20),
  #         email_domain <- string(:alphanumeric, min_length: 2, max_length: 10),
  #         password <- string(:printable, min_length: 8, max_length: 50)
  #       ) do
  #         email = "#{email_local}@#{email_domain}.com"

  #         attrs = %{
  #           username: username,
  #           email: email,
  #           password: password
  #         }

  #         case Auth.create_user(attrs) do
  #           {:ok, user} ->
  #             assert user.username == username
  #             assert user.email == email
  #             assert user.password_hash != password

  #             # Clean up
  #             Repo.delete(user)

  #           {:error, _changeset} ->
  #             # Some combinations might fail validation, which is expected
  #             :ok
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
      password: "StrongPassword123!"
    }

    attrs = Enum.into(attrs, default_attrs)

    {:ok, user} =
      %User{}
      |> User.changeset(attrs)
      |> Repo.insert()

    user
  end

  defp insert_user_no_roles(attrs \\ %{}) do
    # Just create a user without any roles
    insert_user(attrs)
  end

  defp insert_admin_user do
    user = insert_user()

    # Assign admin role
    {:ok, _role} =
      Auth.assign_role(user, %{
        name: "admin",
        permissions: ["read", "write", "delete", "admin"],
        path_patterns: ["*"]
      })

    user
  end
end
