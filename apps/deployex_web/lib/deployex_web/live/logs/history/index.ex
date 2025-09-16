defmodule DeployexWeb.HistoryLive do
  use DeployexWeb, :live_view

  alias Deployer.Monitor
  alias DeployexWeb.Components.MultiSelect
  alias DeployexWeb.Helper
  alias Sentinel.Logs

  @impl true
  def render(assigns) do
    unselected_services =
      assigns.node_info.services_keys -- assigns.node_info.selected_services

    unselected_logs =
      assigns.node_info.logs_keys -- assigns.node_info.selected_logs

    attention_msg = ""

    assigns =
      assigns
      |> assign(unselected_services: unselected_services)
      |> assign(unselected_logs: unselected_logs)
      |> assign(attention_msg: attention_msg)
      |> assign(services_unselected_highlight: Monitor.list() ++ [Helper.self_sname()])

    ~H"""
    <Layouts.app flash={@flash} ui_settings={@ui_settings} current_path={@current_path}>
      <div class="min-h-screen bg-base-300">
        <!-- Header -->
        <div class="bg-base-100 border-b border-base-200 shadow-sm">
          <div class="max-w-7xl mx-auto px-4 py-4">
            <div class="flex items-center justify-between">
              <div>
                <h1 class="text-3xl font-bold text-base-content">History Logs</h1>
                <p class="text-base-content/60 mt-1">Browse historical application logs</p>
              </div>
              <div class="flex items-center gap-4">
                <!-- Time Range Selector -->
                <div class="dropdown dropdown-end">
                  <div tabindex="0" role="button" class="btn btn-outline btn-sm gap-2">
                    <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        stroke-width="2"
                        d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"
                      >
                      </path>
                    </svg>
                    Time Range: {@form.params["start_time"] || "5m"}
                    <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        stroke-width="2"
                        d="M19 9l-7 7-7-7"
                      >
                      </path>
                    </svg>
                  </div>
                  <ul
                    tabindex="0"
                    class="dropdown-content menu bg-base-100 rounded-box z-[1] w-52 p-2 shadow-lg border border-base-200"
                  >
                    <.form
                      for={@form}
                      id="logs-history-update-form"
                      phx-change="form-update"
                      class="contents"
                    >
                      <li :for={option <- ["1m", "5m", "15m", "30m", "1h"]}>
                        <label class="label cursor-pointer justify-start gap-3">
                          <input
                            type="radio"
                            name="start_time"
                            value={option}
                            checked={@form.params["start_time"] == option}
                            class="radio radio-primary radio-sm"
                          />
                          <span class="label-text">{option}</span>
                        </label>
                      </li>
                    </.form>
                  </ul>
                </div>
              </div>
            </div>
          </div>
        </div>
        <!-- Main Content -->
        <div class="max-w-8xl mx-auto px-3 py-3">
          <!-- Filters Card -->
          <div class="card bg-base-100 shadow-sm mb-6">
            <div class="card-body p-6">
              <h2 class="card-title text-lg mb-4">Log Filters</h2>
              <MultiSelect.content
                id="logs-history-multi-select"
                selected_text="Selected logs"
                selected={[
                  %{name: "services", keys: @node_info.selected_services},
                  %{name: "logs", keys: @node_info.selected_logs}
                ]}
                unselected={[
                  %{
                    name: "services",
                    keys: @unselected_services,
                    unselected_highlight: @services_unselected_highlight
                  },
                  %{name: "logs", keys: @unselected_logs, unselected_highlight: []}
                ]}
                show_options={@show_log_options}
              />
            </div>
          </div>
          <!-- Statistics Card -->
          <div :if={length(@log_messages) > 0} class="stats shadow mb-6">
            <div class="stat">
              <div class="stat-figure text-primary">
                <svg class="w-8 h-8" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"
                  >
                  </path>
                </svg>
              </div>
              <div class="stat-title">Total Logs</div>
              <div class="stat-value text-primary">{length(@log_messages)}</div>
              <div class="stat-desc">Historical log entries</div>
            </div>

            <div class="stat">
              <div class="stat-figure text-secondary">
                <svg class="w-8 h-8" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M19 21V5a2 2 0 00-2-2H7a2 2 0 00-2 2v16m14 0h2m-2 0h-5m-9 0H3m2 0h5M9 7h1m-1 4h1m4-4h1m-1 4h1m-5 10v-5a1 1 0 011-1h2a1 1 0 011 1v5m-4 0h4"
                  >
                  </path>
                </svg>
              </div>
              <div class="stat-title">Services</div>
              <div class="stat-value text-secondary">{length(@node_info.selected_services)}</div>
              <div class="stat-desc">Active services</div>
            </div>

            <div class="stat">
              <div class="stat-figure text-accent">
                <svg class="w-8 h-8" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"
                  >
                  </path>
                </svg>
              </div>
              <div class="stat-title">Time Range</div>
              <div class="stat-value text-accent">{@form.params["start_time"] || "5m"}</div>
              <div class="stat-desc">Looking back</div>
            </div>
          </div>
          <!-- Logs Display Card -->
          <div class="card bg-base-100 shadow-sm">
            <div class="card-body p-0">
              <div :if={length(@log_messages) == 0} class="p-12 text-center">
                <div class="flex flex-col items-center gap-4">
                  <svg
                    class="w-16 h-16 text-base-content/30"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"
                    >
                    </path>
                  </svg>
                  <div>
                    <h3 class="text-lg font-semibold text-base-content/70">No logs found</h3>
                    <p class="text-base-content/50 mt-1">
                      Try selecting different services or extending the time range
                    </p>
                  </div>
                </div>
              </div>
              <div :if={length(@log_messages) > 0} class="overflow-x-auto">
                <.modern_history_logs_table id="logs-history-table" rows={@log_messages} />
              </div>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) when is_connected?(socket) do
    {:ok,
     socket
     |> assign(:node_info, update_node_info())
     |> assign(form: to_form(default_form_options()))
     |> assign(:log_messages, [])
     |> assign(:show_log_options, false)
     |> assign(:current_path, "/logs/history")}
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:node_info, node_info_new())
     |> assign(form: to_form(default_form_options()))
     |> assign(:log_messages, [])
     |> assign(:show_log_options, false)
     |> assign(:current_path, "/logs/history")}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "History Logs")
  end

  @impl true
  def handle_event(
        "multi-select-remove-item",
        %{"item" => "services", "key" => service},
        %{assigns: %{node_info: node_info, form: form}} = socket
      ) do
    node_info =
      update_node_info(
        node_info.selected_services -- [service],
        node_info.selected_logs
      )

    start_time_integer = start_time_to_integer(form.params["start_time"])

    log_messages = update_log_messages(node_info, start_time_integer)

    {:noreply,
     socket
     |> assign(:node_info, node_info)
     |> assign(:log_messages, log_messages)}
  end

  def handle_event(
        "multi-select-remove-item",
        %{"item" => "logs", "key" => log},
        %{assigns: %{node_info: node_info, form: form}} = socket
      ) do
    node_info =
      update_node_info(
        node_info.selected_services,
        node_info.selected_logs -- [log]
      )

    start_time_integer = start_time_to_integer(form.params["start_time"])

    log_messages = update_log_messages(node_info, start_time_integer)

    {:noreply,
     socket
     |> assign(:node_info, node_info)
     |> assign(:log_messages, log_messages)}
  end

  def handle_event(
        "multi-select-add-item",
        %{"item" => "services", "key" => service},
        %{assigns: %{node_info: node_info, form: form}} = socket
      ) do
    node_info =
      update_node_info(
        node_info.selected_services ++ [service],
        node_info.selected_logs
      )

    start_time_integer = start_time_to_integer(form.params["start_time"])

    log_messages = update_log_messages(node_info, start_time_integer)

    {:noreply,
     socket
     |> assign(:node_info, node_info)
     |> assign(:log_messages, log_messages)}
  end

  def handle_event(
        "multi-select-add-item",
        %{"item" => "logs", "key" => log},
        %{assigns: %{node_info: node_info, form: form}} = socket
      ) do
    node_info =
      update_node_info(
        node_info.selected_services,
        node_info.selected_logs ++ [log]
      )

    start_time_integer = start_time_to_integer(form.params["start_time"])

    log_messages = update_log_messages(node_info, start_time_integer)

    {:noreply,
     socket
     |> assign(:node_info, node_info)
     |> assign(:log_messages, log_messages)}
  end

  def handle_event("toggle-options", _value, socket) do
    show_log_options = !socket.assigns.show_log_options

    {:noreply, socket |> assign(:show_log_options, show_log_options)}
  end

  def handle_event(
        "form-update",
        %{"start_time" => start_time},
        %{assigns: %{node_info: node_info}} = socket
      ) do
    start_time_integer = start_time_to_integer(start_time)

    log_messages = update_log_messages(node_info, start_time_integer)

    {:noreply,
     socket
     |> assign(form: to_form(%{"start_time" => start_time}))
     |> assign(:log_messages, log_messages)}
  end

  defp update_log_messages(node_info, start_time_integer) do
    Enum.reduce(node_info.selected_services, [], fn service, service_acc ->
      service_acc ++
        Enum.reduce(node_info.selected_logs, [], fn log, log_acc ->
          log_history = Logs.list_data_by_sname_log_type(service, log, from: start_time_integer)

          log_acc ++ Helper.normalize_logs(log_history, service, log)
        end)
    end)
    |> Enum.sort(&(&1.timestamp <= &2.timestamp))
  end

  defp node_info_new do
    %{
      services_keys: [],
      logs_keys: [],
      selected_services: [],
      selected_logs: [],
      sname: []
    }
  end

  defp update_node_info, do: update_node_info([], [])

  defp update_node_info(selected_services, selected_logs) do
    initial_map =
      %{
        node_info_new()
        | selected_services: selected_services,
          selected_logs: selected_logs
      }

    Logs.list_active_snames()
    |> Enum.reduce(initial_map, fn service,
                                   %{
                                     services_keys: services_keys,
                                     logs_keys: logs_keys,
                                     sname: sname
                                   } = acc ->
      sname_logs_keys = Logs.get_types_by_sname(service)
      logs_keys = (logs_keys ++ sname_logs_keys) |> Enum.uniq()

      service = to_string(service)
      services_keys = (services_keys ++ [service]) |> Enum.uniq()

      sname =
        if service in selected_services do
          [
            %{
              logs_keys: logs_keys,
              service: service
            }
            | sname
          ]
        else
          sname
        end

      %{acc | services_keys: services_keys, logs_keys: logs_keys, sname: sname}
    end)
  end

  defp default_form_options, do: %{"num_cols" => "2", "start_time" => "5m"}

  defp start_time_to_integer("1m"), do: 1
  defp start_time_to_integer("5m"), do: 5
  defp start_time_to_integer("15m"), do: 15
  defp start_time_to_integer("30m"), do: 30
  defp start_time_to_integer("1h"), do: 60
end
