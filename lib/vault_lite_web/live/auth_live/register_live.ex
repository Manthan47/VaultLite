defmodule VaultLiteWeb.AuthLive.RegisterLive do
  @moduledoc """
  This module is responsible for the register live view.
  - displays the register form and allows the user to register.
  - displays the flash messages and allows the user to clear them.
  """
  use VaultLiteWeb, :live_view

  alias VaultLite.{Auth}

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Sign Up")
      |> assign(:form, to_form(%{"username" => "", "email" => "", "password" => ""}, as: :user))
      |> assign(:errors, %{})
      |> assign(:loading, false)
      |> assign(:password_strength, %{score: 0, feedback: []})

    {:ok, socket}
  end

  @impl true
  def handle_event("validate", %{"user" => user_params}, socket) do
    errors = validate_registration_form(user_params)
    password_strength = calculate_password_strength(Map.get(user_params, "password", ""))

    socket =
      socket
      |> assign(:form, to_form(user_params, as: :user))
      |> assign(:errors, errors)
      |> assign(:password_strength, password_strength)

    {:noreply, socket}
  end

  @impl true
  def handle_event("register", %{"user" => user_params}, socket) do
    socket = assign(socket, :loading, true)

    case Auth.create_user(user_params) do
      {:ok, user} ->
        socket =
          socket
          |> put_flash(:info, "Account created successfully! Welcome, #{user.username}!")
          |> assign(:loading, false)

        # Redirect to dashboard after successful registration
        {:noreply, push_navigate(socket, to: "/dashboard")}

      {:error, changeset} ->
        errors = extract_changeset_errors(changeset)

        socket =
          socket
          |> put_flash(:error, "Please fix the errors below")
          |> assign(:loading, false)
          |> assign(:errors, errors)
          |> assign(:form, to_form(user_params, as: :user))

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("clear_error", _, socket) do
    {:noreply, clear_flash(socket)}
  end

  # Real-time form validation
  defp validate_registration_form(%{
         "username" => username,
         "email" => email,
         "password" => password
       }) do
    errors = %{}

    # Username validation
    errors =
      cond do
        String.trim(username) == "" ->
          Map.put(errors, :username, "Username is required")

        String.length(username) < 3 ->
          Map.put(errors, :username, "Username must be at least 3 characters")

        String.length(username) > 30 ->
          Map.put(errors, :username, "Username must be less than 30 characters")

        not Regex.match?(~r/^[a-zA-Z0-9_-]+$/, username) ->
          Map.put(
            errors,
            :username,
            "Username can only contain letters, numbers, hyphens, and underscores"
          )

        true ->
          errors
      end

    # Email validation
    errors =
      cond do
        String.trim(email) == "" ->
          Map.put(errors, :email, "Email is required")

        not Regex.match?(~r/^[^\s]+@[^\s]+\.[^\s]+$/, email) ->
          Map.put(errors, :email, "Please enter a valid email address")

        true ->
          errors
      end

    # Password validation
    errors =
      cond do
        String.trim(password) == "" ->
          Map.put(errors, :password, "Password is required")

        String.length(password) < 8 ->
          Map.put(errors, :password, "Password must be at least 8 characters")

        String.length(password) > 128 ->
          Map.put(errors, :password, "Password must be less than 128 characters")

        not Regex.match?(~r/[A-Z]/, password) ->
          Map.put(errors, :password, "Password must contain at least one uppercase letter")

        not Regex.match?(~r/[a-z]/, password) ->
          Map.put(errors, :password, "Password must contain at least one lowercase letter")

        not Regex.match?(~r/[0-9]/, password) ->
          Map.put(errors, :password, "Password must contain at least one number")

        true ->
          errors
      end

    errors
  end

  defp validate_registration_form(_), do: %{}

  # Password strength calculation
  defp calculate_password_strength(password) do
    cond do
      String.length(password) == 0 ->
        %{score: 0, feedback: [], color: "gray"}

      String.length(password) < 8 ->
        %{score: 1, feedback: ["Too short"], color: "red"}

      String.length(password) < 12 and has_basic_requirements?(password) ->
        %{score: 2, feedback: ["Consider adding more characters"], color: "yellow"}

      String.length(password) >= 12 and has_basic_requirements?(password) and
          has_special_chars?(password) ->
        %{score: 4, feedback: ["Excellent password strength"], color: "green"}

      String.length(password) >= 12 and has_basic_requirements?(password) ->
        %{score: 3, feedback: ["Good strength - consider special characters"], color: "blue"}

      true ->
        %{score: 1, feedback: ["Missing uppercase, lowercase, or numbers"], color: "red"}
    end
  end

  defp has_basic_requirements?(password) do
    Regex.match?(~r/[A-Z]/, password) and
      Regex.match?(~r/[a-z]/, password) and
      Regex.match?(~r/[0-9]/, password)
  end

  defp has_special_chars?(password) do
    Regex.match?(~r/[!@#$%^&*()_+\-=\[\]{};':"\\|,.<>\/?]/, password)
  end

  # Extract errors from Ecto changeset
  defp extract_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end

  # Check if form is valid
  defp form_valid?(errors), do: Enum.empty?(errors)

  @impl true
  def render(assigns) do
    ~H"""
    <div class="hero min-h-screen">
      <div class="hero-content flex-col lg:flex-row-reverse">
        <div class="card flex-shrink-0 w-full max-w-sm">
          <div class="card-body">
            <!-- Header -->
            <div class="text-center mb-6">
              <div class="flex justify-center mb-4">
                <.icon name="hero-user-plus" class="h-12 w-12" />
              </div>
              <h1 class="text-3xl font-bold">Create your VaultLite account</h1>
              <p class="py-2">Join the secure secrets management platform</p>
            </div>
            
    <!-- Flash Messages -->
            <div :if={Phoenix.Flash.get(@flash, :info)} class="alert alert-success">
              <.icon name="hero-check-circle" class="h-5 w-5" />
              <span>{Phoenix.Flash.get(@flash, :info)}</span>
              <button type="button" phx-click="clear_error" class="btn btn-ghost btn-xs">
                <.icon name="hero-x-mark" class="h-4 w-4" />
              </button>
            </div>

            <div :if={Phoenix.Flash.get(@flash, :error)} class="alert alert-error">
              <.icon name="hero-x-circle" class="h-5 w-5" />
              <span>{Phoenix.Flash.get(@flash, :error)}</span>
              <button type="button" phx-click="clear_error" class="btn btn-ghost btn-xs">
                <.icon name="hero-x-mark" class="h-4 w-4" />
              </button>
            </div>
            
    <!-- Registration Form -->
            <.form for={@form} phx-submit="register" phx-change="validate" class="space-y-4">
              <!-- Username Field -->
              <div class="form-control">
                <label class="label">
                  <span class="label-text">Username</span>
                </label>
                <.input
                  field={@form[:username]}
                  type="text"
                  autocomplete="username"
                  placeholder="Enter your username"
                  class={[
                    "input input-bordered",
                    if(@errors[:username], do: "input-error", else: "")
                  ]}
                  phx-debounce="300"
                />
                <label :if={@errors[:username]} class="label">
                  <span class="label-text-alt text-error">{@errors[:username]}</span>
                </label>
              </div>
              
    <!-- Email Field -->
              <div class="form-control">
                <label class="label">
                  <span class="label-text">Email</span>
                </label>
                <.input
                  field={@form[:email]}
                  type="email"
                  autocomplete="email"
                  placeholder="Enter your email"
                  class={[
                    "input input-bordered",
                    if(@errors[:email], do: "input-error", else: "")
                  ]}
                  phx-debounce="300"
                />
                <label :if={@errors[:email]} class="label">
                  <span class="label-text-alt text-error">{@errors[:email]}</span>
                </label>
              </div>
              
    <!-- Password Field with Strength Indicator -->
              <div class="form-control">
                <label class="label">
                  <span class="label-text">Password</span>
                </label>
                <.input
                  field={@form[:password]}
                  type="password"
                  autocomplete="new-password"
                  placeholder="Create a strong password"
                  class={[
                    "input input-bordered",
                    if(@errors[:password], do: "input-error", else: "")
                  ]}
                  phx-debounce="300"
                />
                
    <!-- Password Strength Indicator -->
                <div :if={@password_strength.score > 0} class="mt-2">
                  <div class="flex items-center gap-2">
                    <progress
                      class={[
                        "progress w-full",
                        case @password_strength.color do
                          "red" -> "progress-error"
                          "yellow" -> "progress-warning"
                          "blue" -> "progress-info"
                          "green" -> "progress-success"
                          _ -> "progress-neutral"
                        end
                      ]}
                      value={@password_strength.score * 25}
                      max="100"
                    >
                    </progress>
                    <span class="text-xs font-medium">
                      {case @password_strength.score do
                        1 -> "Weak"
                        2 -> "Fair"
                        3 -> "Good"
                        4 -> "Strong"
                        _ -> ""
                      end}
                    </span>
                  </div>
                  <div :if={length(@password_strength.feedback) > 0} class="mt-1">
                    <p :for={feedback <- @password_strength.feedback} class="text-xs opacity-70">
                      {feedback}
                    </p>
                  </div>
                </div>

                <label :if={@errors[:password]} class="label">
                  <span class="label-text-alt text-error">{@errors[:password]}</span>
                </label>
              </div>

              <div class="form-control mt-6">
                <.button
                  type="submit"
                  disabled={not form_valid?(@errors) or @loading or @password_strength.score < 2}
                  class={[
                    "btn w-full",
                    if(form_valid?(@errors) and not @loading and @password_strength.score >= 2,
                      do: "btn-primary",
                      else: "btn-disabled"
                    )
                  ]}
                >
                  <span :if={@loading} class="loading loading-spinner loading-sm mr-2"></span>
                  <.icon :if={not @loading} name="hero-user-plus" class="h-5 w-5 mr-2" />
                  {if @loading, do: "Creating account...", else: "Create account"}
                </.button>
              </div>

              <div class="text-center">
                <p>
                  Already have an account?
                  <.link navigate="/login" class="link link-primary">
                    Sign in
                  </.link>
                </p>
              </div>
            </.form>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
