defmodule Mix.Tasks.VaultLite.Admin do
  @shortdoc "Manage VaultLite admin users"

  @moduledoc """
  VaultLite admin user management tasks.

  ## Usage

      # Create an admin user interactively
      mix vault_lite.admin create

      # Create an admin user with command line arguments
      mix vault_lite.admin create --username admin --email admin@example.com --password securepass123

      # List all admin users
      mix vault_lite.admin list

      # Promote existing user to admin
      mix vault_lite.admin promote <username>

      # Remove admin privileges from user
      mix vault_lite.admin demote <username>
  """
  use Mix.Task
  alias VaultLite.{Repo, User, Role}
  import Ecto.Query

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    case args do
      ["create" | opts] -> create_admin(opts)
      ["list"] -> list_admins()
      ["promote", username] -> promote_user(username)
      ["demote", username] -> demote_user(username)
      _ -> show_help()
    end
  end

  defp create_admin(opts) do
    # Parse command line options
    {parsed_opts, _remaining, _invalid} =
      OptionParser.parse(opts,
        switches: [username: :string, email: :string, password: :string],
        aliases: [u: :username, e: :email, p: :password]
      )

    IO.puts("🔐 Creating VaultLite Admin User\n")

    # Get username
    username = parsed_opts[:username] || prompt("Enter username (default: admin): ", "admin")

    # Check if user already exists
    if Repo.get_by(User, username: username) do
      IO.puts("❌ User '#{username}' already exists!")
      System.halt(1)
    end

    # Get email
    email = parsed_opts[:email] || prompt("Enter email: ")

    if email == "" do
      IO.puts("❌ Email is required!")
      System.halt(1)
    end

    # Check if email already exists
    if Repo.get_by(User, email: email) do
      IO.puts("❌ Email '#{email}' already exists!")
      System.halt(1)
    end

    # Get password
    password = parsed_opts[:password] || secure_prompt("Enter password (min 8 chars): ")

    if String.length(password) < 8 do
      IO.puts("❌ Password must be at least 8 characters!")
      System.halt(1)
    end

    # Create user
    user_attrs = %{
      username: username,
      email: email,
      password: password,
      active: true
    }

    case User.changeset(%User{}, user_attrs) |> Repo.insert() do
      {:ok, user} ->
        IO.puts("✅ Created user: #{user.username} (#{user.email})")

        # Create admin role
        role_attrs = %{
          name: "system_admin",
          permissions: ["admin", "read", "write", "delete"],
          path_patterns: ["*"],
          user_id: user.id
        }

        case Role.changeset(%Role{}, role_attrs) |> Repo.insert() do
          {:ok, _role} ->
            IO.puts("✅ Granted admin privileges to #{user.username}")
            IO.puts("\n🎉 Admin user created successfully!")
            IO.puts("\nCredentials:")
            IO.puts("Username: #{username}")
            IO.puts("Email:    #{email}")
            IO.puts("\n⚠️  Remember to keep these credentials secure!")

          {:error, changeset} ->
            IO.puts("❌ Failed to create admin role:")
            print_errors(changeset)
            System.halt(1)
        end

      {:error, changeset} ->
        IO.puts("❌ Failed to create user:")
        print_errors(changeset)
        System.halt(1)
    end
  end

  defp list_admins do
    IO.puts("👑 VaultLite Admin Users\n")

    admins =
      from(u in User,
        join: r in Role,
        on: r.user_id == u.id,
        where: "admin" in r.permissions,
        select: {u, r},
        distinct: u.id
      )
      |> Repo.all()

    if Enum.empty?(admins) do
      IO.puts("❌ No admin users found!")
      IO.puts("💡 Create one with: mix vault_lite.admin create")
    else
      IO.puts("Found #{length(admins)} admin user(s):\n")

      Enum.each(admins, fn {user, role} ->
        status = if user.active, do: "Active", else: "Inactive"
        IO.puts("• #{user.username} (#{user.email}) - #{status}")
        IO.puts("  Role: #{role.name}")
        IO.puts("  Permissions: #{Enum.join(role.permissions, ", ")}")
        IO.puts("")
      end)
    end
  end

  defp promote_user(username) do
    case Repo.get_by(User, username: username) do
      nil ->
        IO.puts("❌ User '#{username}' not found!")
        System.halt(1)

      user ->
        # Check if user already has admin role
        existing_admin_role =
          from(r in Role,
            where: r.user_id == ^user.id and "admin" in r.permissions
          )
          |> Repo.one()

        if existing_admin_role do
          IO.puts("ℹ️  User '#{username}' already has admin privileges!")
        else
          role_attrs = %{
            name: "promoted_admin",
            permissions: ["admin", "read", "write", "delete"],
            path_patterns: ["*"],
            user_id: user.id
          }

          case Role.changeset(%Role{}, role_attrs) |> Repo.insert() do
            {:ok, _role} ->
              IO.puts("✅ Promoted '#{username}' to admin!")

            {:error, changeset} ->
              IO.puts("❌ Failed to promote user:")
              print_errors(changeset)
              System.halt(1)
          end
        end
    end
  end

  defp demote_user(username) do
    case Repo.get_by(User, username: username) do
      nil ->
        IO.puts("❌ User '#{username}' not found!")
        System.halt(1)

      user ->
        admin_roles =
          from(r in Role,
            where: r.user_id == ^user.id and "admin" in r.permissions
          )
          |> Repo.all()

        if Enum.empty?(admin_roles) do
          IO.puts("ℹ️  User '#{username}' doesn't have admin privileges!")
        else
          # Count total admins
          total_admins =
            from(r in Role, where: "admin" in r.permissions, distinct: true, select: r.user_id)
            |> Repo.aggregate(:count, :user_id)

          if total_admins <= 1 do
            IO.puts("❌ Cannot demote the last admin user! System would be locked.")
            System.halt(1)
          end

          # Remove admin roles
          Enum.each(admin_roles, &Repo.delete!/1)
          IO.puts("✅ Removed admin privileges from '#{username}'")
        end
    end
  end

  defp show_help do
    IO.puts("""
    VaultLite Admin Management

    Available commands:

      mix vault_lite.admin create                 Create a new admin user interactively
      mix vault_lite.admin create --username admin --email admin@example.com --password pass123
                                                  Create admin user with command line args
      mix vault_lite.admin list                   List all admin users
      mix vault_lite.admin promote <username>     Promote existing user to admin
      mix vault_lite.admin demote <username>      Remove admin privileges from user

    Examples:

      # Interactive admin creation
      mix vault_lite.admin create

      # Create admin with arguments
      mix vault_lite.admin create -u admin -e admin@vault.local -p SecurePass123

      # Promote existing user
      mix vault_lite.admin promote john_doe

      # List all admins
      mix vault_lite.admin list
    """)
  end

  defp prompt(message, default \\ nil) do
    input = IO.gets(message) |> String.trim()

    case {input, default} do
      {"", nil} -> prompt(message, default)
      {"", default} -> default
      {input, _} -> input
    end
  end

  defp secure_prompt(message) do
    # In a real production environment, you might want to use a library
    # that hides password input. For now, this is a simple implementation.
    IO.gets(message) |> String.trim()
  end

  defp print_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
    |> Enum.each(fn {field, errors} ->
      IO.puts("  #{field}: #{Enum.join(errors, ", ")}")
    end)
  end
end
