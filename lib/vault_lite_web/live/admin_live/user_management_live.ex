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

  alias VaultLite.{Auth, User, Role}

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
    <div class="h-full bg-gray-50">
      <!-- Navigation Header -->
      <nav class="bg-white shadow-sm border-b">
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div class="flex justify-between h-16">
            <div class="flex items-center">
              <.icon name="hero-lock-closed" class="h-8 w-8 text-indigo-600" />
              <span class="ml-2 text-xl font-bold text-gray-900">VaultLite</span>
            </div>

            <div class="flex items-center space-x-4">
              <span class="text-sm text-gray-700">Welcome, {@current_user.username}!</span>

              <.link
                navigate="/dashboard"
                class="text-gray-500 hover:text-gray-700 px-3 py-2 rounded-md text-sm font-medium"
              >
                Dashboard
              </.link>

              <.link
                navigate="/admin/roles"
                class="text-gray-500 hover:text-gray-700 px-3 py-2 rounded-md text-sm font-medium"
              >
                Role Management
              </.link>

              <.link
                navigate="/admin/audit"
                class="text-gray-500 hover:text-gray-700 px-3 py-2 rounded-md text-sm font-medium"
              >
                Audit Logs
              </.link>

              <.link
                href="/logout"
                method="delete"
                class="text-gray-500 hover:text-gray-700 px-3 py-2 rounded-md text-sm font-medium"
              >
                Logout
              </.link>
            </div>
          </div>
        </div>
      </nav>
      
    <!-- Main Content -->
      <main class="max-w-7xl mx-auto py-6 px-4 sm:px-6 lg:px-8">
        <div class="mb-6">
          <h1 class="text-2xl font-bold text-gray-900">User Management</h1>
          <p class="mt-1 text-sm text-gray-600">
            Manage user accounts, roles, and permissions
          </p>
        </div>

        <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
          <!-- User List Panel -->
          <div class="lg:col-span-2">
            <div class="bg-white shadow rounded-lg">
              <div class="px-6 py-4 border-b border-gray-200">
                <h2 class="text-lg font-medium text-gray-900">Users</h2>
                <!-- Search -->
                <div class="mt-4">
                  <form phx-submit="search" phx-change="search">
                    <input
                      type="text"
                      name="query"
                      value={@search_query}
                      placeholder="Search users by username or email..."
                      class="block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm"
                    />
                  </form>
                </div>
              </div>

              <div class="overflow-hidden">
                <ul role="list" class="divide-y divide-gray-200">
                  <%= for user <- @users do %>
                    <li
                      class={"px-6 py-4 hover:bg-gray-50 cursor-pointer #{if @selected_user && @selected_user.id == user.id, do: "bg-indigo-50 border-r-4 border-indigo-500"}"}
                      phx-click="select_user"
                      phx-value-id={user.id}
                    >
                      <div class="flex items-center justify-between">
                        <div class="flex items-center">
                          <div class="flex-shrink-0">
                            <div class={"h-10 w-10 rounded-full flex items-center justify-center text-white font-medium #{if user.active, do: "bg-green-500", else: "bg-gray-400"}"}>
                              {String.first(user.username) |> String.upcase()}
                            </div>
                          </div>
                          <div class="ml-4">
                            <p class="text-sm font-medium text-gray-900">{user.username}</p>
                            <p class="text-sm text-gray-500">{user.email}</p>
                            <div class="flex items-center mt-1">
                              <span class={"inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium #{if user.active, do: "bg-green-100 text-green-800", else: "bg-gray-100 text-gray-800"}"}>
                                {if user.active, do: "Active", else: "Inactive"}
                              </span>
                              <span class="ml-2 text-xs text-gray-500">
                                {length(user.roles)} role(s)
                              </span>
                            </div>
                          </div>
                        </div>
                        <div class="flex items-center space-x-2">
                          <button
                            type="button"
                            class={"inline-flex items-center px-3 py-1 border border-transparent text-xs font-medium rounded text-white #{if user.active, do: "bg-red-600 hover:bg-red-700", else: "bg-green-600 hover:bg-green-700"}"}
                            phx-click="toggle_user_status"
                            phx-value-id={user.id}
                          >
                            {if user.active, do: "Deactivate", else: "Activate"}
                          </button>
                        </div>
                      </div>
                    </li>
                  <% end %>
                </ul>

                <%= if @users == [] do %>
                  <div class="text-center py-12">
                    <.icon name="hero-users" class="mx-auto h-12 w-12 text-gray-400" />
                    <h3 class="mt-2 text-sm font-medium text-gray-900">No users found</h3>
                    <p class="mt-1 text-sm text-gray-500">
                      {if @search_query != "",
                        do: "Try adjusting your search query.",
                        else: "No users in the system yet."}
                    </p>
                  </div>
                <% end %>
              </div>
            </div>
          </div>
          
    <!-- User Details Panel -->
          <div class="lg:col-span-1">
            <%= if @selected_user do %>
              <div class="bg-white shadow rounded-lg">
                <div class="px-6 py-4 border-b border-gray-200">
                  <h3 class="text-lg font-medium text-gray-900">User Details</h3>
                </div>
                <div class="px-6 py-4">
                  <div class="space-y-4">
                    <div>
                      <dt class="text-sm font-medium text-gray-500">Username</dt>
                      <dd class="mt-1 text-sm text-gray-900">{@selected_user.username}</dd>
                    </div>
                    <div>
                      <dt class="text-sm font-medium text-gray-500">Email</dt>
                      <dd class="mt-1 text-sm text-gray-900">{@selected_user.email}</dd>
                    </div>
                    <div>
                      <dt class="text-sm font-medium text-gray-500">Status</dt>
                      <dd class="mt-1">
                        <span class={"inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium #{if @selected_user.active, do: "bg-green-100 text-green-800", else: "bg-gray-100 text-gray-800"}"}>
                          {if @selected_user.active, do: "Active", else: "Inactive"}
                        </span>
                      </dd>
                    </div>
                    <div>
                      <dt class="text-sm font-medium text-gray-500">Created</dt>
                      <dd class="mt-1 text-sm text-gray-900">
                        {@selected_user.inserted_at |> Calendar.strftime("%B %d, %Y at %I:%M %p")}
                      </dd>
                    </div>
                  </div>
                </div>
                
    <!-- Roles Section -->
                <div class="border-t border-gray-200">
                  <div class="px-6 py-4">
                    <div class="flex items-center justify-between">
                      <h4 class="text-sm font-medium text-gray-900">Roles</h4>
                      <button
                        type="button"
                        class="inline-flex items-center px-3 py-1 border border-transparent text-xs font-medium rounded text-indigo-700 bg-indigo-100 hover:bg-indigo-200"
                        phx-click="show_role_form"
                      >
                        <.icon name="hero-plus" class="h-3 w-3 mr-1" /> Add Role
                      </button>
                    </div>

                    <div class="mt-4 space-y-2">
                      <%= for role <- @selected_user.roles do %>
                        <div class="flex items-center justify-between p-2 bg-gray-50 rounded">
                          <div>
                            <span class="text-sm font-medium text-gray-900">{role.name}</span>
                            <div class="text-xs text-gray-500">
                              {Enum.join(role.permissions, ", ")}
                            </div>
                          </div>
                          <button
                            type="button"
                            class="text-red-600 hover:text-red-800"
                            phx-click="remove_role"
                            phx-value-role_name={role.name}
                          >
                            <.icon name="hero-trash" class="h-4 w-4" />
                          </button>
                        </div>
                      <% end %>

                      <%= if @selected_user.roles == [] do %>
                        <p class="text-sm text-gray-500 italic">No roles assigned</p>
                      <% end %>
                    </div>
                  </div>
                </div>
                
    <!-- Role Assignment Form -->
                <%= if @show_role_form do %>
                  <div class="border-t border-gray-200 bg-gray-50">
                    <div class="px-6 py-4">
                      <h5 class="text-sm font-medium text-gray-900 mb-3">Assign New Role</h5>
                      <form phx-submit="assign_role" phx-change="update_role_form">
                        <div class="space-y-3">
                          <div>
                            <label class="block text-xs font-medium text-gray-700">Role Name</label>
                            <input
                              type="text"
                              name="role[name]"
                              value={@role_form["name"]}
                              placeholder="Enter role name"
                              class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm"
                              required
                            />
                          </div>
                          <div>
                            <label class="block text-xs font-medium text-gray-700">Permissions</label>
                            <div class="mt-1 space-y-1">
                              <%= for permission <- @available_permissions do %>
                                <label class="flex items-center">
                                  <input
                                    type="checkbox"
                                    name="role[permissions][]"
                                    value={permission}
                                    checked={permission in Map.get(@role_form, "permissions", [])}
                                    class="rounded border-gray-300 text-indigo-600 focus:ring-indigo-500"
                                  />
                                  <span class="ml-2 text-xs text-gray-700 capitalize">
                                    {permission}
                                  </span>
                                </label>
                              <% end %>
                            </div>
                          </div>
                          <div class="flex space-x-2">
                            <button
                              type="submit"
                              class="flex-1 inline-flex justify-center py-2 px-4 border border-transparent shadow-sm text-xs font-medium rounded-md text-white bg-indigo-600 hover:bg-indigo-700"
                            >
                              Assign Role
                            </button>
                            <button
                              type="button"
                              class="flex-1 inline-flex justify-center py-2 px-4 border border-gray-300 shadow-sm text-xs font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50"
                              phx-click="hide_role_form"
                            >
                              Cancel
                            </button>
                          </div>
                        </div>
                      </form>
                    </div>
                  </div>
                <% end %>
              </div>
            <% else %>
              <div class="bg-white shadow rounded-lg">
                <div class="text-center py-12">
                  <.icon name="hero-user-circle" class="mx-auto h-12 w-12 text-gray-400" />
                  <h3 class="mt-2 text-sm font-medium text-gray-900">No User Selected</h3>
                  <p class="mt-1 text-sm text-gray-500">
                    Select a user from the list to view details and manage roles.
                  </p>
                </div>
              </div>
            <% end %>
          </div>
        </div>
      </main>
    </div>
    """
  end
end
