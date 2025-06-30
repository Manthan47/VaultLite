defmodule VaultLiteWeb.AuthLive.LoginLive do
  @moduledoc """
  This module is responsible for the login live view.
  - displays the login form and allows the user to login.
  - displays the flash messages and allows the user to clear them.
  """
  use VaultLiteWeb, :live_view

  import Phoenix.Controller, only: [get_csrf_token: 0]

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Sign In")

    {:ok, socket}
  end

  @impl true
  def handle_event("clear_error", _, socket) do
    {:noreply, clear_flash(socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="h-full flex items-center justify-center bg-gray-50 py-12 px-4 sm:px-6 lg:px-8">
      <div class="max-w-md w-full space-y-8">
        <!-- Header -->
        <div>
          <div class="mx-auto h-12 w-auto flex justify-center">
            <.icon name="hero-lock-closed" class="h-12 w-12 text-indigo-600" />
          </div>
          <h2 class="mt-6 text-center text-3xl font-extrabold text-gray-900">
            Sign in to VaultLite
          </h2>
          <p class="mt-2 text-center text-sm text-gray-600">
            Secure access to your secrets
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
        
    <!-- Login Form -->
        <form action="/liveview_login" method="post" class="mt-8 space-y-6">
          <input name="_csrf_token" type="hidden" value={get_csrf_token()} />
          <div class="rounded-md shadow-sm -space-y-px">
            <div>
              <label for="identifier" class="sr-only">Username or Email</label>
              <input
                id="identifier"
                name="identifier"
                type="text"
                autocomplete="username"
                placeholder="Username or Email"
                required
                class="relative block w-full rounded-t-md border-0 py-1.5 text-gray-900 ring-1 ring-inset ring-gray-300 placeholder:text-gray-400 focus:z-10 focus:ring-2 focus:ring-inset focus:ring-indigo-600 sm:text-sm sm:leading-6"
              />
            </div>
            <div>
              <label for="password" class="sr-only">Password</label>
              <input
                id="password"
                name="password"
                type="password"
                autocomplete="current-password"
                placeholder="Password"
                required
                class="relative block w-full rounded-b-md border-0 py-1.5 text-gray-900 ring-1 ring-inset ring-gray-300 placeholder:text-gray-400 focus:z-10 focus:ring-2 focus:ring-inset focus:ring-indigo-600 sm:text-sm sm:leading-6"
              />
            </div>
          </div>

          <div>
            <button
              type="submit"
              class="group relative w-full flex justify-center py-2 px-4 border border-transparent text-sm font-medium rounded-md text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
            >
              <span class="absolute left-0 inset-y-0 flex items-center pl-3">
                <svg
                  class="h-5 w-5 text-indigo-500 group-hover:text-indigo-400"
                  fill="currentColor"
                  viewBox="0 0 20 20"
                >
                  <path
                    fill-rule="evenodd"
                    d="M5 9V7a5 5 0 0110 0v2a2 2 0 012 2v5a2 2 0 01-2 2H5a2 2 0 01-2-2v-5a2 2 0 012-2zm8-2v2H7V7a3 3 0 016 0z"
                    clip-rule="evenodd"
                  />
                </svg>
              </span>
              Sign in
            </button>
          </div>

          <div class="text-center">
            <p class="text-sm text-gray-600">
              Don't have an account?
              <.link navigate="/register" class="font-medium text-indigo-600 hover:text-indigo-500">
                Sign up
              </.link>
            </p>
          </div>
        </form>
      </div>
    </div>
    """
  end
end
