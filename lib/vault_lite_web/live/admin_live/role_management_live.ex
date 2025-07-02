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
    <VaultLiteWeb.Layouts.app flash={@flash} current_user={@current_user}>
      <div class="min-h-screen">
        <!-- Main Content -->
        <main class="max-w-7xl mx-auto py-6 px-4 sm:px-6 lg:px-8">
          <div class="mb-6">
            <div class="flex items-center justify-between">
              <div>
                <h1 class="text-2xl font-bold">Role Management</h1>
                <p class="mt-1 text-sm opacity-70">
                  Manage roles, permissions, and user assignments
                </p>
              </div>
              <button type="button" class="btn btn-primary" phx-click="show_role_form">
                <.icon name="hero-plus" class="h-4 w-4 mr-2" /> Create Role
              </button>
            </div>
          </div>

          <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
            <!-- Role List Panel -->
            <div class="lg:col-span-2">
              <div class="card bg-base-100 shadow">
                <div class="card-body">
                  <h2 class="card-title">Roles</h2>
                  <!-- Search -->
                  <div class="form-control">
                    <form phx-submit="search" phx-change="search">
                      <input
                        type="text"
                        name="query"
                        value={@search_query}
                        placeholder="Search roles by name or permissions..."
                        class="input input-bordered w-full"
                      />
                    </form>
                  </div>

                  <div class="space-y-2">
                    <%= for role <- @roles do %>
                      <div
                        class={[
                          "card bg-base-200 cursor-pointer hover:bg-base-300",
                          if(@selected_role && @selected_role.name == role.name,
                            do: "ring-2 ring-primary",
                            else: ""
                          )
                        ]}
                        phx-click="select_role"
                        phx-value-name={role.name}
                      >
                        <div class="card-body p-4">
                          <div class="flex items-center">
                            <%!-- <div class="avatar placeholder"> --%>
                            <%!-- <div class="w-10 rounded-full bg-primary text-primary-content"> --%>
                            <.icon name="hero-key" class="mr-auto h-8 w-8" />
                            <%!-- </div> --%>
                            <%!-- </div> --%>
                            <div class="ml-4 flex-1">
                              <h3 class="font-medium">{role.name}</h3>
                              <div class="flex items-center gap-1 mt-1">
                                <%= for permission <- role.permissions do %>
                                  <div class="badge badge-ghost text-xs">
                                    {permission}
                                  </div>
                                <% end %>
                              </div>
                              <p class="text-xs opacity-70 mt-1">
                                {role.user_count} user(s) assigned
                              </p>
                            </div>
                          </div>
                        </div>
                      </div>
                    <% end %>

                    <%= if @roles == [] do %>
                      <div class="text-center py-12">
                        <.icon name="hero-key" class="mx-auto h-12 w-12" />
                        <h3 class="mt-2 text-sm font-medium">No roles found</h3>
                        <p class="mt-1 text-sm opacity-70">
                          {if @search_query != "",
                            do: "Try adjusting your search query.",
                            else: "No roles in the system yet."}
                        </p>
                      </div>
                    <% end %>
                  </div>
                </div>
              </div>
            </div>
            
    <!-- Role Details Panel -->
            <div class="lg:col-span-1">
              <%= if @selected_role do %>
                <div class="card bg-base-100 shadow">
                  <div class="card-body">
                    <h3 class="card-title">Role Details</h3>

                    <div class="space-y-4">
                      <div>
                        <label class="label">
                          <span class="label-text font-medium">Role Name</span>
                        </label>
                        <div class="text-sm">{@selected_role.name}</div>
                      </div>
                      <div>
                        <label class="label">
                          <span class="label-text font-medium">Permissions</span>
                        </label>
                        <div class="flex flex-wrap gap-1">
                          <%= for permission <- @selected_role.permissions do %>
                            <div class="badge badge-primary">
                              {permission}
                            </div>
                          <% end %>
                        </div>
                      </div>
                      <div>
                        <label class="label">
                          <span class="label-text font-medium">Assigned Users</span>
                        </label>
                        <div class="text-sm">
                          {@selected_role.user_count} user(s)
                        </div>
                      </div>
                    </div>
                    
    <!-- Users Section -->
                    <div class="divider"></div>
                    <div>
                      <div class="flex items-center justify-between">
                        <h4 class="font-medium">Assigned Users</h4>
                        <button
                          type="button"
                          class="btn btn-sm btn-primary"
                          phx-click="show_user_assignment"
                        >
                          <.icon name="hero-plus" class="h-3 w-3 mr-1" /> Assign User
                        </button>
                      </div>

                      <div class="space-y-2 mt-4">
                        <%= for user <- @selected_role.users do %>
                          <div class="card bg-base-200">
                            <div class="card-body p-3">
                              <div class="flex items-center justify-between">
                                <div class="flex items-center">
                                  <div class="relative">
                                    <div class="avatar placeholder">
                                      <div class="w-10 h-10 rounded-full bg-base-300 flex items-center justify-center">
                                        <.icon name="hero-user" class="h-6 w-6" />
                                      </div>
                                    </div>
                                    <span class={[
                                      "absolute bottom-0 right-0 block h-3 w-3 rounded-full ring-2 ring-base-100",
                                      if(user.active,
                                        do: "bg-success",
                                        else: "bg-base-content opacity-20"
                                      )
                                    ]} />
                                  </div>
                                  <div class="ml-2">
                                    <div class="text-sm font-medium">{user.username}</div>
                                    <div class="text-xs opacity-70">{user.email}</div>
                                  </div>
                                </div>
                                <button
                                  type="button"
                                  class="btn btn-ghost btn-xs"
                                  phx-click="remove_role_from_user"
                                  phx-value-user_id={user.id}
                                >
                                  <.icon name="hero-trash" class="h-4 w-4" />
                                </button>
                              </div>
                            </div>
                          </div>
                        <% end %>

                        <%= if @selected_role.users == [] do %>
                          <p class="text-sm opacity-70 italic">No users assigned to this role</p>
                        <% end %>
                      </div>
                    </div>
                    
    <!-- User Assignment Form -->
                    <%= if @show_user_assignment do %>
                      <div class="divider"></div>
                      <div>
                        <h5 class="font-medium mb-3">Assign Role to User</h5>
                        <div class="space-y-2 max-h-60 overflow-y-auto">
                          <%= for user <- @available_users do %>
                            <%= unless Enum.any?(@selected_role.users, fn assigned_user -> assigned_user.id == user.id end) do %>
                              <button
                                type="button"
                                class="btn btn-outline btn-sm w-full justify-between"
                                phx-click="assign_role_to_user"
                                phx-value-user_id={user.id}
                              >
                                <div class="flex items-center">
                                  <div class={[
                                    "avatar placeholder",
                                    if(user.active, do: "online", else: "offline")
                                  ]}>
                                    <div class={[
                                      "w-6 rounded-full text-xs",
                                      if(user.active,
                                        do: "bg-success text-success-content",
                                        else: "bg-base-300"
                                      )
                                    ]}>
                                      {String.first(user.username) |> String.upcase()}
                                    </div>
                                  </div>
                                  <div class="ml-2 text-left">
                                    <div class="text-sm font-medium">
                                      {user.username}
                                    </div>
                                    <div class="text-xs opacity-70">{user.email}</div>
                                  </div>
                                </div>
                                <.icon name="hero-plus" class="h-4 w-4" />
                              </button>
                            <% end %>
                          <% end %>
                        </div>
                        <div class="mt-4">
                          <button
                            type="button"
                            class="btn btn-outline w-full"
                            phx-click="hide_user_assignment"
                          >
                            Cancel
                          </button>
                        </div>
                      </div>
                    <% end %>
                  </div>
                </div>
              <% else %>
                <div class="card bg-base-100 shadow">
                  <div class="card-body">
                    <div class="text-center py-12">
                      <.icon name="hero-key" class="mx-auto h-12 w-12" />
                      <h3 class="mt-2 text-sm font-medium">No Role Selected</h3>
                      <p class="mt-1 text-sm opacity-70">
                        Select a role from the list to view details and manage user assignments.
                      </p>
                    </div>
                  </div>
                </div>
              <% end %>
            </div>
          </div>
          
    <!-- Role Creation Form Modal -->
          <%= if @show_role_form do %>
            <div class="modal modal-open" phx-click="hide_role_form">
              <div class="modal-box" phx-click-away="hide_role_form">
                <div class="flex items-center mb-4">
                  <div class="avatar placeholder">
                    <div class="w-10 rounded-full bg-primary text-primary-content">
                      <.icon name="hero-key" class="h-6 w-6" />
                    </div>
                  </div>
                  <h3 class="font-bold text-lg ml-4">Create New Role</h3>
                </div>

                <form phx-submit="create_role" phx-change="update_role_form">
                  <div class="space-y-4">
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
                      <div class="space-y-2">
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
                  </div>
                  <div class="modal-action">
                    <button type="submit" class="btn btn-primary">
                      Create Role
                    </button>
                    <button type="button" class="btn btn-outline" phx-click="hide_role_form">
                      Cancel
                    </button>
                  </div>
                </form>
              </div>
            </div>
          <% end %>
        </main>
      </div>
    </VaultLiteWeb.Layouts.app>
    """
  end
end
