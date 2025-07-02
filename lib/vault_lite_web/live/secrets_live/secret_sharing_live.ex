defmodule VaultLiteWeb.SecretsLive.SecretSharingLive do
  use VaultLiteWeb, :live_view
  alias VaultLite.{SecretSharing, Auth}

  @impl true
  def mount(%{"secret_key" => secret_key}, session, socket) do
    current_user = get_current_user(session)

    if is_nil(current_user) do
      {:ok, redirect(socket, to: "/login")}
    else
      {:ok, created_shares} = SecretSharing.list_created_shares(current_user)
      shares_for_secret = Enum.filter(created_shares, &(&1.secret_key == secret_key))

      # Get all available users except current user and already shared users
      all_users = Auth.list_all_users()
      already_shared_user_ids = MapSet.new(shares_for_secret, & &1.shared_with_email)

      available_users =
        all_users
        |> Enum.filter(fn user ->
          user.id != current_user.id && !MapSet.member?(already_shared_user_ids, user.email)
        end)
        |> Enum.map(fn user ->
          %{id: user.id, username: user.username, email: user.email}
        end)

      socket =
        socket
        |> assign(:current_user, current_user)
        |> assign(:secret_key, secret_key)
        |> assign(:shares, shares_for_secret)
        |> assign(:available_users, available_users)
        |> assign(:filtered_users, available_users)
        |> assign(:search_query, "")
        |> assign(:selected_users, [])
        |> assign(:share_form, %{"permission_level" => "read_only"})
        |> assign(:page_title, "Share Secret")
        |> assign(:loading, false)
        |> assign(:show_dropdown, false)

      {:ok, socket}
    end
  end

  @impl true
  def handle_event("share_secret", %{"permission_level" => permission}, socket) do
    secret_key = socket.assigns.secret_key
    user = socket.assigns.current_user
    selected_users = socket.assigns.selected_users

    # Validate input
    if Enum.empty?(selected_users) do
      socket = put_flash(socket, :error, "Please select at least one user to share with")
      {:noreply, socket}
    else
      socket = assign(socket, :loading, true)

      # Share with all selected users
      results =
        Enum.map(selected_users, fn selected_user ->
          SecretSharing.share_secret(secret_key, user, selected_user.username, permission)
        end)

      # Check results
      {successes, failures} =
        Enum.split_with(results, fn result -> match?({:ok, _}, result) end)

      success_count = length(successes)
      failure_count = length(failures)

      socket =
        socket
        |> assign(:loading, false)
        |> assign(:selected_users, [])
        |> assign(:share_form, %{"permission_level" => "read_only"})
        |> reload_shares()
        |> reload_available_users()

      socket =
        cond do
          failure_count == 0 ->
            put_flash(socket, :info, "Secret shared successfully with #{success_count} user(s)")

          success_count == 0 ->
            put_flash(socket, :error, "Failed to share secret with all selected users")

          true ->
            put_flash(
              socket,
              :warning,
              "Shared with #{success_count} user(s), but failed for #{failure_count} user(s)"
            )
        end

      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("revoke_share", %{"username" => username}, socket) do
    secret_key = socket.assigns.secret_key
    user = socket.assigns.current_user

    case SecretSharing.revoke_sharing(secret_key, user, username) do
      {:ok, _} ->
        socket =
          socket
          |> put_flash(:info, "Sharing revoked for #{username}")
          |> reload_shares()

        {:noreply, socket}

      {:error, reason} ->
        error_msg =
          case reason do
            :user_not_found -> "User not found"
            :share_not_found -> "Share not found"
            _ -> "Error revoking share"
          end

        socket = put_flash(socket, :error, error_msg)
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("validate_form", %{"permission_level" => permission}, socket) do
    # Update form state for real-time validation
    socket = assign(socket, :share_form, %{"permission_level" => permission})
    {:noreply, socket}
  end

  @impl true
  def handle_event("search_users", %{"value" => search_query}, socket) do
    filtered_users =
      if String.trim(search_query) == "" do
        socket.assigns.available_users
      else
        query = String.downcase(String.trim(search_query))

        Enum.filter(socket.assigns.available_users, fn user ->
          String.contains?(String.downcase(user.username), query) ||
            String.contains?(String.downcase(user.email), query)
        end)
      end

    socket =
      socket
      |> assign(:search_query, search_query)
      |> assign(:filtered_users, filtered_users)
      |> assign(:show_dropdown, String.trim(search_query) != "")

    {:noreply, socket}
  end

  @impl true
  def handle_event("select_user", %{"user_id" => user_id}, socket) do
    user_id = String.to_integer(user_id)
    user_to_add = Enum.find(socket.assigns.available_users, &(&1.id == user_id))

    if user_to_add && !Enum.any?(socket.assigns.selected_users, &(&1.id == user_id)) do
      socket =
        socket
        |> assign(:selected_users, [user_to_add | socket.assigns.selected_users])
        |> assign(:search_query, "")
        |> assign(:show_dropdown, false)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("remove_user", %{"user_id" => user_id}, socket) do
    user_id = String.to_integer(user_id)
    updated_selected_users = Enum.reject(socket.assigns.selected_users, &(&1.id == user_id))

    socket = assign(socket, :selected_users, updated_selected_users)
    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_dropdown", _params, socket) do
    socket = assign(socket, :show_dropdown, !socket.assigns.show_dropdown)
    {:noreply, socket}
  end

  @impl true
  def handle_event("close_dropdown", _params, socket) do
    socket = assign(socket, :show_dropdown, false)
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <VaultLiteWeb.Layouts.app flash={@flash} current_user={@current_user}>
      <div class="min-h-screen">
        <!-- Main Content -->
        <main class="max-w-4xl mx-auto py-6 px-4 sm:px-6 lg:px-8">
          <!-- Flash Messages -->
          <div :if={Phoenix.Flash.get(@flash, :info)} class="alert alert-success mb-4">
            <.icon name="hero-check-circle" class="h-5 w-5" />
            <span>{Phoenix.Flash.get(@flash, :info)}</span>
          </div>

          <div :if={Phoenix.Flash.get(@flash, :error)} class="alert alert-error mb-4">
            <.icon name="hero-x-circle" class="h-5 w-5" />
            <span>{Phoenix.Flash.get(@flash, :error)}</span>
          </div>
          
    <!-- Header -->
          <div class="mb-6">
            <!-- Simple Breadcrumb -->
            <div class="text-sm breadcrumbs mb-4">
              <ul>
                <li><.link navigate="/dashboard" class="link">Dashboard</.link></li>
                <li>
                  <.link navigate={"/secrets/#{@secret_key}"} class="link">{@secret_key}</.link>
                </li>
                <li>Share</li>
              </ul>
            </div>

            <h1 class="text-2xl font-bold mb-2">Share Secret</h1>
            <p>
              Manage who can access "<span class="badge badge-ghost"><%= @secret_key %></span>" and their permission levels.
            </p>
          </div>
          
    <!-- Share Form -->
          <div class="card bg-base-100 mb-6">
            <div class="card-body">
              <h2 class="card-title">Share with Users</h2>

              <.form for={%{}} phx-submit="share_secret" phx-change="validate_form" class="space-y-4">
                <!-- Multi-Select User Dropdown -->
                <div class="form-control">
                  <label class="label">
                    <span class="label-text font-medium">Select Users</span>
                  </label>
                  
    <!-- Selected Users Display -->
                  <%= if !Enum.empty?(@selected_users) do %>
                    <div class="flex flex-wrap gap-2 mb-2">
                      <%= for user <- @selected_users do %>
                        <div class="badge badge-primary gap-2">
                          <span>{user.username}</span>
                          <button
                            type="button"
                            phx-click="remove_user"
                            phx-value-user_id={user.id}
                            class="btn btn-ghost btn-xs"
                          >
                            <.icon name="hero-x-mark" class="w-3 h-3" />
                          </button>
                        </div>
                      <% end %>
                    </div>
                  <% end %>
                  
    <!-- Search Input -->
                  <div class="relative">
                    <input
                      type="text"
                      placeholder={
                        if Enum.empty?(@available_users),
                          do: "No available users to share with",
                          else: "Search users by username or email..."
                      }
                      class="input input-bordered w-full"
                      value={@search_query}
                      phx-keyup="search_users"
                      phx-debounce="300"
                      disabled={Enum.empty?(@available_users)}
                    />
                    
    <!-- Dropdown -->
                    <%= if @show_dropdown && !Enum.empty?(@filtered_users) do %>
                      <div class="absolute z-10 w-full mt-1 bg-base-100 border border-base-300 rounded-lg shadow-lg max-h-60 overflow-y-auto">
                        <%= for user <- @filtered_users do %>
                          <div
                            class="p-3 hover:bg-base-200 cursor-pointer flex items-center justify-between"
                            phx-click="select_user"
                            phx-value-user_id={user.id}
                          >
                            <div>
                              <div class="font-medium">{user.username}</div>
                              <div class="text-sm opacity-60">{user.email}</div>
                            </div>
                            <.icon name="hero-plus" class="w-4 h-4 opacity-60" />
                          </div>
                        <% end %>
                      </div>
                    <% end %>
                  </div>

                  <label class="label">
                    <span class="label-text-alt">
                      Search and select multiple users to share this secret with
                    </span>
                  </label>
                </div>

                <div class="form-control">
                  <label class="label">
                    <span class="label-text font-medium">Permission Level</span>
                  </label>
                  <select
                    id="permission_level"
                    name="permission_level"
                    class="select select-bordered w-full"
                    value={@share_form["permission_level"]}
                  >
                    <option value="read_only">Read Only</option>
                    <option value="editable">Editable</option>
                  </select>
                  <label class="label">
                    <span class="label-text-alt">
                      <strong>Read Only:</strong>
                      Users can view the secret but cannot modify it.<br />
                      <strong>Editable:</strong>
                      Users can view and modify the secret.
                    </span>
                  </label>
                </div>

                <div class="card-actions justify-end">
                  <button
                    type="submit"
                    class={[
                      "btn btn-primary",
                      if(@loading, do: "loading", else: "")
                    ]}
                    disabled={@loading || Enum.empty?(@selected_users)}
                  >
                    <%= if @loading do %>
                      <span class="loading loading-spinner loading-sm"></span> Sharing...
                    <% else %>
                      <.icon name="hero-share" class="w-4 h-4 mr-2" />
                      Share with {length(@selected_users)} user(s)
                    <% end %>
                  </button>
                </div>
              </.form>
            </div>
          </div>
          
    <!-- Current Shares -->
          <div class="card bg-base-100">
            <div class="card-body">
              <h2 class="card-title">Current Shares</h2>

              <%= if Enum.empty?(@shares) do %>
                <div class="text-center py-8">
                  <.icon name="hero-users" class="mx-auto h-12 w-12 opacity-40" />
                  <h3 class="mt-2 text-lg font-medium">No shares</h3>
                  <p class="mt-1 opacity-60">This secret is not currently shared with anyone.</p>
                </div>
              <% else %>
                <div class="overflow-x-auto">
                  <table class="table">
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
                        <tr class="hover">
                          <td>
                            <div class="flex items-center gap-3">
                              <div class="avatar placeholder">
                                <div class="bg-primary text-primary-content rounded-full w-8 h-8">
                                  <span class="text-sm">
                                    {String.first(String.upcase(share.shared_with_username))}
                                  </span>
                                </div>
                              </div>
                              <div>
                                <div class="font-bold">{share.shared_with_username}</div>
                                <div class="text-sm opacity-50">{share.shared_with_email}</div>
                              </div>
                            </div>
                          </td>
                          <td>
                            <div class={[
                              "badge",
                              if(share.permission_level == "editable",
                                do: "badge-warning",
                                else: "badge-info"
                              )
                            ]}>
                              {String.replace(share.permission_level, "_", " ") |> String.capitalize()}
                            </div>
                          </td>
                          <td>
                            <span class="text-sm">{format_date(share.shared_at)}</span>
                          </td>
                          <td>
                            <button
                              phx-click="revoke_share"
                              phx-value-username={share.shared_with_username}
                              class="btn btn-ghost btn-sm btn-error"
                              onclick="return confirm('Are you sure you want to revoke sharing with this user?')"
                            >
                              <.icon name="hero-x-mark" class="w-4 h-4" /> Revoke
                            </button>
                          </td>
                        </tr>
                      <% end %>
                    </tbody>
                  </table>
                </div>
              <% end %>
            </div>
          </div>
          
    <!-- Back Button -->
          <div class="mt-6">
            <.link navigate="/dashboard" class="btn btn-ghost">
              <.icon name="hero-arrow-left" class="w-4 h-4" /> Back to Dashboard
            </.link>
          </div>
        </main>
      </div>
      
    <!-- JavaScript for dropdown handling -->
      <script>
        document.addEventListener('click', function(event) {
          const dropdown = document.querySelector('.absolute.z-10');
          const searchInput = document.querySelector('input[phx-keyup="search_users"]');

          if (dropdown && !dropdown.contains(event.target) && event.target !== searchInput) {
            // Click outside dropdown - close it
            const liveSocket = window.liveSocket;
            if (liveSocket) {
              liveSocket.execJS(document.body, 'this.dispatchEvent(new CustomEvent("phx:close-dropdown"))');
            }
          }
        });

        // Close dropdown on escape key
        document.addEventListener('keydown', function(event) {
          if (event.key === 'Escape') {
            const liveSocket = window.liveSocket;
            if (liveSocket) {
              liveSocket.execJS(document.body, 'this.dispatchEvent(new CustomEvent("phx:close-dropdown"))');
            }
          }
        });

        // Custom event handler for closing dropdown
        document.addEventListener('phx:close-dropdown', function() {
          const view = window.liveSocket.getViewByEl(document.body);
          if (view) {
            view.pushEvent('close_dropdown', {});
          }
        });
      </script>
    </VaultLiteWeb.Layouts.app>
    """
  end

  # Private helper functions

  defp reload_shares(socket) do
    secret_key = socket.assigns.secret_key
    user = socket.assigns.current_user
    {:ok, created_shares} = SecretSharing.list_created_shares(user)
    shares_for_secret = Enum.filter(created_shares, &(&1.secret_key == secret_key))

    assign(socket, :shares, shares_for_secret)
  end

  defp reload_available_users(socket) do
    current_user = socket.assigns.current_user
    shares_for_secret = socket.assigns.shares

    # Get all available users except current user and already shared users
    all_users = Auth.list_all_users()
    already_shared_user_ids = MapSet.new(shares_for_secret, & &1.shared_with_email)

    available_users =
      all_users
      |> Enum.filter(fn user ->
        user.id != current_user.id && !MapSet.member?(already_shared_user_ids, user.email)
      end)
      |> Enum.map(fn user ->
        %{id: user.id, username: user.username, email: user.email}
      end)

    socket
    |> assign(:available_users, available_users)
    |> assign(:filtered_users, available_users)
  end

  defp format_date(datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M")
  end

  defp get_current_user(session) do
    case Map.get(session, "user_token") do
      nil ->
        nil

      user_id when is_integer(user_id) ->
        VaultLite.Repo.get(VaultLite.User, user_id)

      user_id when is_binary(user_id) ->
        case Integer.parse(user_id) do
          {id, ""} -> VaultLite.Repo.get(VaultLite.User, id)
          _ -> nil
        end
    end
  end
end
