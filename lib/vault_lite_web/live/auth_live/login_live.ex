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
    <div class="hero min-h-screen">
      <div class="hero-content flex-col lg:flex-row-reverse">
        <div class="card flex-shrink-0 w-full max-w-sm">
          <div class="card-body">
            <!-- Header -->
            <div class="text-center mb-6">
              <div class="flex justify-center mb-4">
                <.icon name="hero-lock-closed" class="h-12 w-12" />
              </div>
              <h1 class="text-3xl font-bold">Sign in to VaultLite</h1>
              <p class="py-2">Secure access to your secrets</p>
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
            
    <!-- Login Form -->
            <form action="/liveview_login" method="post" class="space-y-4">
              <input name="_csrf_token" type="hidden" value={get_csrf_token()} />

              <div class="form-control">
                <label class="label">
                  <span class="label-text">Username or Email</span>
                </label>
                <input
                  id="identifier"
                  name="identifier"
                  type="text"
                  autocomplete="username"
                  placeholder="Username or Email"
                  required
                  class="input input-bordered"
                />
              </div>

              <div class="form-control">
                <label class="label">
                  <span class="label-text">Password</span>
                </label>
                <input
                  id="password"
                  name="password"
                  type="password"
                  autocomplete="current-password"
                  placeholder="Password"
                  required
                  class="input input-bordered"
                />
              </div>

              <div class="form-control mt-6">
                <button type="submit" class="btn btn-primary justify-center">
                  <svg class="h-5 w-5 mr-2" fill="currentColor" viewBox="0 0 20 20">
                    <path
                      fill-rule="evenodd"
                      d="M5 9V7a5 5 0 0110 0v2a2 2 0 012 2v5a2 2 0 01-2 2H5a2 2 0 01-2-2v-5a2 2 0 012-2zm8-2v2H7V7a3 3 0 016 0z"
                      clip-rule="evenodd"
                    />
                  </svg>
                  Sign in
                </button>
              </div>

              <div class="text-center">
                <p>
                  Don't have an account?
                  <.link navigate="/register" class="link link-primary">
                    Sign up
                  </.link>
                </p>
              </div>
            </form>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
