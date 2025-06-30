defmodule VaultLiteWeb.AdminLive.AuditLogLive do
  @moduledoc """
  This module is responsible for the audit log live view.
  - displays the audit logs and allows the user to filter and search through them.
  - displays the statistics of the audit logs.
  """
  use VaultLiteWeb, :live_view

  alias VaultLite.{Audit, User, Auth}

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

  defp action_badge_class(action) do
    case action do
      "create" -> "bg-green-100 text-green-800"
      "read" -> "bg-blue-100 text-blue-800"
      "update" -> "bg-yellow-100 text-yellow-800"
      "delete" -> "bg-red-100 text-red-800"
      "list" -> "bg-gray-100 text-gray-800"
      _ -> "bg-gray-100 text-gray-800"
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
      <main class="max-w-7xl mx-auto py-6 px-4 sm:px-6 lg:px-8">
        <!-- Page Header -->
        <div class="md:flex md:items-center md:justify-between">
          <div class="flex-1 min-w-0">
            <h2 class="text-2xl font-bold leading-7 text-gray-900 sm:text-3xl sm:truncate">
              Audit Logs
            </h2>
            <p class="mt-1 text-sm text-gray-500">
              Monitor and review all system activities
            </p>
          </div>
          <div class="mt-4 flex md:mt-0 md:ml-4">
            <button
              phx-click="refresh"
              class="inline-flex items-center px-4 py-2 border border-gray-300 rounded-md shadow-sm text-sm font-medium text-gray-700 bg-white hover:bg-gray-50"
            >
              <.icon name="hero-arrow-path" class="h-4 w-4 mr-2" /> Refresh
            </button>
          </div>
        </div>
        
    <!-- Statistics Cards -->
        <div class="mt-6 grid grid-cols-1 gap-5 sm:grid-cols-2 lg:grid-cols-4">
          <div class="bg-white overflow-hidden shadow rounded-lg">
            <div class="p-5">
              <div class="flex items-center">
                <div class="flex-shrink-0">
                  <.icon name="hero-document-text" class="h-6 w-6 text-gray-400" />
                </div>
                <div class="ml-5 w-0 flex-1">
                  <dl>
                    <dt class="text-sm font-medium text-gray-500 truncate">Total Logs</dt>
                    <dd class="text-lg font-medium text-gray-900">
                      {Map.get(@statistics, :total_logs, 0)}
                    </dd>
                  </dl>
                </div>
              </div>
            </div>
          </div>

          <div class="bg-white overflow-hidden shadow rounded-lg">
            <div class="p-5">
              <div class="flex items-center">
                <div class="flex-shrink-0">
                  <.icon name="hero-users" class="h-6 w-6 text-gray-400" />
                </div>
                <div class="ml-5 w-0 flex-1">
                  <dl>
                    <dt class="text-sm font-medium text-gray-500 truncate">Active Users</dt>
                    <dd class="text-lg font-medium text-gray-900">
                      {Map.get(@statistics, :active_users, 0)}
                    </dd>
                  </dl>
                </div>
              </div>
            </div>
          </div>

          <div class="bg-white overflow-hidden shadow rounded-lg">
            <div class="p-5">
              <div class="flex items-center">
                <div class="flex-shrink-0">
                  <.icon name="hero-key" class="h-6 w-6 text-gray-400" />
                </div>
                <div class="ml-5 w-0 flex-1">
                  <dl>
                    <dt class="text-sm font-medium text-gray-500 truncate">Top Secret</dt>
                    <dd class="text-lg font-medium text-gray-900">
                      {case Map.get(@statistics, :top_secrets, []) do
                        [] -> "None"
                        [top | _] -> top.secret_key
                      end}
                    </dd>
                  </dl>
                </div>
              </div>
            </div>
          </div>

          <div class="bg-white overflow-hidden shadow rounded-lg">
            <div class="p-5">
              <div class="flex items-center">
                <div class="flex-shrink-0">
                  <.icon name="hero-chart-bar" class="h-6 w-6 text-gray-400" />
                </div>
                <div class="ml-5 w-0 flex-1">
                  <dl>
                    <dt class="text-sm font-medium text-gray-500 truncate">Most Common Action</dt>
                    <dd class="text-lg font-medium text-gray-900">
                      {case Map.get(@statistics, :actions, %{}) do
                        actions when map_size(actions) == 0 ->
                          "None"

                        actions ->
                          {action, _count} = Enum.max_by(actions, fn {_k, v} -> v end)
                          String.capitalize(action)
                      end}
                    </dd>
                  </dl>
                </div>
              </div>
            </div>
          </div>
        </div>
        
    <!-- Search and Filters -->
        <div class="mt-6 bg-white shadow rounded-lg">
          <div class="px-4 py-5 sm:p-6">
            <h3 class="text-lg font-medium text-gray-900 mb-4">Search & Filters</h3>
            
    <!-- Search Bar -->
            <div class="mb-4">
              <.form for={%{}} as={:search} phx-submit="search" class="flex">
                <input
                  type="text"
                  name="search[query]"
                  value={@search_query}
                  placeholder="Search by secret key..."
                  class="flex-1 border-gray-300 rounded-l-md shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                />
                <button
                  type="submit"
                  class="px-4 py-2 bg-indigo-600 text-white rounded-r-md hover:bg-indigo-700"
                >
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
              <div>
                <label class="block text-sm font-medium text-gray-700">Action</label>
                <select
                  name="filter[action]"
                  class="mt-1 block w-full border-gray-300 rounded-md shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                >
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

              <div>
                <label class="block text-sm font-medium text-gray-700">User ID</label>
                <input
                  type="number"
                  name="filter[user_id]"
                  value={Map.get(@filters, :user_id, "")}
                  placeholder="User ID"
                  class="mt-1 block w-full border-gray-300 rounded-md shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                />
              </div>

              <div>
                <label class="block text-sm font-medium text-gray-700">Secret Key</label>
                <input
                  type="text"
                  name="filter[secret_key]"
                  value={Map.get(@filters, :secret_key, "")}
                  placeholder="Secret key"
                  class="mt-1 block w-full border-gray-300 rounded-md shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                />
              </div>

              <div>
                <label class="block text-sm font-medium text-gray-700">Start Date</label>
                <input
                  type="date"
                  name="filter[start_date]"
                  value={
                    case Map.get(@filters, :start_date) do
                      nil -> ""
                      date -> Date.to_iso8601(DateTime.to_date(date))
                    end
                  }
                  class="mt-1 block w-full border-gray-300 rounded-md shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                />
              </div>

              <div>
                <label class="block text-sm font-medium text-gray-700">End Date</label>
                <input
                  type="date"
                  name="filter[end_date]"
                  value={
                    case Map.get(@filters, :end_date) do
                      nil -> ""
                      date -> Date.to_iso8601(DateTime.to_date(date))
                    end
                  }
                  class="mt-1 block w-full border-gray-300 rounded-md shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                />
              </div>

              <div class="sm:col-span-2 lg:col-span-5 flex space-x-3">
                <button
                  type="submit"
                  class="inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md shadow-sm text-white bg-indigo-600 hover:bg-indigo-700"
                >
                  Apply Filters
                </button>
                <button
                  type="button"
                  phx-click="clear_filters"
                  class="inline-flex items-center px-4 py-2 border border-gray-300 text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50"
                >
                  Clear Filters
                </button>
              </div>
            </.form>
          </div>
        </div>
        
    <!-- Audit Logs Table -->
        <div class="mt-6 bg-white shadow rounded-lg overflow-hidden">
          <div class="px-4 py-5 sm:p-6">
            <div class="flex justify-between items-center mb-4">
              <h3 class="text-lg font-medium text-gray-900">Audit Logs</h3>
              <span class="text-sm text-gray-500">
                {length(@audit_logs)} of {@pagination.total} entries
              </span>
            </div>

            <div :if={@loading} class="text-center py-8">
              <div class="inline-block animate-spin rounded-full h-8 w-8 border-b-2 border-indigo-600">
              </div>
              <p class="mt-2 text-sm text-gray-500">Loading audit logs...</p>
            </div>

            <div :if={!@loading and length(@audit_logs) == 0} class="text-center py-8">
              <.icon name="hero-document-text" class="mx-auto h-12 w-12 text-gray-400" />
              <h3 class="mt-2 text-sm font-medium text-gray-900">No audit logs found</h3>
              <p class="mt-1 text-sm text-gray-500">
                Try adjusting your search criteria or filters.
              </p>
            </div>

            <div :if={!@loading and length(@audit_logs) > 0} class="overflow-x-auto">
              <table class="min-w-full divide-y divide-gray-200">
                <thead class="bg-gray-50">
                  <tr>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                      Timestamp
                    </th>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                      User
                    </th>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                      Action
                    </th>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                      Secret Key
                    </th>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                      Metadata
                    </th>
                  </tr>
                </thead>
                <tbody class="bg-white divide-y divide-gray-200">
                  <tr :for={log <- @audit_logs} class="hover:bg-gray-50">
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                      {format_timestamp(log.timestamp)}
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                      {log.user_id || "System"}
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap">
                      <span class={"inline-flex px-2 py-1 text-xs font-medium rounded-full #{action_badge_class(log.action)}"}>
                        {String.capitalize(log.action)}
                      </span>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900 font-mono">
                      {log.secret_key}
                    </td>
                    <td class="px-6 py-4 text-sm text-gray-500 max-w-xs truncate">
                      {format_metadata(log.metadata)}
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
            
    <!-- Pagination -->
            <div
              :if={@pagination.total > @pagination.per_page}
              class="mt-6 flex items-center justify-between"
            >
              <div class="flex-1 flex justify-between sm:hidden">
                <button
                  :if={@pagination.page > 1}
                  phx-click="paginate"
                  phx-value-page={@pagination.page - 1}
                  class="relative inline-flex items-center px-4 py-2 border border-gray-300 text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50"
                >
                  Previous
                </button>
                <button
                  :if={@pagination.page * @pagination.per_page < @pagination.total}
                  phx-click="paginate"
                  phx-value-page={@pagination.page + 1}
                  class="ml-3 relative inline-flex items-center px-4 py-2 border border-gray-300 text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50"
                >
                  Next
                </button>
              </div>
              <div class="hidden sm:flex-1 sm:flex sm:items-center sm:justify-between">
                <div>
                  <p class="text-sm text-gray-700">
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
                  <nav class="relative z-0 inline-flex rounded-md shadow-sm -space-x-px">
                    <button
                      :if={@pagination.page > 1}
                      phx-click="paginate"
                      phx-value-page={@pagination.page - 1}
                      class="relative inline-flex items-center px-2 py-2 rounded-l-md border border-gray-300 bg-white text-sm font-medium text-gray-500 hover:bg-gray-50"
                    >
                      <.icon name="hero-chevron-left" class="h-5 w-5" />
                    </button>

                    <button
                      :if={@pagination.page * @pagination.per_page < @pagination.total}
                      phx-click="paginate"
                      phx-value-page={@pagination.page + 1}
                      class="relative inline-flex items-center px-2 py-2 rounded-r-md border border-gray-300 bg-white text-sm font-medium text-gray-500 hover:bg-gray-50"
                    >
                      <.icon name="hero-chevron-right" class="h-5 w-5" />
                    </button>
                  </nav>
                </div>
              </div>
            </div>
          </div>
        </div>
      </main>
    </div>
    """
  end
end
