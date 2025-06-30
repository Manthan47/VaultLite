defmodule VaultLiteWeb.SecretsLive.SecretDetailLive do
  @moduledoc """
  This module is responsible for the secret detail live view.
  - displays the secret details and allows the user to view the secret.
  - displays the secret versions and allows the user to view the versions.
  - displays the secret creation form and allows the user to create new secrets.
  - displays the secret update form and allows the user to update existing secrets.
  """
  use VaultLiteWeb, :live_view

  alias VaultLite.{Secrets, User}

  @impl true
  def mount(%{"key" => key}, session, socket) do
    current_user = get_current_user(session)

    if is_nil(current_user) do
      {:ok, redirect(socket, to: "/login")}
    else
      socket =
        socket
        |> assign(:current_user, current_user)
        |> assign(:secret_key, key)
        |> assign(:loading, true)
        |> assign(:secret, nil)
        |> assign(:versions, [])
        |> assign(:error, nil)

      {:ok, socket}
    end
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    case socket.assigns.live_action do
      :show ->
        socket =
          socket
          |> assign(:page_title, "Secret: #{socket.assigns.secret_key}")
          |> load_secret()

        {:noreply, socket}

      :versions ->
        socket =
          socket
          |> assign(:page_title, "Versions: #{socket.assigns.secret_key}")
          |> load_versions()

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("toggle_value", _, socket) do
    current_show_value = Map.get(socket.assigns, :show_value, false)
    {:noreply, assign(socket, :show_value, !current_show_value)}
  end

  @impl true
  def handle_event("load_version", %{"version" => version_str}, socket) do
    case Integer.parse(version_str) do
      {version, ""} ->
        socket = load_secret_version(socket, version)
        {:noreply, socket}

      _ ->
        {:noreply, put_flash(socket, :error, "Invalid version number")}
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

  defp load_secret(socket) do
    case Secrets.get_secret(socket.assigns.secret_key, socket.assigns.current_user) do
      {:ok, secret} ->
        socket
        |> assign(:secret, secret)
        |> assign(:loading, false)
        |> assign(:show_value, false)

      {:error, :not_found} ->
        socket
        |> assign(:error, "Secret not found")
        |> assign(:loading, false)

      {:error, :unauthorized} ->
        socket
        |> assign(:error, "You don't have permission to view this secret")
        |> assign(:loading, false)

      {:error, reason} ->
        socket
        |> assign(:error, "Error loading secret: #{inspect(reason)}")
        |> assign(:loading, false)
    end
  end

  defp load_versions(socket) do
    case Secrets.get_secret_versions(socket.assigns.secret_key, socket.assigns.current_user) do
      {:ok, versions} ->
        socket
        |> assign(:versions, versions)
        |> assign(:loading, false)

      {:error, :not_found} ->
        socket
        |> assign(:error, "Secret not found")
        |> assign(:loading, false)

      {:error, :unauthorized} ->
        socket
        |> assign(:error, "You don't have permission to view this secret")
        |> assign(:loading, false)
    end
  end

  defp load_secret_version(socket, version) do
    case Secrets.get_secret(socket.assigns.secret_key, socket.assigns.current_user, version) do
      {:ok, secret} ->
        socket
        |> assign(:secret, secret)
        |> assign(:show_value, false)
        |> put_flash(:info, "Loaded version #{version}")

      {:error, :not_found} ->
        put_flash(socket, :error, "Version #{version} not found")

      {:error, :unauthorized} ->
        put_flash(socket, :error, "You don't have permission to view this version")

      {:error, reason} ->
        put_flash(socket, :error, "Error loading version: #{inspect(reason)}")
    end
  end

  defp format_date(datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S")
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

  defp get_owner_info(secret, current_user) do
    case secret.secret_type do
      "personal" ->
        if secret.owner_id == current_user.id do
          {"You (Personal Secret)", "text-blue-600"}
        else
          # This shouldn't happen due to access control, but just in case
          {"Unknown User", "text-gray-600"}
        end

      "role_based" ->
        {"Shared via Roles", "text-green-600"}

      _ ->
        {"Unknown", "text-gray-600"}
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
      <main class="max-w-4xl mx-auto py-6 px-4 sm:px-6 lg:px-8">
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
        
    <!-- Loading State -->
        <div :if={@loading} class="text-center py-12">
          <div class="inline-flex items-center px-4 py-2 font-semibold leading-6 text-sm shadow rounded-md text-gray-500 bg-white">
            <svg
              class="animate-spin -ml-1 mr-3 h-5 w-5 text-gray-500"
              xmlns="http://www.w3.org/2000/svg"
              fill="none"
              viewBox="0 0 24 24"
            >
              <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4">
              </circle>
              <path
                class="opacity-75"
                fill="currentColor"
                d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
              >
              </path>
            </svg>
            Loading...
          </div>
        </div>
        
    <!-- Error State -->
        <div :if={@error && !@loading} class="text-center py-12">
          <.icon name="hero-exclamation-triangle" class="mx-auto h-12 w-12 text-red-400" />
          <h3 class="mt-2 text-sm font-medium text-gray-900">Error</h3>
          <p class="mt-1 text-sm text-gray-500">{@error}</p>
          <div class="mt-6">
            <.link
              navigate="/dashboard"
              class="inline-flex items-center px-4 py-2 border border-transparent shadow-sm text-sm font-medium rounded-md text-white bg-indigo-600 hover:bg-indigo-700"
            >
              Back to Dashboard
            </.link>
          </div>
        </div>
        
    <!-- Secret Detail View -->
        <div :if={@live_action == :show && @secret && !@loading && !@error}>
          <div class="bg-white shadow overflow-hidden sm:rounded-lg">
            <div class="px-4 py-5 sm:px-6 border-b border-gray-200">
              <div class="flex items-center justify-between">
                <div>
                  <div class="flex items-center space-x-3">
                    <h3 class="text-lg leading-6 font-medium text-gray-900">Secret Details</h3>
                    <% {badge_text, badge_class} = secret_type_badge(@secret.secret_type) %>
                    <span class={"inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium #{badge_class}"}>
                      {badge_text}
                    </span>
                    <%= if @secret.secret_type == "personal" do %>
                      <.icon name="hero-user" class="h-5 w-5 text-blue-500" />
                    <% else %>
                      <.icon name="hero-key" class="h-5 w-5 text-green-500" />
                    <% end %>
                  </div>
                  <p class="mt-1 max-w-2xl text-sm text-gray-500">
                    Key: {@secret.key}
                  </p>
                </div>
                <div class="flex space-x-3">
                  <.link
                    navigate={"/secrets/#{@secret.key}/edit"}
                    class="inline-flex items-center px-3 py-2 border border-gray-300 shadow-sm text-sm leading-4 font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50"
                    title="Edit secret"
                  >
                    <.icon name="hero-pencil" class="h-4 w-4" />
                  </.link>
                  <.link
                    navigate={"/secrets/#{@secret.key}/versions"}
                    class="inline-flex items-center px-3 py-2 border border-gray-300 shadow-sm text-sm leading-4 font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50"
                    title="View versions"
                  >
                    <.icon name="hero-clock" class="h-4 w-4" />
                  </.link>
                </div>
              </div>
            </div>

            <dl class="divide-y divide-gray-200">
              <div class="px-4 py-5 sm:grid sm:grid-cols-3 sm:gap-4 sm:px-6">
                <dt class="text-sm font-medium text-gray-500">Type</dt>
                <dd class="mt-1 text-sm text-gray-900 sm:mt-0 sm:col-span-2">
                  <% {owner_text, owner_class} = get_owner_info(@secret, @current_user) %>
                  <span class={"text-sm #{owner_class}"}>
                    {owner_text}
                  </span>
                  <%= if @secret.secret_type == "personal" do %>
                    <p class="text-xs text-gray-500 mt-1">
                      This secret is private to you and not shared with other users
                    </p>
                  <% else %>
                    <p class="text-xs text-gray-500 mt-1">
                      This secret's access is controlled by role-based permissions
                    </p>
                  <% end %>
                </dd>
              </div>

              <div class="px-4 py-5 sm:grid sm:grid-cols-3 sm:gap-4 sm:px-6">
                <dt class="text-sm font-medium text-gray-500">Version</dt>
                <dd class="mt-1 text-sm text-gray-900 sm:mt-0 sm:col-span-2">
                  <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-blue-100 text-blue-800">
                    v{@secret.version}
                  </span>
                </dd>
              </div>

              <div class="px-4 py-5 sm:grid sm:grid-cols-3 sm:gap-4 sm:px-6">
                <dt class="text-sm font-medium text-gray-500">Secret Value</dt>
                <dd class="mt-1 text-sm text-gray-900 sm:mt-0 sm:col-span-2">
                  <div class="flex items-center space-x-3">
                    <div class="flex-1">
                      <%= if @show_value do %>
                        <div class="font-mono p-3 bg-gray-100 rounded border text-sm break-all">
                          {@secret.value}
                        </div>
                      <% else %>
                        <div class="font-mono p-3 bg-gray-100 rounded border text-sm">
                          ••••••••••••••••••••
                        </div>
                      <% end %>
                    </div>
                    <button
                      phx-click="toggle_value"
                      class="inline-flex items-center px-3 py-2 border border-gray-300 shadow-sm text-sm leading-4 font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50"
                    >
                      <.icon
                        name={if(@show_value, do: "hero-eye-slash", else: "hero-eye")}
                        class="h-4 w-4"
                      />
                    </button>
                  </div>
                </dd>
              </div>

              <div class="px-4 py-5 sm:grid sm:grid-cols-3 sm:gap-4 sm:px-6">
                <dt class="text-sm font-medium text-gray-500">Created</dt>
                <dd class="mt-1 text-sm text-gray-900 sm:mt-0 sm:col-span-2">
                  {format_date(@secret.inserted_at)}
                </dd>
              </div>

              <div class="px-4 py-5 sm:grid sm:grid-cols-3 sm:gap-4 sm:px-6">
                <dt class="text-sm font-medium text-gray-500">Last Updated</dt>
                <dd class="mt-1 text-sm text-gray-900 sm:mt-0 sm:col-span-2">
                  {format_date(@secret.updated_at)}
                </dd>
              </div>

              <div
                :if={@secret.metadata && map_size(@secret.metadata) > 0}
                class="px-4 py-5 sm:grid sm:grid-cols-3 sm:gap-4 sm:px-6"
              >
                <dt class="text-sm font-medium text-gray-500">Metadata</dt>
                <dd class="mt-1 text-sm text-gray-900 sm:mt-0 sm:col-span-2">
                  <div class="space-y-2">
                    <%= for {key, value} <- @secret.metadata do %>
                      <div class="flex">
                        <span class="font-medium text-gray-700 mr-2">{key}:</span>
                        <span class="text-gray-900">{value}</span>
                      </div>
                    <% end %>
                  </div>
                </dd>
              </div>
            </dl>
          </div>
        </div>
        
    <!-- Versions View -->
        <div :if={@live_action == :versions && !@loading && !@error}>
          <div class="bg-white shadow overflow-hidden sm:rounded-lg">
            <div class="px-4 py-5 sm:px-6 border-b border-gray-200">
              <div class="flex items-center justify-between">
                <div>
                  <h3 class="text-lg leading-6 font-medium text-gray-900">Version History</h3>
                  <p class="mt-1 max-w-2xl text-sm text-gray-500">
                    Key: {@secret_key}
                  </p>
                </div>
                <.link
                  navigate={"/secrets/#{@secret_key}"}
                  class="inline-flex items-center px-3 py-2 border border-gray-300 shadow-sm text-sm leading-4 font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50"
                  title="Back to details"
                >
                  <.icon name="hero-arrow-left" class="h-4 w-4" />
                </.link>
              </div>
            </div>

            <div class="divide-y divide-gray-200">
              <%= for version <- @versions do %>
                <div class="px-4 py-4">
                  <div class="flex items-center justify-between">
                    <div class="flex items-center">
                      <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-blue-100 text-blue-800">
                        v{version.version}
                      </span>
                      <%= if version.secret_type do %>
                        <% {badge_text, badge_class} = secret_type_badge(version.secret_type) %>
                        <span class={"ml-2 inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium #{badge_class}"}>
                          {badge_text}
                        </span>
                      <% end %>
                      <div class="ml-4">
                        <p class="text-sm text-gray-500">
                          Created: {format_date(version.created_at)}
                        </p>
                        <p class="text-sm text-gray-500">
                          Updated: {format_date(version.updated_at)}
                        </p>
                      </div>
                    </div>
                    <button
                      phx-click="load_version"
                      phx-value-version={version.version}
                      class="inline-flex items-center px-3 py-2 border border-gray-300 shadow-sm text-sm leading-4 font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50"
                      title="View version {version.version}"
                    >
                      <.icon name="hero-eye" class="h-4 w-4" />
                    </button>
                  </div>
                  <div :if={version.metadata && map_size(version.metadata) > 0} class="mt-2">
                    <p class="text-xs text-gray-500">
                      Metadata: {Enum.map_join(version.metadata, ", ", fn {k, v} -> "#{k}: #{v}" end)}
                    </p>
                  </div>
                </div>
              <% end %>
            </div>
          </div>
          
    <!-- Selected Version Display -->
          <div :if={@secret} class="mt-6 bg-white shadow overflow-hidden sm:rounded-lg">
            <div class="px-4 py-5 sm:px-6 border-b border-gray-200">
              <div class="flex items-center space-x-3">
                <h3 class="text-lg leading-6 font-medium text-gray-900">
                  Version {[@secret.version]} Details
                </h3>
                <%= if @secret.secret_type do %>
                  <% {badge_text, badge_class} = secret_type_badge(@secret.secret_type) %>
                  <span class={"inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium #{badge_class}"}>
                    {badge_text}
                  </span>
                <% end %>
              </div>
            </div>
            <dl class="divide-y divide-gray-200">
              <div class="px-4 py-5 sm:grid sm:grid-cols-3 sm:gap-4 sm:px-6">
                <dt class="text-sm font-medium text-gray-500">Secret Value</dt>
                <dd class="mt-1 text-sm text-gray-900 sm:mt-0 sm:col-span-2">
                  <div class="flex items-center space-x-3">
                    <div class="flex-1">
                      <%= if @show_value do %>
                        <div class="font-mono p-3 bg-gray-100 rounded border text-sm break-all">
                          {@secret.value}
                        </div>
                      <% else %>
                        <div class="font-mono p-3 bg-gray-100 rounded border text-sm">
                          ••••••••••••••••••••
                        </div>
                      <% end %>
                    </div>
                    <button
                      phx-click="toggle_value"
                      class="inline-flex items-center px-3 py-2 border border-gray-300 shadow-sm text-sm leading-4 font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50"
                    >
                      <.icon
                        name={if(@show_value, do: "hero-eye-slash", else: "hero-eye")}
                        class="h-4 w-4"
                      />
                    </button>
                  </div>
                </dd>
              </div>
            </dl>
          </div>
        </div>
      </main>
    </div>
    """
  end
end
