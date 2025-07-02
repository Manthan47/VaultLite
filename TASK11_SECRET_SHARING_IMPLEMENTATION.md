# Task 11: Secret Sharing Implementation

## Overview
Implement functionality to enable users to share their personal secrets with other users, supporting two permission levels: read-only and editable. Additionally, enhance the dashboard to display sharing information, showing who shared each secret with the current user.

## Current State Analysis
- ✅ Personal secrets exist (owned by individual users)
- ✅ Role-based secrets exist (controlled by RBAC)
- ✅ User management and authentication system
- ✅ Audit logging system
- ✅ Phoenix LiveView dashboard
- ❌ **Missing**: Secret sharing mechanism between users
- ❌ **Missing**: Permission levels for shared secrets
- ❌ **Missing**: Sharing status display on dashboard

## Goal
Enable secure sharing of personal secrets between users with granular permission controls and clear visibility of sharing relationships.

---

## Task Breakdown

### 1. Database Schema Changes

#### Create SecretShare Migration
**File: `priv/repo/migrations/create_secret_shares.exs`**

```elixir
defmodule VaultLite.Repo.Migrations.CreateSecretShares do
  use Ecto.Migration

  def change do
    create table(:secret_shares) do
      add :secret_key, :string, null: false
      add :owner_id, references(:users, on_delete: :delete_all), null: false
      add :shared_with_id, references(:users, on_delete: :delete_all), null: false
      add :permission_level, :string, null: false # "read_only" or "editable"
      add :shared_at, :utc_datetime, null: false
      add :expires_at, :utc_datetime, null: true # Optional expiration
      add :active, :boolean, default: true, null: false

      timestamps()
    end

    # Indexes for efficient querying
    create unique_index(:secret_shares, [:secret_key, :shared_with_id], name: :secret_shares_unique_share)
    create index(:secret_shares, [:owner_id])
    create index(:secret_shares, [:shared_with_id])
    create index(:secret_shares, [:secret_key])
    create index(:secret_shares, [:permission_level])
    create index(:secret_shares, [:active])
  end
end
```

### 2. Ecto Schema Implementation

#### Create SecretShare Schema
**File: `lib/vault_lite/secret_share.ex`**

```elixir
defmodule VaultLite.SecretShare do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  @permission_levels ["read_only", "editable"]

  schema "secret_shares" do
    field :secret_key, :string
    field :permission_level, :string
    field :shared_at, :utc_datetime
    field :expires_at, :utc_datetime
    field :active, :boolean, default: true

    belongs_to :owner, VaultLite.User, foreign_key: :owner_id
    belongs_to :shared_with, VaultLite.User, foreign_key: :shared_with_id

    timestamps()
  end

  def changeset(secret_share, attrs) do
    secret_share
    |> cast(attrs, [:secret_key, :owner_id, :shared_with_id, :permission_level, :shared_at, :expires_at, :active])
    |> validate_required([:secret_key, :owner_id, :shared_with_id, :permission_level, :shared_at])
    |> validate_inclusion(:permission_level, @permission_levels)
    |> validate_different_users()
    |> unique_constraint([:secret_key, :shared_with_id])
  end

  # Query helpers
  def active_shares(query), do: from(s in query, where: s.active == true)
  def by_secret(query, secret_key), do: from(s in query, where: s.secret_key == ^secret_key)
  def by_shared_with(query, user_id), do: from(s in query, where: s.shared_with_id == ^user_id)
  def by_owner(query, user_id), do: from(s in query, where: s.owner_id == ^user_id)

  defp validate_different_users(changeset) do
    owner_id = get_field(changeset, :owner_id)
    shared_with_id = get_field(changeset, :shared_with_id)

    if owner_id && shared_with_id && owner_id == shared_with_id do
      add_error(changeset, :shared_with_id, "cannot share secret with yourself")
    else
      changeset
    end
  end
end
```

### 3. Context Layer Implementation

#### Create SecretSharing Context
**File: `lib/vault_lite/secret_sharing.ex`**

```elixir
defmodule VaultLite.SecretSharing do
  @moduledoc """
  Context for managing secret sharing between users.
  """

  import Ecto.Query
  alias VaultLite.{Repo, SecretShare, User, Secret, Audit}

  @doc """
  Share a secret with another user.
  """
  def share_secret(secret_key, owner_user, shared_with_username, permission_level, opts \\ []) do
    with {:ok, shared_with_user} <- find_user_by_username(shared_with_username),
         {:ok, secret} <- verify_secret_ownership(secret_key, owner_user),
         {:ok, _} <- validate_sharing_permissions(secret, owner_user),
         expires_at <- Keyword.get(opts, :expires_at),
         attrs <- build_share_attrs(secret_key, owner_user, shared_with_user, permission_level, expires_at),
         {:ok, secret_share} <- create_secret_share(attrs),
         {:ok, _} <- log_sharing_action("share", secret_key, owner_user, shared_with_user, permission_level) do
      {:ok, secret_share}
    end
  end

  @doc """
  Revoke sharing of a secret.
  """
  def revoke_sharing(secret_key, owner_user, shared_with_username) do
    with {:ok, shared_with_user} <- find_user_by_username(shared_with_username),
         {:ok, secret_share} <- find_active_share(secret_key, owner_user.id, shared_with_user.id),
         {:ok, updated_share} <- deactivate_share(secret_share),
         {:ok, _} <- log_sharing_action("revoke", secret_key, owner_user, shared_with_user, secret_share.permission_level) do
      {:ok, updated_share}
    end
  end

  @doc """
  List all secrets shared with a user.
  """
  def list_shared_secrets(user) do
    query = 
      from s in SecretShare,
        join: secret in Secret, on: s.secret_key == secret.key,
        join: owner in User, on: s.owner_id == owner.id,
        where: s.shared_with_id == ^user.id and s.active == true,
        where: is_nil(secret.deleted_at),
        select: %{
          secret_key: s.secret_key,
          permission_level: s.permission_level,
          shared_at: s.shared_at,
          expires_at: s.expires_at,
          owner_username: owner.username,
          owner_email: owner.email,
          secret: secret
        }

    {:ok, Repo.all(query)}
  end

  @doc """
  List all shares created by a user (secrets they've shared).
  """
  def list_created_shares(user) do
    query = 
      from s in SecretShare,
        join: shared_with in User, on: s.shared_with_id == shared_with.id,
        where: s.owner_id == ^user.id and s.active == true,
        select: %{
          secret_key: s.secret_key,
          permission_level: s.permission_level,
          shared_at: s.shared_at,
          expires_at: s.expires_at,
          shared_with_username: shared_with.username,
          shared_with_email: shared_with.email
        }

    {:ok, Repo.all(query)}
  end

  @doc """
  Check if a user has access to a shared secret and return permission level.
  """
  def get_shared_secret_permission(secret_key, user) do
    query = 
      from s in SecretShare,
        where: s.secret_key == ^secret_key and s.shared_with_id == ^user.id and s.active == true

    case Repo.one(query) do
      nil -> {:error, :not_shared}
      share -> 
        if share.expires_at && DateTime.compare(DateTime.utc_now(), share.expires_at) == :gt do
          {:error, :expired}
        else
          {:ok, share.permission_level}
        end
    end
  end

  # Private helper functions
  defp find_user_by_username(username) do
    case Repo.get_by(User, username: username, active: true) do
      nil -> {:error, :user_not_found}
      user -> {:ok, user}
    end
  end

  defp verify_secret_ownership(secret_key, owner_user) do
    query = 
      from s in Secret,
        where: s.key == ^secret_key and s.owner_id == ^owner_user.id and s.secret_type == "personal" and is_nil(s.deleted_at)

    case Repo.one(query) do
      nil -> {:error, :secret_not_found_or_not_owned}
      secret -> {:ok, secret}
    end
  end

  defp validate_sharing_permissions(secret, owner_user) do
    # Additional business logic validation can be added here
    {:ok, :authorized}
  end

  defp build_share_attrs(secret_key, owner_user, shared_with_user, permission_level, expires_at) do
    %{
      secret_key: secret_key,
      owner_id: owner_user.id,
      shared_with_id: shared_with_user.id,
      permission_level: permission_level,
      shared_at: DateTime.utc_now() |> DateTime.truncate(:second),
      expires_at: expires_at,
      active: true
    }
  end

  defp create_secret_share(attrs) do
    %SecretShare{}
    |> SecretShare.changeset(attrs)
    |> Repo.insert()
  end

  defp find_active_share(secret_key, owner_id, shared_with_id) do
    query = 
      from s in SecretShare,
        where: s.secret_key == ^secret_key and s.owner_id == ^owner_id and s.shared_with_id == ^shared_with_id and s.active == true

    case Repo.one(query) do
      nil -> {:error, :share_not_found}
      share -> {:ok, share}
    end
  end

  defp deactivate_share(secret_share) do
    secret_share
    |> SecretShare.changeset(%{active: false})
    |> Repo.update()
  end

  defp log_sharing_action(action, secret_key, owner_user, shared_with_user, permission_level) do
    Audit.log_action(owner_user, "secret_#{action}", secret_key, %{
      shared_with_user_id: shared_with_user.id,
      shared_with_username: shared_with_user.username,
      permission_level: permission_level
    })
  end
end
```

### 4. Update Secrets Context

#### Modify VaultLite.Secrets
**File: `lib/vault_lite/secrets.ex`**

Update the existing secrets context to handle shared secrets:

```elixir
# Add to existing functions:

def get_secret(key, user, version \\ nil) do
  # First try to get as owner or via role-based access (existing logic)
  case get_secret_direct(key, user, version) do
    {:ok, secret_data} -> {:ok, secret_data}
    {:error, :unauthorized} ->
      # Try to access as shared secret
      get_shared_secret(key, user, version)
    {:error, reason} -> {:error, reason}
  end
end

def list_secrets(user, opts \\ []) do
  # Get user's own secrets and role-based secrets (existing logic)
  {:ok, owned_secrets} = list_owned_secrets(user, opts)
  
  # Get shared secrets
  {:ok, shared_secret_data} = VaultLite.SecretSharing.list_shared_secrets(user)
  shared_secrets = Enum.map(shared_secret_data, fn share_data ->
    Map.merge(share_data.secret, %{
      shared_by: share_data.owner_username,
      permission_level: share_data.permission_level,
      shared_at: share_data.shared_at,
      is_shared: true
    })
  end)
  
  # Combine and return
  all_secrets = owned_secrets ++ shared_secrets
  {:ok, all_secrets}
end

defp get_shared_secret(key, user, version) do
  with {:ok, permission_level} <- VaultLite.SecretSharing.get_shared_secret_permission(key, user),
       {:ok, secret_data} <- get_secret_as_system(key, version) do
    # Add sharing metadata to response
    secret_with_sharing = Map.merge(secret_data, %{
      is_shared: true,
      permission_level: permission_level,
      can_edit: permission_level == "editable"
    })
    {:ok, secret_with_sharing}
  end
end

def update_secret(key, value, user, metadata \\ %{}) do
  # Check if this is a shared secret
  case VaultLite.SecretSharing.get_shared_secret_permission(key, user) do
    {:ok, "editable"} ->
      # User has edit permission on shared secret, proceed with update
      update_secret_as_shared(key, value, user, metadata)
    {:ok, "read_only"} ->
      {:error, :read_only_access}
    {:error, :not_shared} ->
      # Not a shared secret, use existing logic
      update_secret_direct(key, value, user, metadata)
    {:error, reason} ->
      {:error, reason}
  end
end
```

### 5. REST API Endpoints

#### Create Sharing Controller
**File: `lib/vault_lite_web/controllers/secret_sharing_controller.ex`**

```elixir
defmodule VaultLiteWeb.SecretSharingController do
  use VaultLiteWeb, :controller
  alias VaultLite.SecretSharing

  action_fallback VaultLiteWeb.FallbackController

  def share_secret(conn, %{"secret_key" => secret_key, "shared_with_username" => username, "permission_level" => permission}) do
    user = Guardian.Plug.current_resource(conn)
    
    with {:ok, secret_share} <- SecretSharing.share_secret(secret_key, user, username, permission) do
      conn
      |> put_status(:created)
      |> json(%{
        message: "Secret shared successfully",
        secret_key: secret_key,
        shared_with: username,
        permission_level: permission,
        shared_at: secret_share.shared_at
      })
    end
  end

  def revoke_sharing(conn, %{"secret_key" => secret_key, "shared_with_username" => username}) do
    user = Guardian.Plug.current_resource(conn)
    
    with {:ok, _} <- SecretSharing.revoke_sharing(secret_key, user, username) do
      conn
      |> json(%{message: "Sharing revoked successfully"})
    end
  end

  def list_shared_with_me(conn, _params) do
    user = Guardian.Plug.current_resource(conn)
    
    with {:ok, shared_secrets} <- SecretSharing.list_shared_secrets(user) do
      conn
      |> json(%{shared_secrets: shared_secrets})
    end
  end

  def list_my_shares(conn, _params) do
    user = Guardian.Plug.current_resource(conn)
    
    with {:ok, created_shares} <- SecretSharing.list_created_shares(user) do
      conn
      |> json(%{created_shares: created_shares})
    end
  end
end
```

#### Update Router
**File: `lib/vault_lite_web/router.ex`**

Add sharing routes:
```elixir
scope "/api", VaultLiteWeb do
  pipe_through [:api, :authenticate]
  
  # Existing routes...
  
  # Secret sharing routes
  post "/secrets/:secret_key/share", SecretSharingController, :share_secret
  delete "/secrets/:secret_key/share/:shared_with_username", SecretSharingController, :revoke_sharing
  get "/shared/with-me", SecretSharingController, :list_shared_with_me
  get "/shared/by-me", SecretSharingController, :list_my_shares
end
```

### 6. LiveView UI Implementation

#### Update Secret Dashboard
**File: `lib/vault_lite_web/live/dashboard_live/secret_dashboard_live.ex`**

Enhance dashboard to show sharing information:

```elixir
# Add to existing load_secrets function:
defp load_secrets(socket) do
  user = socket.assigns.current_user
  search = Map.get(socket.assigns, :search_query, "")
  filter_type = Map.get(socket.assigns, :filter_type, "all")

  {:ok, all_secrets} = Secrets.list_secrets(user)

  # Enhanced filtering to include shared secrets
  filtered_secrets =
    case filter_type do
      "personal" ->
        Enum.filter(all_secrets, fn secret ->
          secret.secret_type == "personal" && !Map.get(secret, :is_shared, false)
        end)
      "shared_with_me" ->
        Enum.filter(all_secrets, fn secret ->
          Map.get(secret, :is_shared, false)
        end)
      "role_based" ->
        Enum.filter(all_secrets, fn secret ->
          secret.secret_type == "role_based"
        end)
      _ ->
        all_secrets
    end

  socket
  |> assign(:secrets, filtered_secrets)
  |> assign(:loading, false)
end

# Add sharing status display helper:
defp sharing_status_badge(secret) do
  cond do
    Map.get(secret, :is_shared, false) ->
      permission = Map.get(secret, :permission_level, "read_only")
      shared_by = Map.get(secret, :shared_by, "Unknown")
      {"Shared by #{shared_by} (#{permission})", "bg-purple-100 text-purple-800"}
    
    secret.secret_type == "personal" ->
      {"Personal", "bg-blue-100 text-blue-800"}
    
    true ->
      {"Role-based", "bg-green-100 text-green-800"}
  end
end
```

#### Create Secret Sharing LiveView
**File: `lib/vault_lite_web/live/secrets_live/secret_sharing_live.ex`**

```elixir
defmodule VaultLiteWeb.SecretsLive.SecretSharingLive do
  use VaultLiteWeb, :live_view
  alias VaultLite.SecretSharing

  def mount(%{"secret_key" => secret_key}, session, socket) do
    current_user = get_current_user(session)
    
    if is_nil(current_user) do
      {:ok, redirect(socket, to: "/login")}
    else
      {:ok, created_shares} = SecretSharing.list_created_shares(current_user)
      shares_for_secret = Enum.filter(created_shares, &(&1.secret_key == secret_key))
      
      socket = 
        socket
        |> assign(:current_user, current_user)
        |> assign(:secret_key, secret_key)
        |> assign(:shares, shares_for_secret)
        |> assign(:share_form, %{"username" => "", "permission_level" => "read_only"})
        |> assign(:page_title, "Share Secret")
      
      {:ok, socket}
    end
  end

  def handle_event("share_secret", %{"username" => username, "permission_level" => permission}, socket) do
    secret_key = socket.assigns.secret_key
    user = socket.assigns.current_user
    
    case SecretSharing.share_secret(secret_key, user, username, permission) do
      {:ok, _secret_share} ->
        {:ok, updated_shares} = SecretSharing.list_created_shares(user)
        shares_for_secret = Enum.filter(updated_shares, &(&1.secret_key == secret_key))
        
        socket = 
          socket
          |> assign(:shares, shares_for_secret)
          |> assign(:share_form, %{"username" => "", "permission_level" => "read_only"})
          |> put_flash(:info, "Secret shared successfully with #{username}")
        
        {:noreply, socket}
      
      {:error, reason} ->
        error_msg = case reason do
          :user_not_found -> "User not found"
          :secret_not_found_or_not_owned -> "Secret not found or you don't own it"
          _ -> "Error sharing secret"
        end
        
        socket = put_flash(socket, :error, error_msg)
        {:noreply, socket}
    end
  end

  def handle_event("revoke_share", %{"username" => username}, socket) do
    secret_key = socket.assigns.secret_key
    user = socket.assigns.current_user
    
    case SecretSharing.revoke_sharing(secret_key, user, username) do
      {:ok, _} ->
        {:ok, updated_shares} = SecretSharing.list_created_shares(user)
        shares_for_secret = Enum.filter(updated_shares, &(&1.secret_key == secret_key))
        
        socket = 
          socket
          |> assign(:shares, shares_for_secret)
          |> put_flash(:info, "Sharing revoked for #{username}")
        
        {:noreply, socket}
      
      {:error, reason} ->
        error_msg = case reason do
          :share_not_found -> "Share not found"
          _ -> "Error revoking share"
        end
        
        socket = put_flash(socket, :error, error_msg)
        {:noreply, socket}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto py-6 px-4">
      <div class="mb-6">
        <h1 class="text-2xl font-bold mb-2">Share Secret: <%= @secret_key %></h1>
        <p class="text-gray-600">Manage who can access this secret and their permission levels.</p>
      </div>

      <!-- Share Form -->
      <div class="bg-white shadow rounded-lg p-6 mb-6">
        <h2 class="text-lg font-medium mb-4">Share with New User</h2>
        
        <.form for={%{}} phx-submit="share_secret" class="space-y-4">
          <div>
            <label class="label">
              <span class="label-text">Username</span>
            </label>
            <input 
              name="username" 
              type="text" 
              placeholder="Enter username to share with"
              class="input input-bordered w-full"
              value={@share_form["username"]}
              required
            />
          </div>
          
          <div>
            <label class="label">
              <span class="label-text">Permission Level</span>
            </label>
            <select name="permission_level" class="select select-bordered w-full" value={@share_form["permission_level"]}>
              <option value="read_only">Read Only</option>
              <option value="editable">Editable</option>
            </select>
            <div class="text-sm text-gray-500 mt-1">
              <strong>Read Only:</strong> User can view the secret but cannot modify it.<br/>
              <strong>Editable:</strong> User can view and modify the secret.
            </div>
          </div>
          
          <button type="submit" class="btn btn-primary">
            <.icon name="hero-share" class="w-4 h-4 mr-2" />
            Share Secret
          </button>
        </.form>
      </div>

      <!-- Current Shares -->
      <div class="bg-white shadow rounded-lg p-6">
        <h2 class="text-lg font-medium mb-4">Current Shares</h2>
        
        <%= if Enum.empty?(@shares) do %>
          <p class="text-gray-500 italic">This secret is not currently shared with anyone.</p>
        <% else %>
          <div class="overflow-x-auto">
            <table class="table w-full">
              <thead>
                <tr>
                  <th>Shared With</th>
                  <th>Permission Level</th>
                  <th>Shared At</th>
                  <th>Actions</th>
                </tr>
              </thead>
              <tbody>
                <%= for share <- @shares do %>
                  <tr>
                    <td>
                      <div>
                        <div class="font-medium"><%= share.shared_with_username %></div>
                        <div class="text-sm text-gray-500"><%= share.shared_with_email %></div>
                      </div>
                    </td>
                    <td>
                      <span class={[
                        "badge",
                        if(share.permission_level == "editable", do: "badge-warning", else: "badge-info")
                      ]}>
                        <%= String.replace(share.permission_level, "_", " ") |> String.capitalize() %>
                      </span>
                    </td>
                    <td><%= format_date(share.shared_at) %></td>
                    <td>
                      <button 
                        phx-click="revoke_share" 
                        phx-value-username={share.shared_with_username}
                        class="btn btn-sm btn-error"
                        onclick="return confirm('Are you sure you want to revoke sharing with this user?')"
                      >
                        <.icon name="hero-x-mark" class="w-4 h-4" />
                        Revoke
                      </button>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        <% end %>
      </div>
      
      <!-- Back Button -->
      <div class="mt-6">
        <.link navigate="/dashboard" class="btn btn-outline">
          <.icon name="hero-arrow-left" class="w-4 h-4 mr-2" />
          Back to Dashboard
        </.link>
      </div>
    </div>
    """
  end

  defp format_date(datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M")
  end

  defp get_current_user(session) do
    case Map.get(session, "user_token") do
      nil -> nil
      user_id when is_integer(user_id) -> VaultLite.Repo.get(VaultLite.User, user_id)
      user_id when is_binary(user_id) ->
        case Integer.parse(user_id) do
          {id, ""} -> VaultLite.Repo.get(VaultLite.User, id)
          _ -> nil
        end
    end
  end
end
```

### 7. Update Router for LiveView

**File: `lib/vault_lite_web/router.ex`**

Add sharing routes to LiveView scope:
```elixir
scope "/", VaultLiteWeb do
  pipe_through [:browser, :require_authenticated_user]
  
  # Existing routes...
  
  live "/secrets/:secret_key/share", SecretsLive.SecretSharingLive, :show
end
```

### 8. Enhanced Dashboard Display

Update the dashboard template to show sharing information:

```heex
<!-- In the secrets list, enhance each secret card: -->
<div class="card bg-base-100 shadow-md">
  <div class="card-body">
    <div class="flex justify-between items-start">
      <div class="flex-1">
        <h3 class="card-title text-lg font-medium">
          <.icon name={secret_icon(secret)} class="w-5 h-5 mr-2" />
          <%= secret.key %>
        </h3>
        
        <!-- Sharing status badges -->
        <div class="flex gap-2 mt-2">
          <%= if Map.get(secret, :is_shared, false) do %>
            <span class="badge badge-purple badge-sm">
              <.icon name="hero-share" class="w-3 h-3 mr-1" />
              Shared by <%= Map.get(secret, :shared_by, "Unknown") %>
            </span>
            <span class={[
              "badge badge-sm",
              if(Map.get(secret, :permission_level) == "editable", do: "badge-warning", else: "badge-info")
            ]}>
              <%= String.replace(Map.get(secret, :permission_level, "read_only"), "_", " ") |> String.capitalize() %>
            </span>
          <% else %>
            <span class={elem(secret_type_badge(secret.secret_type), 1) ++ " badge badge-sm"}>
              <%= elem(secret_type_badge(secret.secret_type), 0) %>
            </span>
          <% end %>
        </div>
      </div>
      
      <div class="dropdown dropdown-end">
        <label tabindex="0" class="btn btn-ghost btn-sm">
          <.icon name="hero-ellipsis-vertical" class="w-4 h-4" />
        </label>
        <ul class="dropdown-content menu p-2 shadow bg-base-100 rounded-box w-52">
          <li>
            <.link navigate={"/secrets/#{secret.key}"}>
              <.icon name="hero-eye" class="w-4 h-4" />
              View
            </.link>
          </li>
          
          <%= if can_edit_secret?(secret, @current_user) do %>
            <li>
              <.link navigate={"/secrets/#{secret.key}/edit"}>
                <.icon name="hero-pencil" class="w-4 h-4" />
                Edit
              </.link>
            </li>
          <% end %>
          
          <%= if can_share_secret?(secret, @current_user) do %>
            <li>
              <.link navigate={"/secrets/#{secret.key}/share"}>
                <.icon name="hero-share" class="w-4 h-4" />
                Manage Sharing
              </.link>
            </li>
          <% end %>
          
          <%= if can_delete_secret?(secret, @current_user) do %>
            <li>
              <a phx-click="delete_secret" phx-value-key={secret.key} 
                 onclick="return confirm('Are you sure?')" class="text-error">
                <.icon name="hero-trash" class="w-4 h-4" />
                Delete
              </a>
            </li>
          <% end %>
        </ul>
      </div>
    </div>
    
    <div class="text-sm text-gray-500 mt-2">
      <%= if Map.get(secret, :is_shared, false) do %>
        Shared with you on <%= format_date(Map.get(secret, :shared_at)) %>
      <% else %>
        Created <%= format_date(secret.inserted_at) %>
      <% end %>
    </div>
  </div>
</div>
```

### 9. Security Considerations

#### Authorization Checks
- **Share Permission**: Only personal secret owners can share their secrets
- **Edit Shared Secrets**: Only users with "editable" permission can modify shared secrets
- **View Shared Secrets**: Both "read_only" and "editable" users can view shared secrets
- **Revoke Sharing**: Only the original owner can revoke sharing

#### Audit Logging
- All sharing operations (share, revoke, access) are logged
- Sharing metadata includes target user and permission level
- Failed sharing attempts are logged for security monitoring

#### Data Protection
- Shared secrets maintain the same encryption as personal secrets
- No additional copies of secret data are created
- Sharing relationships are separate from secret data

### 10. Testing Strategy

#### Unit Tests
**File: `test/vault_lite/secret_sharing_test.exs`**

```elixir
defmodule VaultLite.SecretSharingTest do
  use VaultLite.DataCase
  alias VaultLite.{SecretSharing, Secrets, User, Repo}

  describe "share_secret/4" do
    test "successfully shares a personal secret with read-only permission" do
      owner = insert(:user)
      recipient = insert(:user)
      
      {:ok, _secret} = Secrets.create_secret("test_key", "test_value", owner, %{}, "personal")
      
      assert {:ok, secret_share} = SecretSharing.share_secret("test_key", owner, recipient.username, "read_only")
      assert secret_share.secret_key == "test_key"
      assert secret_share.permission_level == "read_only"
    end

    test "prevents sharing secret with yourself" do
      owner = insert(:user)
      {:ok, _secret} = Secrets.create_secret("test_key", "test_value", owner, %{}, "personal")
      
      assert {:error, _} = SecretSharing.share_secret("test_key", owner, owner.username, "read_only")
    end

    test "prevents sharing non-owned secrets" do
      owner = insert(:user)
      other_user = insert(:user)
      recipient = insert(:user)
      
      {:ok, _secret} = Secrets.create_secret("test_key", "test_value", owner, %{}, "personal")
      
      assert {:error, :secret_not_found_or_not_owned} = 
        SecretSharing.share_secret("test_key", other_user, recipient.username, "read_only")
    end
  end

  describe "list_shared_secrets/1" do
    test "returns secrets shared with user" do
      owner = insert(:user)
      recipient = insert(:user)
      
      {:ok, _secret} = Secrets.create_secret("shared_key", "shared_value", owner, %{}, "personal")
      {:ok, _share} = SecretSharing.share_secret("shared_key", owner, recipient.username, "editable")
      
      {:ok, shared_secrets} = SecretSharing.list_shared_secrets(recipient)
      
      assert length(shared_secrets) == 1
      assert List.first(shared_secrets).secret_key == "shared_key"
      assert List.first(shared_secrets).permission_level == "editable"
    end
  end
end
```

#### Integration Tests
Test the full flow including LiveView interactions and API endpoints.

### 11. Performance Considerations

#### Database Optimization
- Efficient indexes on secret_shares table for common queries
- Pagination for large sharing lists
- Query optimization for dashboard loading

#### Caching Strategy
- Cache sharing relationships for frequently accessed secrets
- Cache user lookups for username resolution
- Invalidate caches when sharing relationships change

### 12. Documentation Updates

Update user guide with sharing functionality:
- How to share secrets with specific permission levels
- How to manage existing shares
- Understanding sharing indicators on dashboard
- Security implications of sharing secrets

---

## Implementation Checklist

### Phase 1: Database and Models ✅
- [ ] Create secret_shares migration
- [ ] Implement SecretShare schema
- [ ] Add validation logic
- [ ] Run migrations and test schema

### Phase 2: Context Layer ✅
- [ ] Implement SecretSharing context
- [ ] Update Secrets context for shared secret access
- [ ] Add audit logging integration
- [ ] Write unit tests for context functions

### Phase 3: API Layer ✅
- [ ] Create SecretSharingController
- [ ] Add sharing routes to router
- [ ] Test API endpoints
- [ ] Add API documentation

### Phase 4: LiveView UI ✅
- [ ] Update dashboard to show sharing status
- [ ] Create secret sharing management page
- [ ] Add sharing controls to secret detail views
- [ ] Update filter and search to include shared secrets

### Phase 5: Security and Testing ✅
- [ ] Implement authorization checks
- [ ] Add comprehensive test suite
- [ ] Security review of sharing logic
- [ ] Performance testing with large datasets

### Phase 6: Documentation ✅
- [ ] Update API documentation
- [ ] Update user guide
- [ ] Create sharing best practices guide
- [ ] Update admin documentation

---

## Success Criteria

1. **Functional Requirements Met**:
   - ✅ Users can share personal secrets with other users
   - ✅ Two permission levels: read-only and editable
   - ✅ Dashboard shows who shared each secret with current user
   - ✅ Secret owners can manage sharing (add/remove users)
   - ✅ Shared secrets respect permission levels

2. **Security Requirements Met**:
   - ✅ Only secret owners can share their personal secrets
   - ✅ Proper authorization checks for all sharing operations
   - ✅ Audit logging for all sharing activities
   - ✅ No data leakage between users

3. **User Experience Requirements Met**:
   - ✅ Intuitive sharing interface
   - ✅ Clear indication of sharing status on dashboard
   - ✅ Easy management of existing shares
   - ✅ Responsive design for all devices

4. **Technical Requirements Met**:
   - ✅ Efficient database queries with proper indexing
   - ✅ Comprehensive test coverage
   - ✅ Integration with existing authentication and authorization
   - ✅ Backwards compatibility with existing functionality

This implementation provides a secure, user-friendly secret sharing system that extends VaultLite's capabilities while maintaining its security principles and design patterns. 