defmodule VaultLiteWeb.SecretsLive.SecretFormLive do
  @moduledoc """
  This module is responsible for the secret form live view.
  - displays the secret form and allows the user to create, update, and delete them.
  - displays the secret details and allows the user to view the secret.
  - displays the secret creation form and allows the user to create new secrets.
  - displays the secret update form and allows the user to update existing secrets.
  """
  use VaultLiteWeb, :live_view

  alias VaultLite.{Secrets, User}

  @impl true
  def mount(params, session, socket) do
    current_user = get_current_user(session)
    secret_key = Map.get(params, "key")

    {action, secret, page_title} =
      case secret_key do
        nil ->
          {:new, nil, "Create Secret"}

        key ->
          case Secrets.get_secret(key, current_user) do
            {:ok, secret} -> {:edit, secret, "Edit Secret: #{key}"}
            {:error, _} -> {:new, nil, "Create Secret"}
          end
      end

    socket =
      socket
      |> assign(:current_user, current_user)
      |> assign(:action, action)
      |> assign(:secret, secret)
      |> assign(:page_title, page_title)
      |> assign(
        :form,
        to_form(%{"key" => "", "value" => "", "metadata" => "", "secret_type" => "role_based"},
          as: :secret
        )
      )
      |> assign(:errors, %{})
      |> assign(:loading, false)
      |> assign(:metadata_pairs, [%{key: "", value: ""}])
      |> assign(:selected_secret_type, "role_based")

    # If editing, populate form with existing data
    socket =
      if action == :edit and secret do
        metadata_json = Jason.encode!(secret.metadata || %{}, pretty: true)

        metadata_pairs =
          case secret.metadata do
            nil ->
              [%{key: "", value: ""}]

            metadata when metadata == %{} ->
              [%{key: "", value: ""}]

            metadata ->
              Enum.map(metadata, fn {k, v} -> %{key: k, value: v} end) ++ [%{key: "", value: ""}]
          end

        socket
        |> assign(
          :form,
          to_form(
            %{
              "key" => secret.key,
              # Don't pre-populate for security
              "value" => "",
              "metadata" => metadata_json,
              "secret_type" => secret.secret_type
            },
            as: :secret
          )
        )
        |> assign(:metadata_pairs, metadata_pairs)
        |> assign(:selected_secret_type, secret.secret_type)
      else
        socket
      end

    {:ok, socket}
  end

  @impl true
  def handle_event("validate", %{"secret" => secret_params}, socket) do
    errors = validate_secret_form(secret_params, socket.assigns.action)

    # Update selected secret type from the form params
    selected_secret_type = Map.get(secret_params, "secret_type", "role_based")

    socket =
      socket
      |> assign(:form, to_form(secret_params, as: :secret))
      |> assign(:errors, errors)
      |> assign(:selected_secret_type, selected_secret_type)

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_secret_type", %{"secret_type" => secret_type}, socket) do
    current_form_data = Phoenix.HTML.Form.input_value(socket.assigns.form, :secret) || %{}
    updated_form_data = Map.put(current_form_data, "secret_type", secret_type)

    socket =
      socket
      |> assign(:form, to_form(updated_form_data, as: :secret))
      |> assign(:selected_secret_type, secret_type)

    {:noreply, socket}
  end

  @impl true
  def handle_event("add_metadata_pair", _, socket) do
    metadata_pairs = socket.assigns.metadata_pairs ++ [%{key: "", value: ""}]

    socket = assign(socket, :metadata_pairs, metadata_pairs)
    {:noreply, socket}
  end

  @impl true
  def handle_event("remove_metadata_pair", %{"index" => index}, socket) do
    index = String.to_integer(index)
    metadata_pairs = List.delete_at(socket.assigns.metadata_pairs, index)

    socket = assign(socket, :metadata_pairs, metadata_pairs)
    {:noreply, socket}
  end

  @impl true
  def handle_event("update_metadata_pair", params, socket) do
    # Extract field information from _target or from phx-value attributes
    {index, field, value} =
      case params do
        # If phx-value attributes are present
        %{"index" => index_str, "field" => field} = p ->
          index = String.to_integer(index_str)
          field_name = "metadata_#{field}_#{index}"
          value = Map.get(p, field_name, "")
          {index, field, value}

        # Fallback: extract from _target field name
        %{"_target" => [field_name]} = p ->
          case Regex.run(~r/metadata_(\w+)_(\d+)/, field_name) do
            [_full, field, index_str] ->
              index = String.to_integer(index_str)
              value = Map.get(p, field_name, "")
              {index, field, value}

            _ ->
              {0, "key", ""}
          end

        # Default case
        _ ->
          {0, "key", ""}
      end

    metadata_pairs = socket.assigns.metadata_pairs

    # Ensure index is within bounds
    socket =
      if index < length(metadata_pairs) do
        updated_pairs =
          List.update_at(metadata_pairs, index, fn pair ->
            Map.put(pair, String.to_atom(field), value)
          end)

        assign(socket, :metadata_pairs, updated_pairs)
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("submit", %{"secret" => secret_params}, socket) do
    socket = assign(socket, :loading, true)

    # Build metadata from pairs
    metadata =
      socket.assigns.metadata_pairs
      |> Enum.reject(fn %{key: k, value: v} -> k == "" or v == "" end)
      |> Enum.reduce(%{}, fn %{key: k, value: v}, acc -> Map.put(acc, k, v) end)

    # Get secret type from form, default to role_based
    secret_type = Map.get(secret_params, "secret_type", "role_based")

    params = Map.put(secret_params, "metadata", metadata)

    result =
      case socket.assigns.action do
        :new ->
          Secrets.create_secret(
            params["key"],
            params["value"],
            socket.assigns.current_user,
            metadata,
            secret_type
          )

        :edit ->
          Secrets.update_secret(
            socket.assigns.secret.key,
            params["value"],
            socket.assigns.current_user,
            metadata
          )
      end

    case result do
      {:ok, _secret} ->
        action_text = if socket.assigns.action == :new, do: "created", else: "updated"

        socket =
          socket
          |> put_flash(:info, "Secret #{action_text} successfully!")
          |> assign(:loading, false)
          |> push_navigate(to: "/dashboard")

        {:noreply, socket}

      {:error, reason} ->
        error_msg =
          case reason do
            :unauthorized ->
              "You don't have permission to perform this action"

            :not_found ->
              "Secret not found"

            %Ecto.Changeset{} = changeset ->
              changeset
              |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
                Enum.reduce(opts, msg, fn {key, value}, acc ->
                  String.replace(acc, "%{#{key}}", to_string(value))
                end)
              end)
              |> Map.values()
              |> List.flatten()
              |> Enum.join(", ")

            _ ->
              "An error occurred while saving the secret"
          end

        socket =
          socket
          |> put_flash(:error, error_msg)
          |> assign(:loading, false)

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

  defp validate_secret_form(%{"key" => key, "value" => value}, action) do
    errors = %{}

    # Key validation (only for new secrets)
    errors =
      if action == :new do
        cond do
          String.trim(key) == "" ->
            Map.put(errors, :key, "Secret key is required")

          String.length(key) < 2 ->
            Map.put(errors, :key, "Secret key must be at least 2 characters")

          String.length(key) > 100 ->
            Map.put(errors, :key, "Secret key must be less than 100 characters")

          not Regex.match?(~r/^[a-zA-Z0-9\/_-]+$/, key) ->
            Map.put(
              errors,
              :key,
              "Secret key can only contain letters, numbers, hyphens, underscores, and forward slashes"
            )

          true ->
            errors
        end
      else
        errors
      end

    # Value validation
    errors =
      cond do
        String.trim(value) == "" ->
          Map.put(errors, :value, "Secret value is required")

        String.length(value) > 10_000 ->
          Map.put(errors, :value, "Secret value must be less than 10,000 characters")

        true ->
          errors
      end

    errors
  end

  defp validate_secret_form(_, _), do: %{}

  defp form_valid?(errors), do: Enum.empty?(errors)

  @impl true
  def render(assigns) do
    ~H"""
    <div class="h-full bg-gray-50">
      <!-- Navigation Header -->
      <nav class="bg-white shadow-sm border-b">
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div class="flex justify-between h-16">
            <div class="flex items-center">
              <.link navigate="/dashboard" class="flex items-center">
                <.icon name="hero-lock-closed" class="h-8 w-8 text-indigo-600" />
                <span class="ml-2 text-xl font-bold text-gray-900">VaultLite</span>
              </.link>
            </div>

            <div class="flex items-center space-x-4">
              <span class="text-sm text-gray-700">Welcome, {@current_user.username}!</span>

              <.link
                navigate="/dashboard"
                class="text-gray-500 hover:text-gray-700 px-3 py-2 rounded-md text-sm font-medium"
              >
                Back to Dashboard
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
      <main class="max-w-2xl mx-auto py-6 px-4 sm:px-6 lg:px-8">
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
        
    <!-- Form -->
        <div class="bg-white shadow rounded-lg">
          <div class="px-6 py-4 border-b border-gray-200">
            <h1 class="text-lg font-medium text-gray-900">{@page_title}</h1>
          </div>

          <.form for={@form} phx-submit="submit" phx-change="validate" class="px-6 py-4 space-y-6">
            <!-- Secret Type Toggle (only for new secrets) -->
            <%= if @action == :new do %>
              <div>
                <label class="block text-sm font-medium text-gray-700 mb-3">Secret Type</label>
                <div class="flex items-center space-x-6">
                  <label class="flex items-center">
                    <input
                      type="radio"
                      name="secret[secret_type]"
                      value="role_based"
                      checked={@selected_secret_type == "role_based"}
                      phx-click="toggle_secret_type"
                      phx-value-secret_type="role_based"
                      class="h-4 w-4 text-indigo-600 focus:ring-indigo-500 border-gray-300"
                    />
                    <span class="ml-2 text-sm text-gray-900">Role-based Secret</span>
                  </label>
                  <label class="flex items-center">
                    <input
                      type="radio"
                      name="secret[secret_type]"
                      value="personal"
                      checked={@selected_secret_type == "personal"}
                      phx-click="toggle_secret_type"
                      phx-value-secret_type="personal"
                      class="h-4 w-4 text-indigo-600 focus:ring-indigo-500 border-gray-300"
                    />
                    <span class="ml-2 text-sm text-gray-900">Personal Secret</span>
                  </label>
                </div>
                <p class="mt-2 text-sm text-gray-500">
                  <%= if @selected_secret_type == "personal" do %>
                    Personal secrets are only accessible by you and won't be shared based on roles.
                  <% else %>
                    Role-based secrets are accessible based on your assigned roles and permissions.
                  <% end %>
                </p>
              </div>
            <% else %>
              <div>
                <label class="block text-sm font-medium text-gray-700">Secret Type</label>
                <div class="mt-1 px-3 py-2 bg-gray-50 border border-gray-300 rounded-md sm:text-sm text-gray-900 flex items-center">
                  <span class="capitalize">{String.replace(@secret.secret_type, "_", " ")}</span>
                  <%= if @secret.secret_type == "personal" do %>
                    <span class="ml-2 inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-blue-100 text-blue-800">
                      Personal
                    </span>
                  <% else %>
                    <span class="ml-2 inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800">
                      Role-based
                    </span>
                  <% end %>
                </div>
                <p class="mt-1 text-sm text-gray-500">
                  Secret type cannot be changed when editing
                </p>
              </div>
            <% end %>
            
    <!-- Secret Key (only for new secrets) -->
            <%= if @action == :new do %>
              <div>
                <label for="key" class="block text-sm font-medium text-gray-700">Secret Key</label>
                <.input
                  field={@form[:key]}
                  type="text"
                  placeholder="e.g., api/database/password or prod/jwt-secret"
                  class={[
                    "mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm",
                    if(@errors[:key], do: "border-red-300 focus:border-red-500 focus:ring-red-500")
                  ]}
                  phx-debounce="300"
                />
                <p :if={@errors[:key]} class="mt-1 text-sm text-red-600">
                  {@errors[:key]}
                </p>
                <p class="mt-1 text-sm text-gray-500">
                  <%= if @selected_secret_type == "personal" do %>
                    Choose a descriptive name for your personal secret (e.g., my-password, personal-api-key)
                  <% else %>
                    Use forward slashes to organize secrets hierarchically (e.g., app/env/key)
                  <% end %>
                </p>
              </div>
            <% else %>
              <div>
                <label class="block text-sm font-medium text-gray-700">Secret Key</label>
                <div class="mt-1 px-3 py-2 bg-gray-50 border border-gray-300 rounded-md sm:text-sm text-gray-900">
                  {@secret.key}
                </div>
                <p class="mt-1 text-sm text-gray-500">
                  Secret key cannot be changed when editing
                </p>
              </div>
            <% end %>
            
    <!-- Secret Value -->
            <div>
              <label for="value" class="block text-sm font-medium text-gray-700">Secret Value</label>
              <.input
                field={@form[:value]}
                type="textarea"
                rows="4"
                placeholder="Enter the secret value..."
                class={[
                  "mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm",
                  if(@errors[:value], do: "border-red-300 focus:border-red-500 focus:ring-red-500")
                ]}
                phx-debounce="300"
              />
              <p :if={@errors[:value]} class="mt-1 text-sm text-red-600">
                {@errors[:value]}
              </p>
              <p class="mt-1 text-sm text-gray-500">
                The secret value will be encrypted before storage
              </p>
            </div>
            
    <!-- Metadata -->
            <div>
              <div class="flex items-center justify-between">
                <label class="block text-sm font-medium text-gray-700">Metadata (Optional)</label>
                <button
                  type="button"
                  phx-click="add_metadata_pair"
                  class="inline-flex items-center px-3 py-1 border border-transparent text-sm font-medium rounded-md text-indigo-700 bg-indigo-100 hover:bg-indigo-200"
                >
                  <.icon name="hero-plus" class="h-4 w-4 mr-1" /> Add Field
                </button>
              </div>

              <div class="mt-2 space-y-2">
                <%= for {pair, index} <- Enum.with_index(@metadata_pairs) do %>
                  <div class="flex items-center space-x-2">
                    <.input
                      name={"metadata_key_#{index}"}
                      type="text"
                      value={pair.key}
                      placeholder="Key"
                      class="flex-1 rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm"
                      phx-change="update_metadata_pair"
                      phx-value-index={index}
                      phx-value-field="key"
                    />
                    <.input
                      name={"metadata_value_#{index}"}
                      type="text"
                      value={pair.value}
                      placeholder="Value"
                      class="flex-1 rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm"
                      phx-change="update_metadata_pair"
                      phx-value-index={index}
                      phx-value-field="value"
                    />
                    <%= if length(@metadata_pairs) > 1 do %>
                      <button
                        type="button"
                        phx-click="remove_metadata_pair"
                        phx-value-index={index}
                        class="inline-flex items-center px-2 py-1 border border-gray-300 rounded-md text-sm font-medium text-gray-700 bg-white hover:bg-gray-50"
                      >
                        <.icon name="hero-x-mark" class="h-4 w-4" />
                      </button>
                    <% end %>
                  </div>
                <% end %>
              </div>
              <p class="mt-1 text-sm text-gray-500">
                Add key-value pairs for additional secret information (e.g., environment, owner, etc.)
              </p>
            </div>
            
    <!-- Submit Button -->
            <div class="flex justify-end space-x-3 pt-4 border-t border-gray-200">
              <.link
                navigate="/dashboard"
                class="px-4 py-2 border border-gray-300 rounded-md shadow-sm text-sm font-medium text-gray-700 bg-white hover:bg-gray-50"
              >
                Cancel
              </.link>

              <button
                type="submit"
                disabled={not form_valid?(@errors) or @loading}
                class={[
                  "px-4 py-2 border border-transparent rounded-md shadow-sm text-sm font-medium text-white focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500",
                  if(form_valid?(@errors) and not @loading,
                    do: "bg-indigo-600 hover:bg-indigo-700",
                    else: "bg-gray-400 cursor-not-allowed"
                  )
                ]}
              >
                <%= if @loading do %>
                  <div class="flex items-center">
                    <svg
                      class="animate-spin -ml-1 mr-2 h-4 w-4 text-white"
                      xmlns="http://www.w3.org/2000/svg"
                      fill="none"
                      viewBox="0 0 24 24"
                    >
                      <circle
                        class="opacity-25"
                        cx="12"
                        cy="12"
                        r="10"
                        stroke="currentColor"
                        stroke-width="4"
                      >
                      </circle>
                      <path
                        class="opacity-75"
                        fill="currentColor"
                        d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
                      >
                      </path>
                    </svg>
                    {if @action == :new, do: "Creating...", else: "Updating..."}
                  </div>
                <% else %>
                  {if @action == :new, do: "Create Secret", else: "Update Secret"}
                <% end %>
              </button>
            </div>
          </.form>
        </div>
      </main>
    </div>
    """
  end
end
