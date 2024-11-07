defmodule DeployexWeb.LogsLive do
  use DeployexWeb, :live_view

  alias Deployex.Terminal
  alias DeployexWeb.Components.MultiSelect

  @impl true
  def render(assigns) do
    unselected_services_keys =
      assigns.node_info.services_keys -- assigns.node_info.selected_services_keys

    unselected_logs_keys =
      assigns.node_info.logs_keys -- assigns.node_info.selected_logs_keys

    assigns =
      assigns
      |> assign(unselected_services_keys: unselected_services_keys)
      |> assign(unselected_logs_keys: unselected_logs_keys)

    ~H"""
    <div class="min-h-screen bg-gray-500 ">
      <div class="flex">
        <MultiSelect.content
          id="log-multi-select"
          selected_text="Selected logs"
          selected={[
            %{name: "services", keys: @node_info.selected_services_keys},
            %{name: "logs", keys: @node_info.selected_logs_keys}
          ]}
          unselected={[
            %{name: "services", keys: @unselected_services_keys},
            %{name: "logs", keys: @unselected_logs_keys}
          ]}
          show_options={@show_log_options}
        />
        <button
          id="log-multi-select-reset"
          phx-click="logs-reset"
          class="phx-submit-loading:opacity-75 rounded-lg bg-cyan-500 hover:bg-cyan-900 mb-1 py-2 px-3 mt-2 mr-2 text-sm font-semibold leading-6 text-white active:text-white/80"
        >
          RESET
        </button>
      </div>
      <div class="p-2">
        <div class="bg-white w-full shadow-lg rounded">
          <.table_logs id="terminal-live-logs-table" rows={@streams.log_messages}>
            <:col :let={{_id, log_message}} label="SERVICE">
              <div class="flex">
                <div class={["w-[5px]  rounded ml-1 mr-1", log_message.color]}></div>
                <span><%= log_message.service %></span>
              </div>
            </:col>
            <:col :let={{_id, log_message}} label="TYPE">
              <%= log_message.type %>
            </:col>
            <:col :let={{_id, log_message}} label="CONTENT">
              <%= log_message.content %>
            </:col>
          </.table_logs>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) when is_connected?(socket) do
    {:ok,
     socket
     |> assign(:node_info, update_node_info())
     |> assign(:node_data, %{})
     |> assign(:current_config, %{})
     |> assign(:show_log_options, false)
     |> stream(:log_messages, [])}
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:node_info, node_info_new())
     |> assign(:node_data, %{})
     |> assign(:current_config, %{})
     |> assign(:show_log_options, false)
     |> stream(:log_messages, [])}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Live Logs")
  end

  @impl true
  def handle_event(
        "multi-select-remove-item",
        %{"item" => "services", "key" => service_key},
        %{assigns: %{node_info: node_info, current_config: current_config}} = socket
      ) do
    node_info =
      update_node_info(
        node_info.selected_services_keys -- [service_key],
        node_info.selected_logs_keys
      )

    socket =
      Enum.reduce(node_info.selected_logs_keys, socket, fn log_key, acc ->
        data_key = data_key(service_key, log_key)
        terminal_server = current_config[data_key]["terminal_server"]
        Terminal.async_terminate(terminal_server)

        acc
        |> stream(data_key, [], reset: true)
        |> update_current_config(data_key, %{
          "transition" => false,
          "terminal_server" => nil
        })
      end)

    {:noreply, assign(socket, :node_info, node_info)}
  end

  def handle_event(
        "multi-select-remove-item",
        %{"item" => "logs", "key" => log_key},
        %{assigns: %{node_info: node_info, current_config: current_config}} = socket
      ) do
    node_info =
      update_node_info(
        node_info.selected_services_keys,
        node_info.selected_logs_keys -- [log_key]
      )

    socket =
      Enum.reduce(node_info.selected_services_keys, socket, fn service_key, acc ->
        data_key = data_key(service_key, log_key)
        terminal_server = current_config[data_key]["terminal_server"]
        Terminal.async_terminate(terminal_server)

        acc
        |> stream(data_key, [], reset: true)
        |> update_current_config(data_key, %{
          "transition" => false,
          "terminal_server" => nil
        })
      end)

    {:noreply, assign(socket, :node_info, node_info)}
  end

  def handle_event(
        "multi-select-add-item",
        %{"item" => "services", "key" => service_key},
        %{assigns: %{node_info: node_info}} = socket
      ) do
    node_info =
      update_node_info(
        node_info.selected_services_keys ++ [service_key],
        node_info.selected_logs_keys
      )

    socket =
      Enum.reduce(node_info.selected_logs_keys, socket, fn log_key, acc ->
        app = Enum.find(node_info.node, &(&1.service == service_key))

        path = log_path(app.instance, log_key)

        if File.exists?(path) do
          commands = "tail -f -n 0 #{path}"
          options = [:stdout]

          {:ok, _pid} =
            Terminal.new(%Terminal{
              instance: app.instance,
              commands: commands,
              options: options,
              target: self(),
              metadata: %{context: :terminal_index, service: service_key, type: log_key}
            })
        end

        data_key = data_key(service_key, log_key)

        acc
        |> update_current_config(data_key, %{
          "transition" => false
        })
      end)

    {:noreply, assign(socket, :node_info, node_info)}
  end

  def handle_event(
        "multi-select-add-item",
        %{"item" => "logs", "key" => log_key},
        %{assigns: %{node_info: node_info}} = socket
      ) do
    node_info =
      update_node_info(
        node_info.selected_services_keys,
        node_info.selected_logs_keys ++ [log_key]
      )

    socket =
      Enum.reduce(node_info.selected_services_keys, socket, fn service_key, acc ->
        app = Enum.find(node_info.node, &(&1.service == service_key))
        path = log_path(app.instance, log_key)

        if File.exists?(path) do
          commands = "tail -f -n 0 #{path}"
          options = [:stdout]

          {:ok, _pid} =
            Terminal.new(%Terminal{
              instance: app.instance,
              commands: commands,
              options: options,
              target: self(),
              metadata: %{context: :terminal_index, service: service_key, type: log_key}
            })
        end

        data_key = data_key(service_key, log_key)

        acc
        |> update_current_config(data_key, %{
          "transition" => false
        })
      end)

    {:noreply, assign(socket, :node_info, node_info)}
  end

  def handle_event("toggle-options", _value, socket) do
    show_log_options = !socket.assigns.show_log_options

    {:noreply, socket |> assign(:show_log_options, show_log_options)}
  end

  def handle_event("logs-reset", _value, socket) do
    {:noreply, stream(socket, :log_messages, [], reset: true)}
  end

  @impl true
  def handle_info({:terminal_update, %{status: :closed}}, socket) do
    {:noreply, socket}
  end

  def handle_info(
        {:terminal_update,
         %{
           metadata: %{context: :terminal_index, service: service_key, type: log_key},
           myself: pid,
           message: ""
         }},
        socket
      ) do
    data_key = data_key(service_key, log_key)

    {:noreply, update_current_config(socket, data_key, %{"terminal_server" => pid})}
  end

  def handle_info(
        {:terminal_update,
         %{
           metadata: %{context: :terminal_index, service: service_key, type: log_key},
           myself: pid,
           message: message
         }},
        %{assigns: %{current_config: current_config}} = socket
      ) do
    data_key = data_key(service_key, log_key)
    terminal_server = current_config[data_key]["terminal_server"]

    if terminal_server == pid do
      messages =
        message
        |> String.split(["\n", "\r"], trim: true)
        |> Enum.map(fn content ->
          color = log_color(content, log_key)

          %{
            id: Deployex.Common.uuid4(),
            content: content,
            color: color,
            service: service_key,
            type: log_key
          }
        end)

      {:noreply, stream(socket, :log_messages, messages)}
    else
      {:noreply, socket}
    end
  end

  defp data_key(service, log), do: "#{service}::#{log}"

  defp update_current_config(
         %{assigns: %{current_config: current_config}} = socket,
         data_key,
         attributes
       ) do
    updated_data =
      current_config
      |> Map.get(data_key, %{})
      |> Map.merge(attributes)

    assign(socket, :current_config, Map.put(current_config, data_key, updated_data))
  end

  defp node_info_new do
    %{
      services_keys: [],
      logs_keys: ["stdout", "stderr"],
      selected_services_keys: [],
      selected_logs_keys: [],
      node: []
    }
  end

  defp update_node_info, do: update_node_info([], [])

  defp update_node_info(selected_services_keys, selected_logs_keys) do
    initial_map =
      %{
        node_info_new()
        | selected_services_keys: selected_services_keys,
          selected_logs_keys: selected_logs_keys
      }

    {:ok, hostname} = :inet.gethostname()

    Deployex.Storage.instance_list()
    |> Enum.reduce(initial_map, fn instance,
                                   %{
                                     services_keys: services_keys,
                                     logs_keys: logs_keys,
                                     node: node
                                   } = acc ->
      sname = Deployex.Storage.sname(instance)
      service = "#{sname}@#{hostname}"
      services_keys = services_keys ++ [service]

      node =
        if service in selected_services_keys do
          [
            %{
              sname: sname,
              instance: instance,
              logs_keys: logs_keys,
              service: service
            }
            | node
          ]
        else
          node
        end

      %{acc | services_keys: services_keys, logs_keys: logs_keys, node: node}
    end)
  end

  defp log_path(instance, "stdout") do
    instance
    |> Deployex.Storage.stdout_path()
  end

  defp log_path(instance, "stderr") do
    instance
    |> Deployex.Storage.stderr_path()
  end

  defp log_color(_message, "stderr"), do: "bg-red-500"

  defp log_color(message, _log_type) do
    cond do
      String.contains?(message, ["debug", "DEBUG"]) ->
        "bg-gray-300"

      String.contains?(message, ["info", "INFO"]) ->
        "bg-blue-300"

      String.contains?(message, ["warning", "WARNING"]) ->
        "bg-yellow-400"

      String.contains?(message, ["error", "ERROR", "SIGTERM"]) ->
        "bg-red-500"

      String.contains?(message, ["notice", "NOTICE"]) ->
        "bg-orange-300"

      true ->
        "bg-gray-300"
    end
  end
end
