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
  def handle_event("copy_secret_value", _, socket) do
    # JavaScript handles the actual copying, this just provides user feedback
    socket = put_flash(socket, :info, "Secret value copied to clipboard!")
    {:noreply, socket}
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

  defp secret_type_badge(secret) do
    cond do
      # Handle string secret type (for version history)
      is_binary(secret) ->
        case secret do
          "personal" ->
            {"Personal", "bg-blue-100 text-blue-800"}

          "role_based" ->
            {"Role-based", "bg-green-100 text-green-800"}

          _ ->
            {"Unknown", "bg-gray-100 text-gray-800"}
        end

      # Handle full secret map - check for shared secrets first
      is_map(secret) && Map.get(secret, :is_shared, false) ->
        permission = Map.get(secret, :permission_level, "read_only")

        if permission == "editable" do
          {"Shared (Editable)", "bg-purple-100 text-purple-800"}
        else
          {"Shared (Read-only)", "bg-purple-100 text-purple-800"}
        end

      # Handle full secret map - personal secrets
      is_map(secret) && secret.secret_type == "personal" ->
        {"Personal", "bg-blue-100 text-blue-800"}

      # Handle full secret map - role-based secrets
      is_map(secret) && secret.secret_type == "role_based" ->
        {"Role-based", "bg-green-100 text-green-800"}

      # Default case
      true ->
        {"Unknown", "bg-gray-100 text-gray-800"}
    end
  end

  defp get_owner_info(secret, current_user) do
    cond do
      # Check if this is a shared secret
      Map.get(secret, :is_shared, false) ->
        shared_by = Map.get(secret, :shared_by, "Unknown User")
        permission = Map.get(secret, :permission_level, "read_only")
        permission_text = String.replace(permission, "_", " ") |> String.capitalize()
        {"Shared by #{shared_by} (#{permission_text})", "text-purple-600"}

      # Personal secret owned by current user
      secret.secret_type == "personal" && secret.owner_id == current_user.id ->
        {"You (Personal Secret)", "text-blue-600"}

      # Personal secret owned by someone else (shouldn't happen with proper access control)
      secret.secret_type == "personal" ->
        {"Personal Secret (Not Owned)", "text-gray-600"}

      # Role-based secret
      secret.secret_type == "role_based" ->
        {"Shared via Roles", "text-green-600"}

      # Default case
      true ->
        {"Unknown", "text-gray-600"}
    end
  end

  defp can_edit_secret?(secret, current_user) do
    cond do
      # Shared secret - check permission level
      Map.get(secret, :is_shared, false) ->
        Map.get(secret, :permission_level) == "editable"

      # Personal secret - must be owner
      secret.secret_type == "personal" ->
        secret.owner_id == current_user.id

      # Role-based secret - use existing role authorization (simplified for now)
      secret.secret_type == "role_based" ->
        true

      # Default case
      true ->
        false
    end
  end

  defp get_secret_description(secret) do
    cond do
      Map.get(secret, :is_shared, false) ->
        shared_by = Map.get(secret, :shared_by, "Unknown User")
        permission = Map.get(secret, :permission_level, "read_only")
        permission_text = String.replace(permission, "_", " ") |> String.downcase()

        if permission == "editable" do
          "This secret was shared with you by #{shared_by} with #{permission_text} permissions. You can view and modify it."
        else
          "This secret was shared with you by #{shared_by} with #{permission_text} permissions. You can only view it."
        end

      secret.secret_type == "personal" ->
        "This secret is private to you and not shared with other users"

      secret.secret_type == "role_based" ->
        "This secret's access is controlled by role-based permissions"

      true ->
        "Unknown secret type"
    end
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
          
    <!-- Loading State -->
          <div :if={@loading} class="flex justify-center py-12">
            <span class="loading loading-spinner loading-md"></span>
            <span class="ml-2">Loading...</span>
          </div>
          
    <!-- Error State -->
          <div :if={@error && !@loading} class="text-center py-12">
            <.icon name="hero-exclamation-triangle" class="mx-auto h-12 w-12" />
            <h3 class="mt-2 text-sm font-medium">Error</h3>
            <p class="mt-1 text-sm opacity-70">{@error}</p>
            <div class="mt-6">
              <.link navigate="/dashboard" class="btn btn-primary">
                Back to Dashboard
              </.link>
            </div>
          </div>
          
    <!-- Secret Detail View -->
          <div :if={@live_action == :show && @secret && !@loading && !@error}>
            <div class="card bg-base-100">
              <div class="card-body">
                <div class="flex items-center justify-between mb-4">
                  <div>
                    <div class="flex items-center gap-3">
                      <h2 class="card-title">Secret Details</h2>
                      <% {badge_text, _badge_class} = secret_type_badge(@secret) %>
                      <div class="badge badge-outline">{badge_text}</div>
                      <%= cond do %>
                        <% Map.get(@secret, :is_shared, false) -> %>
                          <.icon name="hero-share" class="h-5 w-5" />
                        <% @secret.secret_type == "personal" -> %>
                          <.icon name="hero-user" class="h-5 w-5" />
                        <% true -> %>
                          <.icon name="hero-key" class="h-5 w-5" />
                      <% end %>
                    </div>
                    <p class="opacity-70">Key: {@secret.key}</p>
                  </div>
                  <div class="flex gap-2">
                    <%= if can_edit_secret?(@secret, @current_user) do %>
                      <.link
                        navigate={"/secrets/#{@secret.key}/edit"}
                        class="btn btn-ghost btn-sm"
                        title="Edit secret"
                      >
                        <.icon name="hero-pencil" class="h-4 w-4" />
                      </.link>
                    <% end %>
                    <.link
                      navigate={"/secrets/#{@secret.key}/versions"}
                      class="btn btn-ghost btn-sm"
                      title="View versions"
                    >
                      <.icon name="hero-clock" class="h-4 w-4" />
                    </.link>
                  </div>
                </div>

                <div class="">
                  <table class="table">
                    <tbody>
                      <tr>
                        <td class="font-medium">Type</td>
                        <td>
                          <% {owner_text, _owner_class} = get_owner_info(@secret, @current_user) %>
                          <span>{owner_text}</span>
                          <p class="text-xs opacity-70 mt-1">
                            {get_secret_description(@secret)}
                          </p>
                        </td>
                      </tr>

                      <tr>
                        <td class="font-medium">Version</td>
                        <td>
                          <div class="badge badge-info">v{@secret.version}</div>
                        </td>
                      </tr>

                      <tr>
                        <td class="font-medium">Secret Value</td>
                        <td>
                          <div class="flex items-center gap-3">
                            <div class="flex-1">
                              <%= if @show_value do %>
                                <div class="mockup-code">
                                  <pre><code>{@secret.value}</code></pre>
                                </div>
                              <% else %>
                                <div class="mockup-code">
                                  <pre><code>••••••••••••••••••••</code></pre>
                                </div>
                              <% end %>
                            </div>
                            <div class="flex gap-1">
                              <button
                                phx-click="copy_secret_value"
                                class="btn btn-ghost btn-sm tooltip"
                                data-tip="Copy to clipboard"
                                onclick={"copyToClipboard('#{String.replace(@secret.value, "'", "\\'")}', this)"}
                              >
                                <.icon name="hero-clipboard-document" class="h-4 w-4" />
                              </button>
                              <button
                                phx-click="toggle_value"
                                class="btn btn-ghost btn-sm tooltip"
                                data-tip="Toggle visibility"
                              >
                                <.icon
                                  name={if(@show_value, do: "hero-eye-slash", else: "hero-eye")}
                                  class="h-4 w-4"
                                />
                              </button>
                            </div>
                          </div>
                        </td>
                      </tr>

                      <tr>
                        <td class="font-medium">Created</td>
                        <td>{format_date(@secret.inserted_at)}</td>
                      </tr>

                      <tr>
                        <td class="font-medium">Last Updated</td>
                        <td>{format_date(@secret.updated_at)}</td>
                      </tr>

                      <tr :if={@secret.metadata && map_size(@secret.metadata) > 0}>
                        <td class="font-medium">Metadata</td>
                        <td>
                          <div class="space-y-1">
                            <%= for {key, value} <- @secret.metadata do %>
                              <div class="flex gap-2">
                                <span class="font-medium">{key}:</span>
                                <span>{value}</span>
                              </div>
                            <% end %>
                          </div>
                        </td>
                      </tr>
                    </tbody>
                  </table>
                </div>
              </div>
            </div>
          </div>
          
    <!-- Versions View -->
          <div :if={@live_action == :versions && !@loading && !@error}>
            <div class="card bg-base-100">
              <div class="card-body">
                <div class="flex items-center justify-between mb-4">
                  <div>
                    <h2 class="card-title">Version History</h2>
                    <p class="opacity-70">Key: {@secret_key}</p>
                  </div>
                  <.link
                    navigate={"/secrets/#{@secret_key}"}
                    class="btn btn-ghost btn-sm"
                    title="Back to details"
                  >
                    <.icon name="hero-arrow-left" class="h-4 w-4" />
                  </.link>
                </div>

                <div class="space-y-4">
                  <%= for version <- @versions do %>
                    <div class="card bg-base-200">
                      <div class="card-body p-4">
                        <div class="flex items-center justify-between">
                          <div class="flex items-center gap-3">
                            <div class="badge badge-info">v{version.version}</div>
                            <%= if version.secret_type do %>
                              <% {badge_text, _badge_class} = secret_type_badge(version.secret_type) %>
                              <div class="badge badge-outline">{badge_text}</div>
                            <% end %>
                            <div>
                              <p class="text-sm opacity-70">
                                Created: {format_date(version.created_at)}
                              </p>
                              <p class="text-sm opacity-70">
                                Updated: {format_date(version.updated_at)}
                              </p>
                            </div>
                          </div>
                          <button
                            phx-click="load_version"
                            phx-value-version={version.version}
                            class="btn btn-ghost btn-sm"
                            title="View version {version.version}"
                          >
                            <.icon name="hero-eye" class="h-4 w-4" />
                          </button>
                        </div>
                        <div :if={version.metadata && map_size(version.metadata) > 0} class="mt-2">
                          <p class="text-xs opacity-70">
                            Metadata: {Enum.map_join(version.metadata, ", ", fn {k, v} ->
                              "#{k}: #{v}"
                            end)}
                          </p>
                        </div>
                      </div>
                    </div>
                  <% end %>
                </div>
              </div>
            </div>
            
    <!-- Selected Version Display -->
            <div :if={@secret} class="card bg-base-100 mt-6">
              <div class="card-body">
                <div class="flex items-center gap-3 mb-4">
                  <h3 class="text-lg font-medium">Version {[@secret.version]} Details</h3>
                  <%= if @secret.secret_type do %>
                    <% {badge_text, _badge_class} = secret_type_badge(@secret) %>
                    <div class="badge badge-outline">{badge_text}</div>
                  <% end %>
                </div>

                <div class="overflow-x-auto">
                  <table class="table">
                    <tbody>
                      <tr>
                        <td class="font-medium">Secret Value</td>
                        <td>
                          <div class="flex items-center gap-3">
                            <div class="flex-1">
                              <%= if @show_value do %>
                                <div class="mockup-code">
                                  <pre><code>{@secret.value}</code></pre>
                                </div>
                              <% else %>
                                <div class="mockup-code">
                                  <pre><code>••••••••••••••••••••</code></pre>
                                </div>
                              <% end %>
                            </div>
                            <div class="flex gap-1">
                              <button
                                phx-click="copy_secret_value"
                                class="btn btn-ghost btn-sm tooltip"
                                data-tip="Copy to clipboard"
                                onclick={"copyToClipboard('#{String.replace(@secret.value, "'", "\\'")}', this)"}
                              >
                                <.icon name="hero-clipboard-document" class="h-4 w-4" />
                              </button>
                              <button
                                phx-click="toggle_value"
                                class="btn btn-ghost btn-sm tooltip"
                                data-tip="Toggle visibility"
                              >
                                <.icon
                                  name={if(@show_value, do: "hero-eye-slash", else: "hero-eye")}
                                  class="h-4 w-4"
                                />
                              </button>
                            </div>
                          </div>
                        </td>
                      </tr>
                    </tbody>
                  </table>
                </div>
              </div>
            </div>
          </div>
        </main>
      </div>
      
    <!-- JavaScript for clipboard copying -->
      <script>
        window.copyToClipboard = function(text, button) {
          // Use the modern Clipboard API if available
          if (navigator.clipboard && window.isSecureContext) {
            navigator.clipboard.writeText(text).then(function() {
              showCopyFeedback(button, true);
            }, function(err) {
              console.error('Could not copy text: ', err);
              showCopyFeedback(button, false);
            });
          } else {
            // Fallback for older browsers
            const textArea = document.createElement("textarea");
            textArea.value = text;
            textArea.style.position = "fixed";
            textArea.style.left = "-999999px";
            textArea.style.top = "-999999px";
            document.body.appendChild(textArea);
            textArea.focus();
            textArea.select();

            try {
              const successful = document.execCommand('copy');
              showCopyFeedback(button, successful);
            } catch (err) {
              console.error('Could not copy text: ', err);
              showCopyFeedback(button, false);
            }

            document.body.removeChild(textArea);
          }
        };

        function showCopyFeedback(button, success) {
          const originalIcon = button.innerHTML;
          const originalTip = button.getAttribute('data-tip');

          if (success) {
            button.innerHTML = '<svg class="h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"></path></svg>';
            button.setAttribute('data-tip', 'Copied!');
            button.classList.add('btn-success');
          } else {
            button.innerHTML = '<svg class="h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path></svg>';
            button.setAttribute('data-tip', 'Copy failed');
            button.classList.add('btn-error');
          }

          // Reset after 2 seconds
          setTimeout(function() {
            button.innerHTML = originalIcon;
            button.setAttribute('data-tip', originalTip);
            button.classList.remove('btn-success', 'btn-error');
          }, 2000);
        }
      </script>
    </VaultLiteWeb.Layouts.app>
    """
  end
end
