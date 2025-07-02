defmodule VaultLiteWeb.AdminLive.AuditLogLive do
  @moduledoc """
  This module is responsible for the audit log live view.
  - displays the audit logs and allows the user to filter and search through them.
  - displays the statistics of the audit logs.
  """
  use VaultLiteWeb, :live_view

  alias VaultLite.Audit
  alias VaultLite.Auth
  alias VaultLite.Schema.User

  @impl true
  def mount(_params, session, socket) do
    current_user = get_current_user(session)

    if is_nil(current_user) do
      {:ok, redirect(socket, to: "/login")}
    else
      # Check if user has admin privileges to view audit logs
      case Auth.has_role?(current_user, "system_admin") do
        true ->
          socket =
            socket
            |> assign(:current_user, current_user)
            |> assign(:page_title, "Audit Logs")
            |> assign(:loading, true)
            |> assign(:audit_logs, [])
            |> assign(:statistics, %{})
            |> assign(:filters, %{})
            |> assign(:pagination, %{page: 1, per_page: 20, total: 0})
            |> assign(:search_query, "")

          # Load initial data
          send(self(), :load_data)

          {:ok, socket}

        false ->
          {:ok,
           socket
           |> put_flash(:error, "Access denied. Admin privileges required.")
           |> redirect(to: "/dashboard")}
      end
    end
  end

  @impl true
  def handle_info(:load_data, socket) do
    socket =
      socket
      |> load_audit_logs()
      |> load_statistics()
      |> assign(:loading, false)

    {:noreply, socket}
  end

  @impl true
  def handle_event("filter", %{"filter" => filter_params}, socket) do
    filters = build_filters(filter_params)

    socket =
      socket
      |> assign(:filters, filters)
      |> assign(:pagination, Map.put(socket.assigns.pagination, :page, 1))
      |> load_audit_logs()

    {:noreply, socket}
  end

  @impl true
  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    socket =
      socket
      |> assign(:search_query, query)
      |> assign(:pagination, Map.put(socket.assigns.pagination, :page, 1))
      |> load_audit_logs()

    {:noreply, socket}
  end

  @impl true
  def handle_event("paginate", %{"page" => page}, socket) do
    {page_num, _} = Integer.parse(page)

    socket =
      socket
      |> assign(:pagination, Map.put(socket.assigns.pagination, :page, page_num))
      |> load_audit_logs()

    {:noreply, socket}
  end

  @impl true
  def handle_event("clear_filters", _params, socket) do
    socket =
      socket
      |> assign(:filters, %{})
      |> assign(:search_query, "")
      |> assign(:pagination, %{page: 1, per_page: 20, total: 0})
      |> load_audit_logs()

    {:noreply, socket}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    socket =
      socket
      |> load_audit_logs()
      |> load_statistics()

    {:noreply, socket}
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

  defp load_audit_logs(socket) do
    %{filters: filters, pagination: pagination, search_query: search_query} = socket.assigns

    opts =
      []
      |> add_filter_opts(filters)
      |> add_search_opts(search_query)
      |> add_pagination_opts(pagination)

    case Audit.get_audit_logs(opts) do
      {:ok, logs} ->
        # Get total count for pagination
        total_opts = opts |> Keyword.delete(:limit) |> Keyword.delete(:offset)
        {:ok, all_logs} = Audit.get_audit_logs(total_opts)
        total = length(all_logs)

        socket
        |> assign(:audit_logs, logs)
        |> assign(:pagination, Map.put(pagination, :total, total))

      {:error, _reason} ->
        socket
        |> put_flash(:error, "Failed to load audit logs")
        |> assign(:audit_logs, [])
    end
  end

  defp load_statistics(socket) do
    case Audit.get_audit_statistics() do
      {:ok, stats} ->
        assign(socket, :statistics, stats)

      {:error, _reason} ->
        socket
        |> put_flash(:error, "Failed to load statistics")
        |> assign(:statistics, %{})
    end
  end

  defp build_filters(filter_params) do
    filters = %{}

    filters =
      case Map.get(filter_params, "action", "") do
        "" -> filters
        action -> Map.put(filters, :action, action)
      end

    filters =
      case Map.get(filter_params, "user_id", "") do
        "" ->
          filters

        user_id_str ->
          case Integer.parse(user_id_str) do
            {user_id, _} -> Map.put(filters, :user_id, user_id)
            _ -> filters
          end
      end

    filters =
      case Map.get(filter_params, "secret_key", "") do
        "" -> filters
        secret_key -> Map.put(filters, :secret_key, secret_key)
      end

    filters =
      case Map.get(filter_params, "start_date", "") do
        "" ->
          filters

        date_str ->
          case Date.from_iso8601(date_str) do
            {:ok, date} ->
              datetime = DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
              Map.put(filters, :start_date, datetime)

            _ ->
              filters
          end
      end

    filters =
      case Map.get(filter_params, "end_date", "") do
        "" ->
          filters

        date_str ->
          case Date.from_iso8601(date_str) do
            {:ok, date} ->
              datetime = DateTime.new!(date, ~T[23:59:59], "Etc/UTC")
              Map.put(filters, :end_date, datetime)

            _ ->
              filters
          end
      end

    filters
  end

  defp add_filter_opts(opts, filters) do
    Enum.reduce(filters, opts, fn {key, value}, acc ->
      Keyword.put(acc, key, value)
    end)
  end

  defp add_search_opts(opts, search_query) when search_query == "", do: opts

  defp add_search_opts(opts, search_query) do
    # For search, we'll filter by secret_key containing the query
    Keyword.put(opts, :secret_key_contains, search_query)
  end

  defp add_pagination_opts(opts, %{page: page, per_page: per_page}) do
    offset = (page - 1) * per_page

    opts
    |> Keyword.put(:limit, per_page)
    |> Keyword.put(:offset, offset)
  end

  defp format_timestamp(timestamp) do
    timestamp
    |> DateTime.shift_zone!("Etc/UTC")
    |> Calendar.strftime("%Y-%m-%d %H:%M:%S UTC")
  end

  defp format_metadata(metadata) when map_size(metadata) == 0, do: "-"

  defp format_metadata(metadata) do
    metadata
    |> Enum.map(fn {k, v} -> "#{k}: #{inspect(v)}" end)
    |> Enum.join(", ")
  end

  defp get_action_badge_class(action) do
    case action do
      "create" -> "badge badge-success"
      "read" -> "badge badge-info"
      "update" -> "badge badge-warning"
      "delete" -> "badge badge-error"
      "list" -> "badge badge-ghost"
      _ -> "badge badge-ghost"
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <VaultLiteWeb.Layouts.app flash={@flash} current_user={@current_user}>
      <div class="min-h-screen">
        <!-- Main Content -->
        <main class="max-w-7xl mx-auto py-6 px-4 sm:px-6 lg:px-8">
          <!-- Page Header -->
          <div class="md:flex md:items-center md:justify-between">
            <div class="flex-1 min-w-0">
              <h2 class="text-2xl font-bold leading-7 sm:text-3xl sm:truncate">
                Audit Logs
              </h2>
              <p class="mt-1 text-sm opacity-70">
                Monitor and review all system activities
              </p>
            </div>
            <div class="mt-4 flex md:mt-0 md:ml-4">
              <button phx-click="refresh" class="btn btn-outline">
                <.icon name="hero-arrow-path" class="h-4 w-4 mr-2" /> Refresh
              </button>
            </div>
          </div>
          
    <!-- Statistics Cards -->
          <div class="stats shadow mt-6 w-full">
            <div class="stat">
              <div class="stat-figure">
                <.icon name="hero-document-text" class="h-8 w-8" />
              </div>
              <div class="stat-title">Total Logs</div>
              <div class="stat-value">{Map.get(@statistics, :total_logs, 0)}</div>
            </div>

            <div class="stat">
              <div class="stat-figure">
                <.icon name="hero-users" class="h-8 w-8" />
              </div>
              <div class="stat-title">Active Users</div>
              <div class="stat-value">{Map.get(@statistics, :active_users, 0)}</div>
            </div>

            <div class="stat">
              <div class="stat-figure">
                <.icon name="hero-key" class="h-8 w-8" />
              </div>
              <div class="stat-title">Top Secret</div>
              <div class="stat-value text-sm">
                {case Map.get(@statistics, :top_secrets, []) do
                  [] -> "None"
                  [top | _] -> top.secret_key
                end}
              </div>
            </div>

            <div class="stat">
              <div class="stat-figure">
                <.icon name="hero-chart-bar" class="h-8 w-8" />
              </div>
              <div class="stat-title">Most Common Action</div>
              <div class="stat-value text-sm">
                {case Map.get(@statistics, :actions, %{}) do
                  actions when map_size(actions) == 0 ->
                    "None"

                  actions ->
                    {action, _count} = Enum.max_by(actions, fn {_k, v} -> v end)
                    String.capitalize(action)
                end}
              </div>
            </div>
          </div>
          
    <!-- Search and Filters -->
          <div class="card bg-base-100 shadow mt-6">
            <div class="card-body">
              <h3 class="card-title">Search & Filters</h3>
              
    <!-- Search Bar -->
              <div class="form-control">
                <.form for={%{}} as={:search} phx-submit="search" class="input-group">
                  <input
                    type="text"
                    name="search[query]"
                    value={@search_query}
                    placeholder="Search by secret key..."
                    class="input input-bordered flex-1"
                  />
                  <button type="submit" class="btn btn-primary">
                    Search
                  </button>
                </.form>
              </div>
              
    <!-- Filters -->
              <.form
                for={%{}}
                as={:filter}
                phx-submit="filter"
                class="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-5"
              >
                <div class="form-control">
                  <label class="label">
                    <span class="label-text">Action</span>
                  </label>
                  <select name="filter[action]" class="select select-bordered">
                    <option value="">All Actions</option>
                    <option value="create" selected={Map.get(@filters, :action) == "create"}>
                      Create
                    </option>
                    <option value="read" selected={Map.get(@filters, :action) == "read"}>Read</option>
                    <option value="update" selected={Map.get(@filters, :action) == "update"}>
                      Update
                    </option>
                    <option value="delete" selected={Map.get(@filters, :action) == "delete"}>
                      Delete
                    </option>
                    <option value="list" selected={Map.get(@filters, :action) == "list"}>List</option>
                  </select>
                </div>

                <div class="form-control">
                  <label class="label">
                    <span class="label-text">User ID</span>
                  </label>
                  <input
                    type="number"
                    name="filter[user_id]"
                    value={Map.get(@filters, :user_id, "")}
                    placeholder="User ID"
                    class="input input-bordered"
                  />
                </div>

                <div class="form-control">
                  <label class="label">
                    <span class="label-text">Secret Key</span>
                  </label>
                  <input
                    type="text"
                    name="filter[secret_key]"
                    value={Map.get(@filters, :secret_key, "")}
                    placeholder="Secret key"
                    class="input input-bordered"
                  />
                </div>

                <div class="form-control">
                  <label class="label">
                    <span class="label-text">Start Date</span>
                  </label>
                  <input
                    type="date"
                    name="filter[start_date]"
                    value={
                      case Map.get(@filters, :start_date) do
                        nil -> ""
                        date -> Date.to_iso8601(DateTime.to_date(date))
                      end
                    }
                    class="input input-bordered"
                  />
                </div>

                <div class="form-control">
                  <label class="label">
                    <span class="label-text">End Date</span>
                  </label>
                  <input
                    type="date"
                    name="filter[end_date]"
                    value={
                      case Map.get(@filters, :end_date) do
                        nil -> ""
                        date -> Date.to_iso8601(DateTime.to_date(date))
                      end
                    }
                    class="input input-bordered"
                  />
                </div>

                <div class="sm:col-span-2 lg:col-span-5 flex gap-3">
                  <button type="submit" class="btn btn-primary">
                    Apply Filters
                  </button>
                  <button type="button" phx-click="clear_filters" class="btn btn-outline">
                    Clear Filters
                  </button>
                </div>
              </.form>
            </div>
          </div>
          
    <!-- Audit Logs Table -->
          <div class="card bg-base-100 shadow mt-6">
            <div class="card-body">
              <div class="flex justify-between items-center mb-4">
                <h3 class="card-title">Audit Logs</h3>
                <span class="text-sm opacity-70">
                  {length(@audit_logs)} of {@pagination.total} entries
                </span>
              </div>

              <div :if={@loading} class="text-center py-8">
                <span class="loading loading-spinner loading-lg"></span>
                <p class="mt-2 text-sm opacity-70">Loading audit logs...</p>
              </div>

              <div :if={!@loading and length(@audit_logs) == 0} class="text-center py-8">
                <.icon name="hero-document-text" class="mx-auto h-12 w-12" />
                <h3 class="mt-2 text-sm font-medium">No audit logs found</h3>
                <p class="mt-1 text-sm opacity-70">
                  Try adjusting your search criteria or filters.
                </p>
              </div>

              <div :if={!@loading and length(@audit_logs) > 0} class="overflow-x-auto">
                <table class="table">
                  <thead>
                    <tr>
                      <th>Timestamp</th>
                      <th>User</th>
                      <th>Action</th>
                      <th>Secret Key</th>
                      <th>Metadata</th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr :for={log <- @audit_logs} class="hover">
                      <td class="font-mono text-sm">
                        {format_timestamp(log.timestamp)}
                      </td>
                      <td>
                        {log.user_id || "System"}
                      </td>
                      <td>
                        <div class={get_action_badge_class(log.action)}>
                          {String.capitalize(log.action)}
                        </div>
                      </td>
                      <td class="font-mono">
                        {log.secret_key}
                      </td>
                      <td class="max-w-xs truncate">
                        {format_metadata(log.metadata)}
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
              
    <!-- Pagination -->
              <div
                :if={@pagination.total > @pagination.per_page}
                class="flex items-center justify-between mt-6"
              >
                <div class="flex-1 flex justify-between sm:hidden">
                  <button
                    :if={@pagination.page > 1}
                    phx-click="paginate"
                    phx-value-page={@pagination.page - 1}
                    class="btn btn-outline"
                  >
                    Previous
                  </button>
                  <button
                    :if={@pagination.page * @pagination.per_page < @pagination.total}
                    phx-click="paginate"
                    phx-value-page={@pagination.page + 1}
                    class="btn btn-outline"
                  >
                    Next
                  </button>
                </div>
                <div class="hidden sm:flex-1 sm:flex sm:items-center sm:justify-between">
                  <div>
                    <p class="text-sm opacity-70">
                      Showing
                      <span class="font-medium">
                        {(@pagination.page - 1) * @pagination.per_page + 1}
                      </span>
                      to
                      <span class="font-medium">
                        {min(@pagination.page * @pagination.per_page, @pagination.total)}
                      </span>
                      of <span class="font-medium">{@pagination.total}</span>
                      results
                    </p>
                  </div>
                  <div>
                    <div class="btn-group">
                      <button
                        :if={@pagination.page > 1}
                        phx-click="paginate"
                        phx-value-page={@pagination.page - 1}
                        class="btn btn-outline"
                      >
                        <.icon name="hero-chevron-left" class="h-5 w-5" />
                      </button>

                      <button
                        :if={@pagination.page * @pagination.per_page < @pagination.total}
                        phx-click="paginate"
                        phx-value-page={@pagination.page + 1}
                        class="btn btn-outline"
                      >
                        <.icon name="hero-chevron-right" class="h-5 w-5" />
                      </button>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </main>
      </div>
    </VaultLiteWeb.Layouts.app>
    """
  end
end
