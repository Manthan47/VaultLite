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
    <div class="h-full flex items-center justify-center bg-gray-50 py-12 px-4 sm:px-6 lg:px-8">
      <div class="max-w-md w-full space-y-8">
        <!-- Header -->
        <div>
          <div class="mx-auto h-12 w-auto flex justify-center">
            <.icon name="hero-user-plus" class="h-12 w-12 text-indigo-600" />
          </div>
          <h2 class="mt-6 text-center text-3xl font-extrabold text-gray-900">
            Create your VaultLite account
          </h2>
          <p class="mt-2 text-center text-sm text-gray-600">
            Join the secure secrets management platform
          </p>
        </div>
        
    <!-- Flash Messages -->
        <div :if={Phoenix.Flash.get(@flash, :info)} class="rounded-md bg-green-50 p-4">
          <div class="flex">
            <div class="flex-shrink-0">
              <.icon name="hero-check-circle" class="h-5 w-5 text-green-400" />
            </div>
            <div class="ml-3">
              <p class="text-sm font-medium text-green-800">
                {Phoenix.Flash.get(@flash, :info)}
              </p>
            </div>
            <div class="ml-auto pl-3">
              <div class="-mx-1.5 -my-1.5">
                <button
                  type="button"
                  phx-click="clear_error"
                  class="inline-flex bg-green-50 rounded-md p-1.5 text-green-500 hover:bg-green-100"
                >
                  <.icon name="hero-x-mark" class="h-5 w-5" />
                </button>
              </div>
            </div>
          </div>
        </div>

        <div :if={Phoenix.Flash.get(@flash, :error)} class="rounded-md bg-red-50 p-4">
          <div class="flex">
            <div class="flex-shrink-0">
              <.icon name="hero-x-circle" class="h-5 w-5 text-red-400" />
            </div>
            <div class="ml-3">
              <p class="text-sm font-medium text-red-800">
                {Phoenix.Flash.get(@flash, :error)}
              </p>
            </div>
            <div class="ml-auto pl-3">
              <div class="-mx-1.5 -my-1.5">
                <button
                  type="button"
                  phx-click="clear_error"
                  class="inline-flex bg-red-50 rounded-md p-1.5 text-red-500 hover:bg-red-100"
                >
                  <.icon name="hero-x-mark" class="h-5 w-5" />
                </button>
              </div>
            </div>
          </div>
        </div>
        
    <!-- Registration Form -->
        <.form for={@form} phx-submit="register" phx-change="validate" class="mt-8 space-y-6">
          <div class="space-y-4">
            <!-- Username Field -->
            <div>
              <label for="username" class="block text-sm font-medium text-gray-700">Username</label>
              <.input
                field={@form[:username]}
                type="text"
                autocomplete="username"
                placeholder="Enter your username"
                class={[
                  "mt-1 block w-full rounded-md border-0 py-1.5 text-gray-900 ring-1 ring-inset placeholder:text-gray-400 focus:ring-2 focus:ring-inset sm:text-sm sm:leading-6",
                  if(@errors[:username],
                    do: "ring-red-300 focus:ring-red-600",
                    else: "ring-gray-300 focus:ring-indigo-600"
                  )
                ]}
                phx-debounce="300"
              />
              <p :if={@errors[:username]} class="mt-1 text-sm text-red-600">
                {@errors[:username]}
              </p>
            </div>
            
    <!-- Email Field -->
            <div>
              <label for="email" class="block text-sm font-medium text-gray-700">Email</label>
              <.input
                field={@form[:email]}
                type="email"
                autocomplete="email"
                placeholder="Enter your email"
                class={[
                  "mt-1 block w-full rounded-md border-0 py-1.5 text-gray-900 ring-1 ring-inset placeholder:text-gray-400 focus:ring-2 focus:ring-inset sm:text-sm sm:leading-6",
                  if(@errors[:email],
                    do: "ring-red-300 focus:ring-red-600",
                    else: "ring-gray-300 focus:ring-indigo-600"
                  )
                ]}
                phx-debounce="300"
              />
              <p :if={@errors[:email]} class="mt-1 text-sm text-red-600">
                {@errors[:email]}
              </p>
            </div>
            
    <!-- Password Field with Strength Indicator -->
            <div>
              <label for="password" class="block text-sm font-medium text-gray-700">Password</label>
              <.input
                field={@form[:password]}
                type="password"
                autocomplete="new-password"
                placeholder="Create a strong password"
                class={[
                  "mt-1 block w-full rounded-md border-0 py-1.5 text-gray-900 ring-1 ring-inset placeholder:text-gray-400 focus:ring-2 focus:ring-inset sm:text-sm sm:leading-6",
                  if(@errors[:password],
                    do: "ring-red-300 focus:ring-red-600",
                    else: "ring-gray-300 focus:ring-indigo-600"
                  )
                ]}
                phx-debounce="300"
              />
              
    <!-- Password Strength Indicator -->
              <div :if={@password_strength.score > 0} class="mt-2">
                <div class="flex items-center space-x-2">
                  <div class="flex-1">
                    <div class="bg-gray-200 rounded-full h-2">
                      <div class={[
                        "h-2 rounded-full transition-all duration-300",
                        case @password_strength.color do
                          "red" -> "bg-red-500 w-1/4"
                          "yellow" -> "bg-yellow-500 w-2/4"
                          "blue" -> "bg-blue-500 w-3/4"
                          "green" -> "bg-green-500 w-full"
                          _ -> "bg-gray-300 w-0"
                        end
                      ]}>
                      </div>
                    </div>
                  </div>
                  <span class={[
                    "text-xs font-medium",
                    case @password_strength.color do
                      "red" -> "text-red-600"
                      "yellow" -> "text-yellow-600"
                      "blue" -> "text-blue-600"
                      "green" -> "text-green-600"
                      _ -> "text-gray-600"
                    end
                  ]}>
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
                  <p :for={feedback <- @password_strength.feedback} class="text-xs text-gray-600">
                    {feedback}
                  </p>
                </div>
              </div>

              <p :if={@errors[:password]} class="mt-1 text-sm text-red-600">
                {@errors[:password]}
              </p>
            </div>
          </div>

          <div>
            <.button
              type="submit"
              disabled={not form_valid?(@errors) or @loading or @password_strength.score < 2}
              class={
                "group relative w-full flex justify-center py-2 px-4 border border-transparent text-sm font-medium rounded-md text-white focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500 " <>
                  if(form_valid?(@errors) and not @loading and @password_strength.score >= 2,
                    do: "bg-indigo-600 hover:bg-indigo-700",
                    else: "bg-gray-400 cursor-not-allowed"
                  )
              }
            >
              <span :if={@loading} class="absolute left-0 inset-y-0 flex items-center pl-3">
                <svg
                  class="animate-spin h-5 w-5 text-white"
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
              </span>
              <span :if={not @loading} class="absolute left-0 inset-y-0 flex items-center pl-3">
                <.icon
                  name="hero-user-plus"
                  class="h-5 w-5 text-indigo-500 group-hover:text-indigo-400"
                />
              </span>
              {if @loading, do: "Creating account...", else: "Create account"}
            </.button>
          </div>

          <div class="text-center">
            <p class="text-sm text-gray-600">
              Already have an account?
              <.link navigate="/login" class="font-medium text-indigo-600 hover:text-indigo-500">
                Sign in
              </.link>
            </p>
          </div>
        </.form>
      </div>
    </div>
    """
  end
end
