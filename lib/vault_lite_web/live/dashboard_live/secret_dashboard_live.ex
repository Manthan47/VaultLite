defmodule VaultLiteWeb.DashboardLive.SecretDashboardLive do
  @moduledoc """
  This module is responsible for the secret dashboard live view.
  - displays the secrets and allows the user to create, update, and delete them.
  - displays the secret details and allows the user to view the secret.
  - displays the secret creation form and allows the user to create new secrets.
  - displays the secret update form and allows the user to update existing secrets.
  """
  use VaultLiteWeb, :live_view

  alias VaultLite.{Secrets, User}

  @impl true
  def mount(_params, session, socket) do
    current_user = get_current_user(session)

    # Redirect to login if no user found
    if is_nil(current_user) do
      {:ok, redirect(socket, to: "/login")}
    else
      if connected?(socket) do
        VaultLiteWeb.Endpoint.subscribe("secrets:user:#{current_user.id}")
      end

      socket =
        socket
        |> assign(:current_user, current_user)
        |> assign(:page_title, "Dashboard")
        |> assign(:search_query, "")
        |> assign(:secrets, [])
        |> assign(:loading, true)
        # all, personal, role_based
        |> assign(:filter_type, "all")
        |> load_secrets()

      {:ok, socket}
    end
  end

  @impl true
  def handle_event("search", params, socket) do
    # Handle both form submit and input change events
    query =
      case params do
        # From form submit
        %{"search" => %{"query" => q}} -> q
        # From phx-change
        %{"value" => q} -> q
        _ -> ""
      end

    socket =
      socket
      |> assign(:search_query, query)
      |> load_secrets()

    {:noreply, socket}
  end

  @impl true
  def handle_event("filter_secrets", %{"filter" => filter_type}, socket) do
    socket =
      socket
      |> assign(:filter_type, filter_type)
      |> load_secrets()

    {:noreply, socket}
  end

  @impl true
  def handle_event("delete_secret", %{"key" => key}, socket) do
    case Secrets.delete_secret(key, socket.assigns.current_user) do
      {:ok, _} ->
        socket =
          socket
          |> put_flash(:info, "Secret '#{key}' deleted successfully")
          |> load_secrets()

        {:noreply, socket}

      {:error, reason} ->
        error_msg =
          case reason do
            :not_found -> "Secret not found"
            :unauthorized -> "You don't have permission to delete this secret"
            _ -> "Error deleting secret"
          end

        socket = put_flash(socket, :error, error_msg)
        {:noreply, socket}
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

  defp load_secrets(socket) do
    user = socket.assigns.current_user
    search = Map.get(socket.assigns, :search_query, "")
    filter_type = Map.get(socket.assigns, :filter_type, "all")

    {:ok, all_secrets} = Secrets.list_secrets(user)

    # Filter by search if provided
    searched_secrets =
      if search != "" do
        search_term = String.downcase(search)

        Enum.filter(all_secrets, fn secret ->
          String.contains?(String.downcase(secret.key), search_term)
        end)
      else
        all_secrets
      end

    # Filter by secret type
    filtered_secrets =
      case filter_type do
        "personal" ->
          Enum.filter(searched_secrets, fn secret ->
            secret.secret_type == "personal"
          end)

        "role_based" ->
          Enum.filter(searched_secrets, fn secret ->
            secret.secret_type == "role_based"
          end)

        _ ->
          searched_secrets
      end

    socket
    |> assign(:secrets, filtered_secrets)
    |> assign(:loading, false)
  end

  defp format_date(datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M")
  end

  defp secret_type_badge(secret_type) do
    case secret_type do
      "personal" ->
        {"Personal", "bg-blue-100 text-blue-800"}

      "role_based" ->
        {"Role-based", "bg-green-100 text-green-800"}

      _ ->
        {"Unknown", "bg-gray-100 text-gray-800"}
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

              <%= if VaultLite.Auth.is_admin?(@current_user) do %>
                <.link
                  navigate="/admin/users"
                  class="text-gray-500 hover:text-gray-700 px-3 py-2 rounded-md text-sm font-medium"
                >
                  User Management
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
              <% end %>

              <.link
                navigate="/secrets/new"
                class="bg-indigo-600 hover:bg-indigo-700 text-white px-4 py-2 rounded-md text-sm font-medium"
              >
                New Secret
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
        <!-- Flash Messages -->
        <div :if={Phoenix.Flash.get(@flash, :info)} class="mb-4 rounded-md bg-green-50 p-4">
          <div class="flex">
            <div class="flex-shrink-0">
              <.icon name="hero-check-circle" class="h-5 w-5 text-green-400" />
            </div>
            <div class="ml-3">
              <p class="text-sm font-medium text-green-800">
                {Phoenix.Flash.get(@flash, :info)}
              </p>
            </div>
          </div>
        </div>

        <div :if={Phoenix.Flash.get(@flash, :error)} class="mb-4 rounded-md bg-red-50 p-4">
          <div class="flex">
            <div class="flex-shrink-0">
              <.icon name="hero-x-circle" class="h-5 w-5 text-red-400" />
            </div>
            <div class="ml-3">
              <p class="text-sm font-medium text-red-800">
                {Phoenix.Flash.get(@flash, :error)}
              </p>
            </div>
          </div>
        </div>
        
    <!-- Search and Title -->
        <div class="mb-6">
          <h1 class="text-2xl font-bold text-gray-900 mb-4">Your Secrets</h1>

          <div class="flex flex-col sm:flex-row gap-4 items-start sm:items-center justify-between">
            <!-- Search -->
            <.form for={%{}} phx-submit="search" class="flex-1 max-w-md">
              <div class="relative">
                <div class="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none">
                  <.icon name="hero-magnifying-glass" class="h-5 w-5 text-gray-400" />
                </div>
                <input
                  name="search[query]"
                  type="text"
                  value={@search_query}
                  placeholder="Search secrets..."
                  class="block w-full pl-10 pr-3 py-2.5 border border-gray-300 rounded-lg shadow-sm bg-white text-gray-900 placeholder-gray-500 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm"
                  phx-change="search"
                  phx-debounce="300"
                />
              </div>
            </.form>
            
    <!-- Filter Buttons -->
            <div class="flex space-x-2">
              <button
                phx-click="filter_secrets"
                phx-value-filter="all"
                class={[
                  "px-3 py-2 text-sm font-medium rounded-md",
                  if(@filter_type == "all",
                    do: "bg-indigo-100 text-indigo-700 border border-indigo-200",
                    else: "bg-white text-gray-700 border border-gray-300 hover:bg-gray-50"
                  )
                ]}
              >
                All Secrets
              </button>
              <button
                phx-click="filter_secrets"
                phx-value-filter="personal"
                class={[
                  "px-3 py-2 text-sm font-medium rounded-md",
                  if(@filter_type == "personal",
                    do: "bg-blue-100 text-blue-700 border border-blue-200",
                    else: "bg-white text-gray-700 border border-gray-300 hover:bg-gray-50"
                  )
                ]}
              >
                Personal
              </button>
              <button
                phx-click="filter_secrets"
                phx-value-filter="role_based"
                class={[
                  "px-3 py-2 text-sm font-medium rounded-md",
                  if(@filter_type == "role_based",
                    do: "bg-green-100 text-green-700 border border-green-200",
                    else: "bg-white text-gray-700 border border-gray-300 hover:bg-gray-50"
                  )
                ]}
              >
                Role-based
              </button>
            </div>
          </div>
        </div>
        
    <!-- Secrets List -->
        <div class="bg-white shadow overflow-hidden sm:rounded-md">
          <%= if length(@secrets) == 0 do %>
            <div class="p-6 text-center">
              <.icon name="hero-key" class="mx-auto h-12 w-12 text-gray-400" />
              <h3 class="mt-2 text-sm font-medium text-gray-900">No secrets</h3>
              <p class="mt-1 text-sm text-gray-500">
                <%= cond do %>
                  <% @search_query != "" and @filter_type != "all" -> %>
                    No {@filter_type} secrets found matching "{@search_query}"
                  <% @search_query != "" -> %>
                    No secrets found matching "{@search_query}"
                  <% @filter_type == "personal" -> %>
                    You don't have any personal secrets yet.
                  <% @filter_type == "role_based" -> %>
                    You don't have access to any role-based secrets.
                  <% true -> %>
                    Get started by creating your first secret.
                <% end %>
              </p>
              <div class="mt-6">
                <.link
                  navigate="/secrets/new"
                  class="inline-flex items-center px-4 py-2 border border-transparent shadow-sm text-sm font-medium rounded-md text-white bg-indigo-600 hover:bg-indigo-700"
                >
                  <.icon name="hero-plus" class="-ml-1 mr-2 h-5 w-5" /> New Secret
                </.link>
              </div>
            </div>
          <% else %>
            <ul class="divide-y divide-gray-200">
              <%= for secret <- @secrets do %>
                <li>
                  <div class="px-4 py-4 flex items-center justify-between">
                    <div class="flex items-center">
                      <div class="flex-shrink-0">
                        <%= if secret.secret_type == "personal" do %>
                          <.icon name="hero-user" class="h-5 w-5 text-blue-500" />
                        <% else %>
                          <.icon name="hero-key" class="h-5 w-5 text-green-500" />
                        <% end %>
                      </div>
                      <div class="ml-4">
                        <div class="flex items-center">
                          <p class="text-sm font-medium text-indigo-600 truncate">
                            {secret.key}
                          </p>
                          <span class="ml-2 inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-gray-100 text-gray-800">
                            v{secret.version}
                          </span>
                          <% {badge_text, badge_class} = secret_type_badge(secret.secret_type) %>
                          <span class={"ml-2 inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium #{badge_class}"}>
                            {badge_text}
                          </span>
                        </div>
                        <p class="text-sm text-gray-500">
                          Last updated {format_date(secret.updated_at)}
                          <%= if secret.secret_type == "personal" do %>
                            • Only you can access this secret
                          <% end %>
                        </p>
                      </div>
                    </div>
                    <div class="flex items-center space-x-2">
                      <.link
                        navigate={"/secrets/#{secret.key}"}
                        class="text-indigo-600 hover:text-indigo-500 p-1 rounded"
                        title="View secret"
                      >
                        <.icon name="hero-eye" class="h-5 w-5" />
                      </.link>
                      <.link
                        navigate={"/secrets/#{secret.key}/edit"}
                        class="text-yellow-600 hover:text-yellow-500 p-1 rounded"
                        title="Edit secret"
                      >
                        <.icon name="hero-pencil" class="h-5 w-5" />
                      </.link>
                      <button
                        phx-click="delete_secret"
                        phx-value-key={secret.key}
                        class="text-red-600 hover:text-red-500 p-1 rounded"
                        title="Delete secret"
                        data-confirm="Are you sure you want to delete this secret?"
                      >
                        <.icon name="hero-trash" class="h-5 w-5" />
                      </button>
                    </div>
                  </div>
                </li>
              <% end %>
            </ul>
          <% end %>
        </div>
      </main>
    </div>
    """
  end
end
