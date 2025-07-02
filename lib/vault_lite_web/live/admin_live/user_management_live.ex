defmodule VaultLiteWeb.AdminLive.UserManagementLive do
  @moduledoc """
  This module is responsible for the user management live view.
  - displays the users and allows the user to create, update, and delete them.
  - displays the roles and allows the user to assign roles to users.
  - displays the user details and allows the user to view the roles assigned to the user.
  - displays the role assignment form and allows the user to assign roles to users.
  - displays the user creation form and allows the user to create new users.
  - displays the user update form and allows the user to update existing users.
  """
  use VaultLiteWeb, :live_view

  alias VaultLite.Auth
  alias VaultLite.Schema.Role
  alias VaultLite.Schema.User

  @impl true
  def mount(_params, session, socket) do
    current_user = get_current_user(session)

    if is_nil(current_user) do
      {:ok, redirect(socket, to: "/login")}
    else
      # Check if user has admin access
      case Auth.check_admin_access(current_user) do
        {:ok, :authorized} ->
          socket =
            socket
            |> assign(:current_user, current_user)
            |> assign(:page_title, "User Management")
            |> assign(:users, [])
            |> assign(:selected_user, nil)
            |> assign(:show_user_form, false)
            |> assign(:show_role_form, false)
            |> assign(:available_permissions, Role.valid_permissions())
            |> assign(:search_query, "")
            |> assign(:role_form, %{name: "", permissions: []})
            |> load_users()

          {:ok, socket}

        {:error, :unauthorized} ->
          {:ok,
           socket
           |> put_flash(:error, "Access denied. Admin privileges required.")
           |> redirect(to: "/dashboard")}
      end
    end
  end

  defp get_current_user(session) do
    case Map.get(session, "user_token") do
      nil ->
        nil

      user_id when is_integer(user_id) ->
        VaultLite.Repo.get(User, user_id)

      user_id when is_binary(user_id) ->
        case Integer.parse(user_id) do
          {id, ""} -> VaultLite.Repo.get(User, id)
          _ -> nil
        end
    end
  end

  defp load_users(socket) do
    users = Auth.list_all_users_including_inactive()
    assign(socket, :users, users)
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    filtered_users =
      if query == "" do
        Auth.list_all_users_including_inactive()
      else
        Auth.list_all_users_including_inactive()
        |> Enum.filter(fn user ->
          String.contains?(String.downcase(user.username), String.downcase(query)) ||
            String.contains?(String.downcase(user.email), String.downcase(query))
        end)
      end

    {:noreply,
     socket
     |> assign(:users, filtered_users)
     |> assign(:search_query, query)}
  end

  def handle_event("select_user", %{"id" => user_id}, socket) do
    user_id = String.to_integer(user_id)
    selected_user = Auth.get_user_by_id(user_id)

    {:noreply,
     socket
     |> assign(:selected_user, selected_user)
     |> assign(:show_user_form, false)
     |> assign(:show_role_form, false)}
  end

  def handle_event("toggle_user_status", %{"id" => user_id}, socket) do
    user_id = String.to_integer(user_id)
    user = Auth.get_user_by_id(user_id)

    result =
      if user.active do
        Auth.deactivate_user(user_id, socket.assigns.current_user.id)
      else
        Auth.reactivate_user(user_id, socket.assigns.current_user.id)
      end

    case result do
      {:ok, _updated_user} ->
        status = if user.active, do: "deactivated", else: "reactivated"

        {:noreply,
         socket
         |> put_flash(:info, "User #{user.username} successfully #{status}")
         |> load_users()
         |> assign(:selected_user, nil)}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to update user status")}
    end
  end

  def handle_event("show_role_form", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_role_form, true)
     |> assign(:role_form, %{name: "", permissions: []})}
  end

  def handle_event("hide_role_form", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_role_form, false)}
  end

  def handle_event("update_role_form", %{"role" => role_params}, socket) do
    {:noreply,
     socket
     |> assign(:role_form, role_params)}
  end

  def handle_event("assign_role", %{"role" => role_params}, socket) do
    selected_user = socket.assigns.selected_user

    if selected_user do
      role_data = %{
        name: role_params["name"],
        permissions: Map.get(role_params, "permissions", [])
      }

      case Auth.assign_role(selected_user.id, role_data) do
        {:ok, _role} ->
          updated_user = Auth.get_user_by_id(selected_user.id)

          {:noreply,
           socket
           |> put_flash(
             :info,
             "Role '#{role_data.name}' successfully assigned to #{selected_user.username}"
           )
           |> assign(:selected_user, updated_user)
           |> assign(:show_role_form, false)
           |> load_users()}

        {:error, changeset} ->
          error_msg =
            case changeset.errors do
              [{:name, {msg, _}} | _] -> "Role name: #{msg}"
              [{:permissions, {msg, _}} | _] -> "Permissions: #{msg}"
              _ -> "Failed to assign role"
            end

          {:noreply,
           socket
           |> put_flash(:error, error_msg)}
      end
    else
      {:noreply,
       socket
       |> put_flash(:error, "No user selected")}
    end
  end

  def handle_event("remove_role", %{"role_name" => role_name}, socket) do
    selected_user = socket.assigns.selected_user

    if selected_user do
      case Auth.remove_role(selected_user.id, role_name) do
        {:ok, :removed} ->
          updated_user = Auth.get_user_by_id(selected_user.id)

          {:noreply,
           socket
           |> put_flash(
             :info,
             "Role '#{role_name}' successfully removed from #{selected_user.username}"
           )
           |> assign(:selected_user, updated_user)
           |> load_users()}

        {:error, :role_not_found} ->
          {:noreply,
           socket
           |> put_flash(:error, "Role not found")}

        {:error, _changeset} ->
          {:noreply,
           socket
           |> put_flash(:error, "Failed to remove role")}
      end
    else
      {:noreply,
       socket
       |> put_flash(:error, "No user selected")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <VaultLiteWeb.Layouts.app flash={@flash} current_user={@current_user}>
      <div class="min-h-screen">
        <!-- Main Content -->
        <main class="max-w-7xl mx-auto py-6 px-4 sm:px-6 lg:px-8">
          <div class="mb-6">
            <h1 class="text-2xl font-bold">User Management</h1>
            <p class="mt-1 text-sm opacity-70">
              Manage user accounts, roles, and permissions
            </p>
          </div>

          <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
            <!-- User List Panel -->
            <div class="lg:col-span-2">
              <div class="card bg-base-100 shadow">
                <div class="card-body">
                  <h2 class="card-title">Users</h2>
                  <!-- Search -->
                  <div class="form-control">
                    <form phx-submit="search" phx-change="search">
                      <input
                        type="text"
                        name="query"
                        value={@search_query}
                        placeholder="Search users by username or email..."
                        class="input input-bordered w-full"
                      />
                    </form>
                  </div>

                  <div class="space-y-2">
                    <%= for user <- @users do %>
                      <div
                        class={[
                          "card bg-base-200 cursor-pointer hover:bg-base-300",
                          if(@selected_user && @selected_user.id == user.id,
                            do: "ring-2 ring-primary",
                            else: ""
                          )
                        ]}
                        phx-click="select_user"
                        phx-value-id={user.id}
                      >
                        <div class="card-body p-4">
                          <div class="flex items-center justify-between">
                            <div class="flex items-center">
                              <div class="relative">
                                <div class="avatar placeholder">
                                  <div class="w-10 h-10 rounded-full bg-base-300 flex items-center justify-center">
                                    <.icon name="hero-user" class="h-6 w-6" />
                                  </div>
                                </div>
                                <!-- Status indicator dot -->
                                <span class={[
                                  "absolute bottom-0 right-0 block h-3 w-3 rounded-full ring-2 ring-base-100",
                                  if(user.active,
                                    do: "bg-success",
                                    else: "bg-base-content opacity-20"
                                  )
                                ]} />
                              </div>
                              <div class="ml-4">
                                <p class="text-sm font-medium">{user.username}</p>
                                <p class="text-sm opacity-70">{user.email}</p>
                                <div class="flex items-center mt-1 gap-2">
                                  <div class={[
                                    "badge",
                                    if(user.active, do: "badge-success", else: "badge-ghost")
                                  ]}>
                                    {if user.active, do: "Active", else: "Inactive"}
                                  </div>
                                  <span class="text-xs opacity-70">
                                    {length(user.roles)} role(s)
                                  </span>
                                </div>
                              </div>
                            </div>
                            <div class="flex items-center space-x-2">
                              <button
                                type="button"
                                class={[
                                  "btn btn-sm",
                                  if(user.active, do: "btn-error", else: "btn-success")
                                ]}
                                phx-click="toggle_user_status"
                                phx-value-id={user.id}
                              >
                                {if user.active, do: "Deactivate", else: "Activate"}
                              </button>
                            </div>
                          </div>
                        </div>
                      </div>
                    <% end %>

                    <%= if @users == [] do %>
                      <div class="text-center py-12">
                        <.icon name="hero-users" class="mx-auto h-12 w-12" />
                        <h3 class="mt-2 text-sm font-medium">No users found</h3>
                        <p class="mt-1 text-sm opacity-70">
                          {if @search_query != "",
                            do: "Try adjusting your search query.",
                            else: "No users in the system yet."}
                        </p>
                      </div>
                    <% end %>
                  </div>
                </div>
              </div>
            </div>
            
    <!-- User Details Panel -->
            <div class="lg:col-span-1">
              <%= if @selected_user do %>
                <div class="card bg-base-100 shadow">
                  <div class="card-body">
                    <h3 class="card-title">User Details</h3>

                    <div class="space-y-4">
                      <div>
                        <label class="label">
                          <span class="label-text font-medium">Username</span>
                        </label>
                        <div class="text-sm">{@selected_user.username}</div>
                      </div>
                      <div>
                        <label class="label">
                          <span class="label-text font-medium">Email</span>
                        </label>
                        <div class="text-sm">{@selected_user.email}</div>
                      </div>
                      <div>
                        <label class="label">
                          <span class="label-text font-medium">Status</span>
                        </label>
                        <div class={[
                          "badge",
                          if(@selected_user.active, do: "badge-success", else: "badge-ghost")
                        ]}>
                          {if @selected_user.active, do: "Active", else: "Inactive"}
                        </div>
                      </div>
                      <div>
                        <label class="label">
                          <span class="label-text font-medium">Created</span>
                        </label>
                        <div class="text-sm">
                          {@selected_user.inserted_at |> Calendar.strftime("%B %d, %Y at %I:%M %p")}
                        </div>
                      </div>
                    </div>
                    
    <!-- Roles Section -->
                    <div class="divider"></div>
                    <div>
                      <div class="flex items-center justify-between">
                        <h4 class="font-medium">Roles</h4>
                        <button
                          type="button"
                          class="btn btn-sm btn-primary"
                          phx-click="show_role_form"
                        >
                          <.icon name="hero-plus" class="h-3 w-3 mr-1" /> Add Role
                        </button>
                      </div>

                      <div class="space-y-2 mt-4">
                        <%= for role <- @selected_user.roles do %>
                          <div class="card bg-base-200">
                            <div class="card-body p-3">
                              <div class="flex items-center justify-between">
                                <div>
                                  <span class="text-sm font-medium">{role.name}</span>
                                  <div class="text-xs opacity-70">
                                    {Enum.join(role.permissions, ", ")}
                                  </div>
                                </div>
                                <button
                                  type="button"
                                  class="btn btn-ghost btn-xs"
                                  phx-click="remove_role"
                                  phx-value-role_name={role.name}
                                >
                                  <.icon name="hero-trash" class="h-4 w-4" />
                                </button>
                              </div>
                            </div>
                          </div>
                        <% end %>

                        <%= if @selected_user.roles == [] do %>
                          <p class="text-sm opacity-70 italic">No roles assigned</p>
                        <% end %>
                      </div>
                    </div>
                    
    <!-- Role Assignment Form -->
                    <%= if @show_role_form do %>
                      <div class="divider"></div>
                      <div>
                        <h5 class="font-medium mb-3">Assign New Role</h5>
                        <form phx-submit="assign_role" phx-change="update_role_form">
                          <div class="space-y-3">
                            <div class="form-control">
                              <label class="label">
                                <span class="label-text">Role Name</span>
                              </label>
                              <input
                                type="text"
                                name="role[name]"
                                value={@role_form["name"]}
                                placeholder="Enter role name"
                                class="input input-bordered"
                                required
                              />
                            </div>
                            <div class="form-control">
                              <label class="label">
                                <span class="label-text">Permissions</span>
                              </label>
                              <div class="space-y-1">
                                <%= for permission <- @available_permissions do %>
                                  <label class="label cursor-pointer justify-start gap-2">
                                    <input
                                      type="checkbox"
                                      name="role[permissions][]"
                                      value={permission}
                                      checked={permission in Map.get(@role_form, "permissions", [])}
                                      class="checkbox checkbox-primary"
                                    />
                                    <span class="label-text capitalize">
                                      {permission}
                                    </span>
                                  </label>
                                <% end %>
                              </div>
                            </div>
                            <div class="flex gap-2">
                              <button type="submit" class="btn btn-primary flex-1">
                                Assign Role
                              </button>
                              <button
                                type="button"
                                class="btn btn-outline flex-1"
                                phx-click="hide_role_form"
                              >
                                Cancel
                              </button>
                            </div>
                          </div>
                        </form>
                      </div>
                    <% end %>
                  </div>
                </div>
              <% else %>
                <div class="card bg-base-100 shadow">
                  <div class="card-body">
                    <div class="text-center py-12">
                      <.icon name="hero-user-circle" class="mx-auto h-12 w-12" />
                      <h3 class="mt-2 text-sm font-medium">No User Selected</h3>
                      <p class="mt-1 text-sm opacity-70">
                        Select a user from the list to view details and manage roles.
                      </p>
                    </div>
                  </div>
                </div>
              <% end %>
            </div>
          </div>
        </main>
      </div>
    </VaultLiteWeb.Layouts.app>
    """
  end
end
