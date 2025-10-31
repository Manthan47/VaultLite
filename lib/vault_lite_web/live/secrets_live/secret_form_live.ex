defmodule VaultLiteWeb.SecretsLive.SecretFormLive do
  @moduledoc """
  This module is responsible for the secret form live view.
  - displays the secret form and allows the user to create, update, and delete them.
  - displays the secret details and allows the user to view the secret.
  - displays the secret creation form and allows the user to create new secrets.
  - displays the secret update form and allows the user to update existing secrets.
  """
  use VaultLiteWeb, :live_view

  alias VaultLite.SecretGenerator
  alias VaultLite.Secrets
  alias VaultLite.User

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
      |> assign(:show_generator, false)
      |> assign(:generator_type, :password)
      |> assign(:generator_length, 16)
      |> assign(:generator_include_symbols, true)

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
        |> assign(:show_generator, false)
        |> assign(:generator_type, :password)
        |> assign(:generator_length, 16)
        |> assign(:generator_include_symbols, true)
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
  def handle_event("toggle_generator", _, socket) do
    {:noreply, assign(socket, :show_generator, !socket.assigns.show_generator)}
  end

  @impl true
  def handle_event("update_generator_type", %{"generator_type" => type_str} = _params, socket) do
    generator_type = String.to_atom(type_str)
    current_type = socket.assigns.generator_type
    current_length = socket.assigns.generator_length

    # If type changed and current length is the default for the old type,
    # update to default for new type
    generator_length =
      if generator_type != current_type and
           current_length == SecretGenerator.default_length(current_type) do
        SecretGenerator.default_length(generator_type)
      else
        # Keep current length if valid for new type, otherwise use default
        if SecretGenerator.valid_length?(generator_type, current_length) do
          current_length
        else
          SecretGenerator.default_length(generator_type)
        end
      end

    socket =
      socket
      |> assign(:generator_type, generator_type)
      |> assign(:generator_length, generator_length)

    {:noreply, socket}
  end

  @impl true
  def handle_event(
        "update_generator_length",
        %{"generator_length" => length_str} = _params,
        socket
      ) do
    generator_length =
      case Integer.parse(length_str) do
        {length, ""} ->
          if SecretGenerator.valid_length?(socket.assigns.generator_type, length) do
            length
          else
            socket.assigns.generator_length
          end

        _ ->
          socket.assigns.generator_length
      end

    socket = assign(socket, :generator_length, generator_length)
    {:noreply, socket}
  end

  @impl true
  def handle_event("update_generator_symbols", params, socket) do
    generator_include_symbols = Map.has_key?(params, "generator_include_symbols")
    socket = assign(socket, :generator_include_symbols, generator_include_symbols)
    {:noreply, socket}
  end

  @impl true
  def handle_event("generate_secret", _, socket) do
    opts =
      if socket.assigns.generator_include_symbols,
        do: [include_symbols: true],
        else: [include_symbols: false]

    case SecretGenerator.generate_secret(
           socket.assigns.generator_type,
           socket.assigns.generator_length,
           opts
         ) do
      {:ok, generated_secret} ->
        # Update the form with the generated secret
        current_form_data = Phoenix.HTML.Form.input_value(socket.assigns.form, :secret) || %{}
        updated_form_data = Map.put(current_form_data, "value", generated_secret)

        socket =
          socket
          |> assign(:form, to_form(updated_form_data, as: :secret))
          |> put_flash(:info, "Secret generated successfully!")

        {:noreply, socket}

      {:error, reason} ->
        socket = put_flash(socket, :error, "Failed to generate secret: #{reason}")
        {:noreply, socket}
    end
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
    <VaultLiteWeb.Layouts.app flash={@flash} current_user={@current_user}>
      <div class="min-h-screen">
        <!-- Main Content -->
        <main class="max-w-2xl mx-auto py-6 px-4 sm:px-6 lg:px-8">
          <!-- Flash Messages -->
          <div :if={Phoenix.Flash.get(@flash, :info)} class="alert alert-success mb-4">
            <.icon name="hero-check-circle" class="h-5 w-5" />
            <span>{Phoenix.Flash.get(@flash, :info)}</span>
          </div>

          <div :if={Phoenix.Flash.get(@flash, :error)} class="alert alert-error mb-4">
            <.icon name="hero-x-circle" class="h-5 w-5" />
            <span>{Phoenix.Flash.get(@flash, :error)}</span>
          </div>
          
    <!-- Form -->
          <div class="card bg-base-100">
            <div class="card-body">
              <h1 class="card-title">{@page_title}</h1>

              <.form for={@form} phx-submit="submit" phx-change="validate" class="space-y-6">
                <!-- Secret Type Toggle (only for new secrets) -->
                <%= if @action == :new do %>
                  <div class="form-control">
                    <label class="label">
                      <span class="label-text font-medium">Secret Type</span>
                    </label>
                    <div class="flex gap-6">
                      <label class="label cursor-pointer gap-2">
                        <input
                          type="radio"
                          name="secret[secret_type]"
                          value="role_based"
                          checked={@selected_secret_type == "role_based"}
                          phx-click="toggle_secret_type"
                          phx-value-secret_type="role_based"
                          class="radio radio-primary"
                        />
                        <span class="label-text">Role-based Secret</span>
                      </label>
                      <label class="label cursor-pointer gap-2">
                        <input
                          type="radio"
                          name="secret[secret_type]"
                          value="personal"
                          checked={@selected_secret_type == "personal"}
                          phx-click="toggle_secret_type"
                          phx-value-secret_type="personal"
                          class="radio radio-primary"
                        />
                        <span class="label-text">Personal Secret</span>
                      </label>
                    </div>
                    <label class="label">
                      <span class="label-text-alt">
                        <%= if @selected_secret_type == "personal" do %>
                          Personal secrets are only accessible by you and won't be shared based on roles.
                        <% else %>
                          Role-based secrets are accessible based on your assigned roles and permissions.
                        <% end %>
                      </span>
                    </label>
                  </div>
                <% else %>
                  <div class="form-control">
                    <label class="label">
                      <span class="label-text font-medium">Secret Type</span>
                    </label>
                    <div class="flex items-center gap-2">
                      <span class="capitalize">{String.replace(@secret.secret_type, "_", " ")}</span>
                      <%= if @secret.secret_type == "personal" do %>
                        <div class="badge badge-info">Personal</div>
                      <% else %>
                        <div class="badge badge-success">Role-based</div>
                      <% end %>
                    </div>
                    <label class="label">
                      <span class="label-text-alt">Secret type cannot be changed when editing</span>
                    </label>
                  </div>
                <% end %>
                
    <!-- Secret Key (only for new secrets) -->
                <%= if @action == :new do %>
                  <div class="form-control">
                    <label class="label">
                      <span class="label-text font-medium">Secret Key</span>
                    </label>
                    <.input
                      field={@form[:key]}
                      type="text"
                      placeholder="e.g., api/database/password or prod/jwt-secret"
                      class={[
                        "input input-bordered",
                        if(@errors[:key], do: "input-error", else: "")
                      ]}
                      phx-debounce="300"
                    />
                    <label :if={@errors[:key]} class="label">
                      <span class="label-text-alt text-error">{@errors[:key]}</span>
                    </label>
                    <label class="label">
                      <span class="label-text-alt">
                        <%= if @selected_secret_type == "personal" do %>
                          Choose a descriptive name for your personal secret (e.g., my-password, personal-api-key)
                        <% else %>
                          Use forward slashes to organize secrets hierarchically (e.g., app/env/key)
                        <% end %>
                      </span>
                    </label>
                  </div>
                <% else %>
                  <div class="form-control">
                    <label class="label">
                      <span class="label-text font-medium">Secret Key</span>
                    </label>
                    <input type="text" value={@secret.key} class="input input-bordered" disabled />
                    <label class="label">
                      <span class="label-text-alt">Secret key cannot be changed when editing</span>
                    </label>
                  </div>
                <% end %>
                
    <!-- Secret Value -->
                <div class="form-control">
                  <div class="flex items-center justify-between">
                    <label class="label">
                      <span class="label-text font-medium">Secret Value</span>
                    </label>
                    <button
                      type="button"
                      phx-click="toggle_generator"
                      class="btn btn-sm btn-secondary"
                    >
                      <.icon name="hero-key" class="h-4 w-4" /> Generate
                    </button>
                  </div>
                  
    <!-- Secret Generator (Collapsible) -->
                  <%= if @show_generator do %>
                    <div class="card bg-base-200 mb-4">
                      <div class="card-body p-4">
                        <h4 class="card-title text-sm">Secret Generator</h4>

                        <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
                          <!-- Generator Type -->
                          <div class="form-control">
                            <label class="label">
                              <span class="label-text text-xs">Type</span>
                            </label>
                            <select
                              name="generator_type"
                              class="select select-bordered select-sm"
                              value={to_string(@generator_type)}
                              phx-change="update_generator_type"
                            >
                              <%= for {type, description} <- SecretGenerator.available_types() do %>
                                <option value={to_string(type)}>{description}</option>
                              <% end %>
                            </select>
                          </div>
                          
    <!-- Generator Length -->
                          <div class="form-control">
                            <label class="label">
                              <span class="label-text text-xs">Length</span>
                            </label>
                            <input
                              type="number"
                              name="generator_length"
                              value={@generator_length}
                              min="4"
                              max="128"
                              class="input input-bordered input-sm"
                              disabled={@generator_type == :uuid}
                              phx-change="update_generator_length"
                            />
                          </div>
                          
    <!-- Include Symbols (only for password type) -->
                          <%= if @generator_type == :password do %>
                            <div class="form-control">
                              <label class="label cursor-pointer">
                                <span class="label-text text-xs">Include Symbols</span>
                                <input
                                  type="checkbox"
                                  name="generator_include_symbols"
                                  value="true"
                                  checked={@generator_include_symbols}
                                  class="checkbox checkbox-sm"
                                  phx-change="update_generator_symbols"
                                />
                              </label>
                            </div>
                          <% end %>
                        </div>

                        <div class="card-actions justify-end mt-2">
                          <button
                            type="button"
                            phx-click="generate_secret"
                            class="btn btn-primary btn-sm"
                          >
                            <.icon name="hero-arrow-path" class="h-4 w-4" /> Generate Secret
                          </button>
                        </div>
                      </div>
                    </div>
                  <% end %>

                  <.input
                    field={@form[:value]}
                    type="textarea"
                    rows="4"
                    placeholder="Enter the secret value or use the generator above..."
                    class={[
                      "textarea textarea-bordered",
                      if(@errors[:value], do: "textarea-error", else: "")
                    ]}
                    phx-debounce="300"
                  />
                  <label :if={@errors[:value]} class="label">
                    <span class="label-text-alt text-error">{@errors[:value]}</span>
                  </label>
                  <label class="label">
                    <span class="label-text-alt">
                      The secret value will be encrypted before storage
                    </span>
                  </label>
                </div>
                
    <!-- Metadata -->
                <div class="form-control">
                  <div class="flex items-center justify-between">
                    <label class="label">
                      <span class="label-text font-medium">Metadata (Optional)</span>
                    </label>
                    <button type="button" phx-click="add_metadata_pair" class="btn btn-sm btn-primary">
                      <.icon name="hero-plus" class="h-4 w-4" /> Add Field
                    </button>
                  </div>

                  <div class="space-y-2">
                    <%= for {pair, index} <- Enum.with_index(@metadata_pairs) do %>
                      <div class="flex items-center gap-2">
                        <.input
                          name={"metadata_key_#{index}"}
                          type="text"
                          value={pair.key}
                          placeholder="Key"
                          class="input input-bordered flex-1"
                          phx-change="update_metadata_pair"
                          phx-value-index={index}
                          phx-value-field="key"
                        />
                        <.input
                          name={"metadata_value_#{index}"}
                          type="text"
                          value={pair.value}
                          placeholder="Value"
                          class="input input-bordered flex-1"
                          phx-change="update_metadata_pair"
                          phx-value-index={index}
                          phx-value-field="value"
                        />
                        <%= if length(@metadata_pairs) > 1 do %>
                          <button
                            type="button"
                            phx-click="remove_metadata_pair"
                            phx-value-index={index}
                            class="btn btn-ghost btn-sm"
                          >
                            <.icon name="hero-x-mark" class="h-4 w-4" />
                          </button>
                        <% end %>
                      </div>
                    <% end %>
                  </div>
                  <label class="label">
                    <span class="label-text-alt">
                      Add key-value pairs for additional secret information (e.g., environment, owner, etc.)
                    </span>
                  </label>
                </div>
                
    <!-- Submit Button -->
                <div class="card-actions justify-end pt-4">
                  <.link navigate="/dashboard" class="btn btn-ghost">
                    Cancel
                  </.link>

                  <button
                    type="submit"
                    disabled={not form_valid?(@errors) or @loading}
                    class={[
                      "btn",
                      if(form_valid?(@errors) and not @loading,
                        do: "btn-primary",
                        else: "btn-disabled"
                      )
                    ]}
                  >
                    <%= if @loading do %>
                      <span class="loading loading-spinner loading-sm"></span>
                      {if @action == :new, do: "Creating...", else: "Updating..."}
                    <% else %>
                      {if @action == :new, do: "Create Secret", else: "Update Secret"}
                    <% end %>
                  </button>
                </div>
              </.form>
            </div>
          </div>
        </main>
      </div>
    </VaultLiteWeb.Layouts.app>
    """
  end
end
