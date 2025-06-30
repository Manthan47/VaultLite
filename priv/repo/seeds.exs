# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     VaultLite.Repo.insert!(%VaultLite.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias VaultLite.{Repo, User, Role}

# Only create admin user if no users exist (bootstrap scenario)
case Repo.aggregate(User, :count, :id) do
  0 ->
    IO.puts("🚀 No users found. Creating initial admin user...")

    # Get admin credentials from environment variables or use defaults
    admin_username = System.get_env("ADMIN_USERNAME") || "admin"
    admin_email = System.get_env("ADMIN_EMAIL") || "admin@vaultlite.local"
    admin_password = System.get_env("ADMIN_PASSWORD") || "VaultLite123!!"

    # Create admin user
    admin_user_attrs = %{
      username: admin_username,
      email: admin_email,
      password: admin_password,
      active: true
    }

    {:ok, admin_user} =
      %User{}
      |> User.changeset(admin_user_attrs)
      |> Repo.insert()

    IO.puts("✅ Created admin user: #{admin_user.username} (#{admin_user.email})")

    # Create admin role for the user
    admin_role_attrs = %{
      name: "system_admin",
      permissions: ["admin", "read", "write", "delete"],
      # Access to everything
      path_patterns: ["*"],
      user_id: admin_user.id
    }

    {:ok, admin_role} =
      %Role{}
      |> Role.changeset(admin_role_attrs)
      |> Repo.insert()

    IO.puts("✅ Created admin role: #{admin_role.name} with full permissions")

    IO.puts("""

    🎉 Initial admin setup complete!

    Admin Credentials:
    ------------------
    Username: #{admin_user.username}
    Email:    #{admin_user.email}
    Password: #{admin_password}

    ⚠️  IMPORTANT SECURITY NOTES:
    1. Change the admin password immediately after first login
    2. Consider setting custom admin credentials via environment variables:
       - ADMIN_USERNAME=your_admin_username
       - ADMIN_EMAIL=your_admin_email
       - ADMIN_PASSWORD=your_secure_password
    3. The default password is for development only!

    You can now:
    1. Login at POST /api/auth/login
    2. Create additional users and roles
    3. Manage the secrets system
    """)

  count ->
    IO.puts("👥 Found #{count} existing users. Skipping admin creation.")
    IO.puts("💡 Admin user already exists or database is already populated.")
end

# Create some example roles for demonstration (only if admin user was created)
if Repo.aggregate(User, :count, :id) == 1 do
  IO.puts("\n📝 Creating example roles for demonstration...")

  admin_user = Repo.get_by!(User, username: System.get_env("ADMIN_USERNAME") || "admin")

  example_roles = [
    %{
      name: "developer",
      permissions: ["read", "write"],
      path_patterns: ["secrets/dev/*", "secrets/staging/*"],
      user_id: admin_user.id,
      description: "Developer access to dev and staging secrets"
    },
    %{
      name: "readonly_user",
      permissions: ["read"],
      path_patterns: ["secrets/shared/*"],
      user_id: admin_user.id,
      description: "Read-only access to shared secrets"
    },
    %{
      name: "production_operator",
      permissions: ["read", "write"],
      path_patterns: ["secrets/prod/*"],
      user_id: admin_user.id,
      description: "Production secrets management"
    }
  ]

  Enum.each(example_roles, fn role_attrs ->
    {:ok, role} =
      %Role{}
      |> Role.changeset(role_attrs)
      |> Repo.insert()

    IO.puts("✅ Created example role: #{role.name}")
  end)

  IO.puts("\n🎯 Example roles created for demonstration purposes")
end
