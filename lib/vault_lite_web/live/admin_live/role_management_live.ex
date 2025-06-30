defmodule VaultLiteWeb.AdminLive.RoleManagementLive do
  @moduledoc """
  This module is responsible for the role management live view.
  - displays the roles and allows the user to create, update, and delete them.
  - displays the users and allows the user to assign roles to them.
  - displays the role details and allows the user to view the users assigned to the role.
  - displays the user assignment form and allows the user to assign roles to users.
  - displays the role creation form and allows the user to create new roles.
  - displays the role update form and allows the user to update existing roles.
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
            |> assign(:page_title, "Role Management")
            |> assign(:roles, [])
            |> assign(:selected_role, nil)
            |> assign(:show_role_form, false)
            |> assign(:show_user_assignment, false)
            |> assign(:available_permissions, Role.valid_permissions())
            |> assign(:available_users, [])
            |> assign(:search_query, "")
            |> assign(:role_form, %{name: "", permissions: []})
            |> load_roles()
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

  defp load_roles(socket) do
    roles = Auth.list_roles_with_users()
    assign(socket, :roles, roles)
  end

  defp load_users(socket) do
    users = Auth.list_all_users()
    assign(socket, :available_users, users)
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    filtered_roles =
      if query == "" do
        Auth.list_roles_with_users()
      else
        Auth.list_roles_with_users()
        |> Enum.filter(fn role ->
          String.contains?(String.downcase(role.name), String.downcase(query)) ||
            Enum.any?(role.permissions, fn perm ->
              String.contains?(String.downcase(perm), String.downcase(query))
            end)
        end)
      end

    {:noreply,
     socket
     |> assign(:roles, filtered_roles)
     |> assign(:search_query, query)}
  end

  def handle_event("select_role", %{"name" => role_name}, socket) do
    selected_role =
      Enum.find(socket.assigns.roles, fn role -> role.name == role_name end)

    {:noreply,
     socket
     |> assign(:selected_role, selected_role)
     |> assign(:show_role_form, false)
     |> assign(:show_user_assignment, false)}
  end

  def handle_event("show_role_form", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_role_form, true)
     |> assign(:role_form, %{name: "", permissions: []})
     |> assign(:selected_role, nil)}
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

  def handle_event("create_role", %{"role" => role_params}, socket) do
    # Create a role template by assigning it to the current user first
    role_data = %{
      name: role_params["name"],
      permissions: Map.get(role_params, "permissions", [])
    }

    case Auth.assign_role(socket.assigns.current_user.id, role_data) do
      {:ok, _role} ->
        # Remove the role from current user since this was just for creation
        Auth.remove_role(socket.assigns.current_user.id, role_data.name)

        {:noreply,
         socket
         |> put_flash(:info, "Role '#{role_data.name}' successfully created")
         |> assign(:show_role_form, false)
         |> load_roles()}

      {:error, changeset} ->
        error_msg =
          case changeset.errors do
            [{:name, {msg, _}} | _] -> "Role name: #{msg}"
            [{:permissions, {msg, _}} | _] -> "Permissions: #{msg}"
            _ -> "Failed to create role"
          end

        {:noreply,
         socket
         |> put_flash(:error, error_msg)}
    end
  end

  def handle_event("show_user_assignment", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_user_assignment, true)}
  end

  def handle_event("hide_user_assignment", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_user_assignment, false)}
  end

  def handle_event("assign_role_to_user", %{"user_id" => user_id}, socket) do
    user_id = String.to_integer(user_id)
    selected_role = socket.assigns.selected_role

    if selected_role do
      role_data = %{
        name: selected_role.name,
        permissions: selected_role.permissions
      }

      case Auth.assign_role(user_id, role_data) do
        {:ok, _role} ->
          user = Auth.get_user_by_id(user_id)

          {:noreply,
           socket
           |> put_flash(
             :info,
             "Role '#{selected_role.name}' successfully assigned to #{user.username}"
           )
           |> assign(:show_user_assignment, false)
           |> load_roles()}

        {:error, changeset} ->
          error_msg =
            case changeset.errors do
              [{:name, {msg, _}} | _] -> "Role name: #{msg}"
              _ -> "Role already assigned to this user"
            end

          {:noreply,
           socket
           |> put_flash(:error, error_msg)}
      end
    else
      {:noreply,
       socket
       |> put_flash(:error, "No role selected")}
    end
  end

  def handle_event("remove_role_from_user", %{"user_id" => user_id}, socket) do
    user_id = String.to_integer(user_id)
    selected_role = socket.assigns.selected_role

    if selected_role do
      case Auth.remove_role(user_id, selected_role.name) do
        {:ok, :removed} ->
          user = Auth.get_user_by_id(user_id)

          {:noreply,
           socket
           |> put_flash(
             :info,
             "Role '#{selected_role.name}' successfully removed from #{user.username}"
           )
           |> load_roles()
           |> assign(:selected_role, nil)}

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
       |> put_flash(:error, "No role selected")}
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
                navigate="/admin/users"
                class="text-gray-500 hover:text-gray-700 px-3 py-2 rounded-md text-sm font-medium"
              >
                User Management
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
          <div class="flex items-center justify-between">
            <div>
              <h1 class="text-2xl font-bold text-gray-900">Role Management</h1>
              <p class="mt-1 text-sm text-gray-600">
                Manage roles, permissions, and user assignments
              </p>
            </div>
            <button
              type="button"
              class="inline-flex items-center px-4 py-2 border border-transparent shadow-sm text-sm font-medium rounded-md text-white bg-indigo-600 hover:bg-indigo-700"
              phx-click="show_role_form"
            >
              <.icon name="hero-plus" class="h-4 w-4 mr-2" /> Create Role
            </button>
          </div>
        </div>

        <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
          <!-- Role List Panel -->
          <div class="lg:col-span-2">
            <div class="bg-white shadow rounded-lg">
              <div class="px-6 py-4 border-b border-gray-200">
                <h2 class="text-lg font-medium text-gray-900">Roles</h2>
                <!-- Search -->
                <div class="mt-4">
                  <form phx-submit="search" phx-change="search">
                    <input
                      type="text"
                      name="query"
                      value={@search_query}
                      placeholder="Search roles by name or permissions..."
                      class="block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm"
                    />
                  </form>
                </div>
              </div>

              <div class="overflow-hidden">
                <ul role="list" class="divide-y divide-gray-200">
                  <%= for role <- @roles do %>
                    <li
                      class={"px-6 py-4 hover:bg-gray-50 cursor-pointer #{if @selected_role && @selected_role.name == role.name, do: "bg-indigo-50 border-r-4 border-indigo-500"}"}
                      phx-click="select_role"
                      phx-value-name={role.name}
                    >
                      <div class="flex items-center justify-between">
                        <div class="flex items-center">
                          <div class="flex-shrink-0">
                            <div class="h-10 w-10 rounded-full bg-indigo-500 flex items-center justify-center text-white font-medium">
                              <.icon name="hero-key" class="h-5 w-5" />
                            </div>
                          </div>
                          <div class="ml-4">
                            <p class="text-sm font-medium text-gray-900">{role.name}</p>
                            <div class="flex items-center mt-1">
                              <%= for permission <- role.permissions do %>
                                <span class="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-gray-100 text-gray-800 mr-1">
                                  {permission}
                                </span>
                              <% end %>
                            </div>
                            <p class="text-xs text-gray-500 mt-1">
                              {role.user_count} user(s) assigned
                            </p>
                          </div>
                        </div>
                      </div>
                    </li>
                  <% end %>
                </ul>

                <%= if @roles == [] do %>
                  <div class="text-center py-12">
                    <.icon name="hero-key" class="mx-auto h-12 w-12 text-gray-400" />
                    <h3 class="mt-2 text-sm font-medium text-gray-900">No roles found</h3>
                    <p class="mt-1 text-sm text-gray-500">
                      {if @search_query != "",
                        do: "Try adjusting your search query.",
                        else: "No roles in the system yet."}
                    </p>
                  </div>
                <% end %>
              </div>
            </div>
          </div>
          
    <!-- Role Details Panel -->
          <div class="lg:col-span-1">
            <%= if @selected_role do %>
              <div class="bg-white shadow rounded-lg">
                <div class="px-6 py-4 border-b border-gray-200">
                  <h3 class="text-lg font-medium text-gray-900">Role Details</h3>
                </div>
                <div class="px-6 py-4">
                  <div class="space-y-4">
                    <div>
                      <dt class="text-sm font-medium text-gray-500">Role Name</dt>
                      <dd class="mt-1 text-sm text-gray-900">{@selected_role.name}</dd>
                    </div>
                    <div>
                      <dt class="text-sm font-medium text-gray-500">Permissions</dt>
                      <dd class="mt-1">
                        <div class="flex flex-wrap gap-1">
                          <%= for permission <- @selected_role.permissions do %>
                            <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-indigo-100 text-indigo-800">
                              {permission}
                            </span>
                          <% end %>
                        </div>
                      </dd>
                    </div>
                    <div>
                      <dt class="text-sm font-medium text-gray-500">Assigned Users</dt>
                      <dd class="mt-1 text-sm text-gray-900">
                        {@selected_role.user_count} user(s)
                      </dd>
                    </div>
                  </div>
                </div>
                
    <!-- Users Section -->
                <div class="border-t border-gray-200">
                  <div class="px-6 py-4">
                    <div class="flex items-center justify-between">
                      <h4 class="text-sm font-medium text-gray-900">Assigned Users</h4>
                      <button
                        type="button"
                        class="inline-flex items-center px-3 py-1 border border-transparent text-xs font-medium rounded text-indigo-700 bg-indigo-100 hover:bg-indigo-200"
                        phx-click="show_user_assignment"
                      >
                        <.icon name="hero-plus" class="h-3 w-3 mr-1" /> Assign User
                      </button>
                    </div>

                    <div class="mt-4 space-y-2">
                      <%= for user <- @selected_role.users do %>
                        <div class="flex items-center justify-between p-2 bg-gray-50 rounded">
                          <div class="flex items-center">
                            <div class={"h-6 w-6 rounded-full flex items-center justify-center text-white text-xs font-medium #{if user.active, do: "bg-green-500", else: "bg-gray-400"}"}>
                              {String.first(user.username) |> String.upcase()}
                            </div>
                            <div class="ml-2">
                              <span class="text-sm font-medium text-gray-900">{user.username}</span>
                              <div class="text-xs text-gray-500">{user.email}</div>
                            </div>
                          </div>
                          <button
                            type="button"
                            class="text-red-600 hover:text-red-800"
                            phx-click="remove_role_from_user"
                            phx-value-user_id={user.id}
                          >
                            <.icon name="hero-trash" class="h-4 w-4" />
                          </button>
                        </div>
                      <% end %>

                      <%= if @selected_role.users == [] do %>
                        <p class="text-sm text-gray-500 italic">No users assigned to this role</p>
                      <% end %>
                    </div>
                  </div>
                </div>
                
    <!-- User Assignment Form -->
                <%= if @show_user_assignment do %>
                  <div class="border-t border-gray-200 bg-gray-50">
                    <div class="px-6 py-4">
                      <h5 class="text-sm font-medium text-gray-900 mb-3">Assign Role to User</h5>
                      <div class="space-y-2">
                        <%= for user <- @available_users do %>
                          <%= unless Enum.any?(@selected_role.users, fn assigned_user -> assigned_user.id == user.id end) do %>
                            <button
                              type="button"
                              class="w-full flex items-center justify-between p-2 text-left border border-gray-200 rounded hover:bg-white hover:border-indigo-300"
                              phx-click="assign_role_to_user"
                              phx-value-user_id={user.id}
                            >
                              <div class="flex items-center">
                                <div class={"h-6 w-6 rounded-full flex items-center justify-center text-white text-xs font-medium #{if user.active, do: "bg-green-500", else: "bg-gray-400"}"}>
                                  {String.first(user.username) |> String.upcase()}
                                </div>
                                <div class="ml-2">
                                  <div class="text-sm font-medium text-gray-900">{user.username}</div>
                                  <div class="text-xs text-gray-500">{user.email}</div>
                                </div>
                              </div>
                              <.icon name="hero-plus" class="h-4 w-4 text-gray-400" />
                            </button>
                          <% end %>
                        <% end %>
                      </div>
                      <div class="mt-4">
                        <button
                          type="button"
                          class="w-full inline-flex justify-center py-2 px-4 border border-gray-300 shadow-sm text-xs font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50"
                          phx-click="hide_user_assignment"
                        >
                          Cancel
                        </button>
                      </div>
                    </div>
                  </div>
                <% end %>
              </div>
            <% else %>
              <div class="bg-white shadow rounded-lg">
                <div class="text-center py-12">
                  <.icon name="hero-key" class="mx-auto h-12 w-12 text-gray-400" />
                  <h3 class="mt-2 text-sm font-medium text-gray-900">No Role Selected</h3>
                  <p class="mt-1 text-sm text-gray-500">
                    Select a role from the list to view details and manage user assignments.
                  </p>
                </div>
              </div>
            <% end %>
          </div>
        </div>
        
    <!-- Role Creation Form Modal -->
        <%= if @show_role_form do %>
          <div class="fixed inset-0 z-50 overflow-y-auto" phx-click="hide_role_form">
            <div class="flex items-end justify-center min-h-screen pt-4 px-4 pb-20 text-center sm:block sm:p-0">
              <div class="fixed inset-0 bg-gray-500 bg-opacity-75 transition-opacity"></div>
              <span class="hidden sm:inline-block sm:align-middle sm:h-screen">&#8203;</span>
              <div
                class="inline-block align-bottom bg-white rounded-lg text-left overflow-hidden shadow-xl transform transition-all sm:my-8 sm:align-middle sm:max-w-lg sm:w-full"
                phx-click-away="hide_role_form"
              >
                <div class="bg-white px-4 pt-5 pb-4 sm:p-6 sm:pb-4">
                  <div class="sm:flex sm:items-start">
                    <div class="mx-auto flex-shrink-0 flex items-center justify-center h-12 w-12 rounded-full bg-indigo-100 sm:mx-0 sm:h-10 sm:w-10">
                      <.icon name="hero-key" class="h-6 w-6 text-indigo-600" />
                    </div>
                    <div class="mt-3 text-center sm:mt-0 sm:ml-4 sm:text-left w-full">
                      <h3 class="text-lg leading-6 font-medium text-gray-900">Create New Role</h3>
                      <div class="mt-4">
                        <form phx-submit="create_role" phx-change="update_role_form">
                          <div class="space-y-4">
                            <div>
                              <label class="block text-sm font-medium text-gray-700">Role Name</label>
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
                              <label class="block text-sm font-medium text-gray-700">
                                Permissions
                              </label>
                              <div class="mt-2 space-y-2">
                                <%= for permission <- @available_permissions do %>
                                  <label class="flex items-center">
                                    <input
                                      type="checkbox"
                                      name="role[permissions][]"
                                      value={permission}
                                      checked={permission in Map.get(@role_form, "permissions", [])}
                                      class="rounded border-gray-300 text-indigo-600 focus:ring-indigo-500"
                                    />
                                    <span class="ml-2 text-sm text-gray-700 capitalize">
                                      {permission}
                                    </span>
                                  </label>
                                <% end %>
                              </div>
                            </div>
                          </div>
                          <div class="mt-6 flex space-x-3">
                            <button
                              type="submit"
                              class="w-full inline-flex justify-center rounded-md border border-transparent shadow-sm px-4 py-2 bg-indigo-600 text-base font-medium text-white hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500 sm:text-sm"
                            >
                              Create Role
                            </button>
                            <button
                              type="button"
                              class="w-full inline-flex justify-center rounded-md border border-gray-300 shadow-sm px-4 py-2 bg-white text-base font-medium text-gray-700 hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500 sm:text-sm"
                              phx-click="hide_role_form"
                            >
                              Cancel
                            </button>
                          </div>
                        </form>
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        <% end %>
      </main>
    </div>
    """
  end
end
