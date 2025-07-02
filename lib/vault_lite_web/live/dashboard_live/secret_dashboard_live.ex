defmodule VaultLiteWeb.DashboardLive.SecretDashboardLive do
  @moduledoc """
  This module is responsible for the secret dashboard live view.
  - displays the secrets and allows the user to create, update, and delete them.
  - displays the secret details and allows the user to view the secret.
  - displays the secret creation form and allows the user to create new secrets.
  - displays the secret update form and allows the user to update existing secrets.
  """
  use VaultLiteWeb, :live_view

  alias VaultLite.Secrets
  alias VaultLite.Schema.User

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
        # all, personal, role_based, shared_with_me
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
            secret.secret_type == "personal" && !Map.get(secret, :is_shared, false)
          end)

        "role_based" ->
          Enum.filter(searched_secrets, fn secret ->
            secret.secret_type == "role_based"
          end)

        "shared_with_me" ->
          Enum.filter(searched_secrets, fn secret ->
            Map.get(secret, :is_shared, false)
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

  defp secret_type_badge(secret) do
    cond do
      Map.get(secret, :is_shared, false) ->
        {"Shared by #{Map.get(secret, :shared_by, "Unknown")}", "bg-purple-100 text-purple-800"}

      secret.secret_type == "personal" ->
        {"Personal", "bg-blue-100 text-blue-800"}

      secret.secret_type == "role_based" ->
        {"Role-based", "bg-green-100 text-green-800"}

      true ->
        {"Unknown", "bg-gray-100 text-gray-800"}
    end
  end

  defp can_share_secret?(secret, user) do
    secret.secret_type == "personal" &&
      secret.owner_id == user.id &&
      !Map.get(secret, :is_shared, false)
  end

  defp can_edit_secret?(secret, user) do
    cond do
      Map.get(secret, :is_shared, false) ->
        Map.get(secret, :permission_level) == "editable"

      secret.secret_type == "personal" ->
        secret.owner_id == user.id

      secret.secret_type == "role_based" ->
        # Use existing role-based authorization logic if needed
        true

      true ->
        false
    end
  end

  defp can_delete_secret?(secret, user) do
    # Only owners can delete secrets, not shared users
    secret.secret_type == "personal" && secret.owner_id == user.id &&
      !Map.get(secret, :is_shared, false)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <VaultLiteWeb.Layouts.app flash={@flash} current_user={@current_user}>
      <div class="h-full">
        <!-- Main Content -->
        <main class="max-w-7xl mx-auto py-6 px-4 sm:px-6 lg:px-8">
          <!-- Search and Title -->
          <div class="mb-6">
            <h1 class="text-2xl font-bold mb-4">Your Secrets</h1>

            <div class="flex flex-col sm:flex-row gap-4 items-start sm:items-center justify-between">
              <!-- Search -->
              <.form for={%{}} phx-submit="search" class="flex-1 max-w-md">
                <div class="form-control">
                  <div class="relative">
                    <div class="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none">
                      <.icon name="hero-magnifying-glass" class="h-5 w-5 opacity-80" />
                    </div>
                    <input
                      name="search[query]"
                      type="text"
                      value={@search_query}
                      placeholder="Search secrets..."
                      class="input input-bordered w-full pl-10"
                      phx-change="search"
                      phx-debounce="300"
                    />
                  </div>
                </div>
              </.form>
              
    <!-- Filter Buttons -->
              <div role="tablist" class="tabs tabs-box">
                <button
                  phx-click="filter_secrets"
                  phx-value-filter="all"
                  role="tab"
                  class={[
                    "tab",
                    if(@filter_type == "all",
                      do: "tab-active",
                      else: ""
                    )
                  ]}
                >
                  All Secrets
                </button>
                <button
                  phx-click="filter_secrets"
                  phx-value-filter="personal"
                  role="tab"
                  class={[
                    "tab",
                    if(@filter_type == "personal",
                      do: "tab-active",
                      else: ""
                    )
                  ]}
                >
                  Personal
                </button>
                <button
                  phx-click="filter_secrets"
                  phx-value-filter="shared_with_me"
                  role="tab"
                  class={[
                    "tab",
                    if(@filter_type == "shared_with_me",
                      do: "tab-active",
                      else: ""
                    )
                  ]}
                >
                  Shared with Me
                </button>
                <button
                  phx-click="filter_secrets"
                  phx-value-filter="role_based"
                  role="tab"
                  class={[
                    "tab",
                    if(@filter_type == "role_based",
                      do: "tab-active",
                      else: ""
                    )
                  ]}
                >
                  Role-based
                </button>
              </div>
            </div>
          </div>
          
    <!-- Secrets List -->
          <div class="card bg-base-100">
            <%= if length(@secrets) == 0 do %>
              <div class="card-body text-center">
                <.icon name="hero-key" class="mx-auto h-12 w-12" />
                <h3 class="card-title justify-center">No secrets</h3>
                <p>
                  <%= cond do %>
                    <% @search_query != "" and @filter_type != "all" -> %>
                      No {String.replace(@filter_type, "_", " ")} secrets found matching "{@search_query}"
                    <% @search_query != "" -> %>
                      No secrets found matching "{@search_query}"
                    <% @filter_type == "personal" -> %>
                      You don't have any personal secrets yet.
                    <% @filter_type == "shared_with_me" -> %>
                      No secrets have been shared with you yet.
                    <% @filter_type == "role_based" -> %>
                      You don't have access to any role-based secrets.
                    <% true -> %>
                      Get started by creating your first secret.
                  <% end %>
                </p>
                <div class="card-actions justify-center">
                  <.link navigate="/secrets/new" class="btn btn-primary">
                    <.icon name="hero-plus" class="h-5 w-5" /> New Secret
                  </.link>
                </div>
              </div>
            <% else %>
              <div class="overflow-x-auto">
                <table class="table">
                  <tbody>
                    <%= for secret <- @secrets do %>
                      <tr>
                        <td>
                          <div class="flex items-center gap-3">
                            <div class="avatar">
                              <%= if secret.secret_type == "personal" do %>
                                <div class="mask mask-squircle w-12 h-12">
                                  <.icon name="hero-user" class="h-8 w-8" />
                                </div>
                              <% else %>
                                <div class="mask mask-squircle w-12 h-12">
                                  <.icon name="hero-key" class="h-8 w-8" />
                                </div>
                              <% end %>
                            </div>
                            <div>
                              <div class="flex items-center gap-2">
                                <div class="font-bold">{secret.key}</div>
                                <div class="badge badge-ghost badge-sm">v{secret.version}</div>
                                <% {badge_text, badge_class} = secret_type_badge(secret) %>
                                <div class={["badge badge-outline badge-sm", badge_class]}>
                                  {badge_text}
                                </div>
                                <%= if Map.get(secret, :is_shared, false) do %>
                                  <div class={[
                                    "badge badge-sm",
                                    if(Map.get(secret, :permission_level) == "editable",
                                      do: "badge-warning",
                                      else: "badge-info"
                                    )
                                  ]}>
                                    {String.replace(
                                      Map.get(secret, :permission_level, "read_only"),
                                      "_",
                                      " "
                                    )
                                    |> String.capitalize()}
                                  </div>
                                <% end %>
                              </div>
                              <div class="text-sm opacity-50">
                                <%= if Map.get(secret, :is_shared, false) do %>
                                  Shared with you on {format_date(Map.get(secret, :shared_at))}
                                <% else %>
                                  Last updated {format_date(secret.updated_at)}
                                  <%= if secret.secret_type == "personal" do %>
                                    • Only you can access this secret
                                  <% end %>
                                <% end %>
                              </div>
                            </div>
                          </div>
                        </td>
                        <td>
                          <div class="flex gap-2">
                            <.link
                              navigate={"/secrets/#{secret.key}"}
                              class="btn btn-ghost btn-xs"
                              title="View secret"
                            >
                              <.icon name="hero-eye" class="h-4 w-4" />
                            </.link>

                            <%= if can_edit_secret?(secret, @current_user) do %>
                              <.link
                                navigate={"/secrets/#{secret.key}/edit"}
                                class="btn btn-ghost btn-xs"
                                title="Edit secret"
                              >
                                <.icon name="hero-pencil" class="h-4 w-4" />
                              </.link>
                            <% end %>

                            <%= if can_share_secret?(secret, @current_user) do %>
                              <.link
                                navigate={"/secrets/#{secret.key}/share"}
                                class="btn btn-ghost btn-xs"
                                title="Manage sharing"
                              >
                                <.icon name="hero-share" class="h-4 w-4" />
                              </.link>
                            <% end %>

                            <%= if can_delete_secret?(secret, @current_user) do %>
                              <button
                                phx-click="delete_secret"
                                phx-value-key={secret.key}
                                class="btn btn-ghost btn-xs"
                                title="Delete secret"
                                data-confirm="Are you sure you want to delete this secret?"
                              >
                                <.icon name="hero-trash" class="h-4 w-4" />
                              </button>
                            <% end %>
                          </div>
                        </td>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              </div>
            <% end %>
          </div>
        </main>
      </div>
    </VaultLiteWeb.Layouts.app>
    """
  end
end
