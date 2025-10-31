defmodule VaultLiteWeb.Layouts do
  @moduledoc """
  This module holds different layouts used by your application.

  See the `layouts` directory for all templates available.
  The "root" layout is a skeleton rendered as part of the
  application router. The "app" layout is rendered as component
  in regular views and live views.
  """
  use VaultLiteWeb, :html

  embed_templates "layouts/*"

  @doc """
  Renders the app layout

  ## Examples

      <Layouts.app flash={@flash} current_user={@current_user}>
        <h1>Content</h1>
      </Layout.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :current_user, :map, default: nil, doc: "the current authenticated user"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <!-- Main Navigation -->
    <%= if @current_user do %>
      <nav class="navbar">
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div class="flex justify-between h-16">
            <div class="flex items-center">
              <.icon name="hero-lock-closed" class="h-8 w-8" />
              <span class="ml-2 mr-4 text-xl font-bold">VaultLite</span>
            </div>

            <div class="flex items-center space-x-4">
              <div class="text-sm">Welcome, {@current_user.username}!</div>

              <.link navigate="/dashboard" class="btn btn-ghost btn-sm">
                Dashboard
              </.link>

              <%= if VaultLite.Auth.is_admin?(@current_user) do %>
                <.link navigate="/admin/users" class="btn btn-ghost btn-sm">
                  User Management
                </.link>

                <.link navigate="/admin/roles" class="btn btn-ghost btn-sm">
                  Role Management
                </.link>

                <.link navigate="/admin/audit" class="btn btn-ghost btn-sm">
                  Audit Logs
                </.link>
              <% end %>

              <.link navigate="/secrets/new" class="btn btn-primary btn-sm">
                New Secret
              </.link>

              <div class="flex-none">
                <ul class="flex flex-column px-1 space-x-2 items-center">
                  <li>
                    <.theme_toggle />
                  </li>
                </ul>
              </div>

              <.link href="/logout" method="delete" class="btn btn-ghost btn-sm">
                Logout
              </.link>
            </div>
          </div>
        </div>
      </nav>
    <% else %>
      <!-- Header for non-authenticated pages -->
      <header class="navbar px-2 sm:px-4 lg:px-6">
        <div class="flex-1"></div>
        <div class="flex-none">
          <ul class="flex flex-column px-1 space-x-2 items-center">
            <li>
              <.theme_toggle />
            </li>
          </ul>
        </div>
      </header>
    <% end %>

    <main class="w-full h-full">
      {render_slot(@inner_block)}
    </main>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides theme selection dropdown based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="dropdown dropdown-end">
      <div tabindex="0" role="button" class="btn btn-ghost btn-sm gap-2">
        <.icon name="hero-paint-brush" class="h-4 w-4" />
        <span class="hidden sm:inline">Theme</span>
        <.icon name="hero-chevron-down" class="h-3 w-3" />
      </div>
      <ul
        tabindex="0"
        class="dropdown-content menu bg-base-100 rounded-box z-[1] w-52 p-2 shadow-lg border border-base-300"
      >
        <li>
          <button
            phx-click={JS.dispatch("phx:set-theme", detail: %{theme: "system"})}
            class="flex items-center gap-3 p-2 rounded-lg hover:bg-base-200"
          >
            <.icon name="hero-computer-desktop" class="h-4 w-4" />
            <span>System</span>
            <div class="ml-auto">
              <.icon
                name="hero-check"
                class="h-4 w-4 [[data-theme-preference=system]_&]:opacity-100 opacity-0"
              />
            </div>
          </button>
        </li>
        <li>
          <button
            phx-click={JS.dispatch("phx:set-theme", detail: %{theme: "light"})}
            class="flex items-center gap-3 p-2 rounded-lg hover:bg-base-200"
          >
            <.icon name="hero-sun" class="h-4 w-4" />
            <span>Light</span>
            <div class="ml-auto">
              <.icon name="hero-check" class="h-4 w-4 [[data-theme=light]_&]:opacity-100 opacity-0" />
            </div>
          </button>
        </li>
        <li>
          <button
            phx-click={JS.dispatch("phx:set-theme", detail: %{theme: "dark"})}
            class="flex items-center gap-3 p-2 rounded-lg hover:bg-base-200"
          >
            <.icon name="hero-moon" class="h-4 w-4" />
            <span>Dark</span>
            <div class="ml-auto">
              <.icon name="hero-check" class="h-4 w-4 [[data-theme=dark]_&]:opacity-100 opacity-0" />
            </div>
          </button>
        </li>
        <li>
          <button
            phx-click={JS.dispatch("phx:set-theme", detail: %{theme: "nord"})}
            class="flex items-center gap-3 p-2 rounded-lg hover:bg-base-200"
          >
            <div
              class="grid shrink-0 grid-cols-2 gap-0.5 rounded-md p-1 shadow-sm"
              style="background-color: oklch(0.95127 0.007 260.731);"
            >
              <div class="size-1 rounded-full" style="background-color: oklch(0.32437 0.022 264.182);">
              </div>

              <div class="size-1 rounded-full" style="background-color: oklch(0.59435 0.077 254.027);">
              </div>

              <div class="size-1 rounded-full" style="background-color: oklch(0.69651 0.059 248.687);">
              </div>

              <div class="size-1 rounded-full" style="background-color: oklch(0.77464 0.062 217.469);">
              </div>
            </div>
            <span>Nord</span>
            <div class="ml-auto">
              <.icon name="hero-check" class="h-4 w-4 [[data-theme=nord]_&]:opacity-100 opacity-0" />
            </div>
          </button>
        </li>
        <li>
          <button
            phx-click={JS.dispatch("phx:set-theme", detail: %{theme: "winter"})}
            class="flex items-center gap-3 p-2 rounded-lg hover:bg-base-200"
          >
            <div
              class="grid shrink-0 grid-cols-2 gap-0.5 rounded-md p-1 shadow-sm"
              style="background-color: oklch(0.97466 0.011 259.822);"
            >
              <div class="size-1 rounded-full" style="background-color: oklch(0.41886 0.053 255.824);">
              </div>

              <div class="size-1 rounded-full" style="background-color: oklch(0.5686 0.255 257.57);">
              </div>

              <div class="size-1 rounded-full" style="background-color: oklch(0.42551 0.161 282.339);">
              </div>

              <div class="size-1 rounded-full" style="background-color: oklch(0.59939 0.191 335.171);">
              </div>
            </div>
            <span>Winter</span>
            <div class="ml-auto">
              <.icon name="hero-check" class="h-4 w-4 [[data-theme=winter]_&]:opacity-100 opacity-0" />
            </div>
          </button>
        </li>
        <li>
          <button
            phx-click={JS.dispatch("phx:set-theme", detail: %{theme: "business"})}
            class="flex items-center gap-3 p-2 rounded-lg hover:bg-base-200"
          >
            <div
              class="grid shrink-0 grid-cols-2 gap-0.5 rounded-md p-1 shadow-sm"
              style="background-color: oklch(0.24353 0 0);"
            >
              <div class="size-1 rounded-full" style="background-color: oklch(0.8487 0 0);"></div>

              <div class="size-1 rounded-full" style="background-color: oklch(0.41703 0.099 251.473);">
              </div>

              <div class="size-1 rounded-full" style="background-color: oklch(0.64092 0.027 229.389);">
              </div>

              <div class="size-1 rounded-full" style="background-color: oklch(0.67271 0.167 35.791);">
              </div>
            </div>
            <span>Business</span>
            <div class="ml-auto">
              <.icon
                name="hero-check"
                class="h-4 w-4 [[data-theme=business]_&]:opacity-100 opacity-0"
              />
            </div>
          </button>
        </li>
        <li>
          <button
            phx-click={JS.dispatch("phx:set-theme", detail: %{theme: "night"})}
            class="flex items-center gap-3 p-2 rounded-lg hover:bg-base-200"
          >
            <div
              class="grid shrink-0 grid-cols-2 gap-0.5 rounded-md p-1 shadow-sm"
              style="background-color: oklch(0.20768 0.039 265.754);"
            >
              <div class="size-1 rounded-full" style="background-color: oklch(0.84153 0.007 265.754);">
              </div>

              <div class="size-1 rounded-full" style="background-color: oklch(0.75351 0.138 232.661);">
              </div>

              <div class="size-1 rounded-full" style="background-color: oklch(0.68011 0.158 276.934);">
              </div>

              <div class="size-1 rounded-full" style="background-color: oklch(0.7236 0.176 350.048);">
              </div>
            </div>
            <span>Night</span>
            <div class="ml-auto">
              <.icon name="hero-check" class="h-4 w-4 [[data-theme=night]_&]:opacity-100 opacity-0" />
            </div>
          </button>
        </li>
      </ul>
    </div>
    """
  end
end
