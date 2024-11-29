defmodule DeployexWeb.TracingLive do
  use DeployexWeb, :live_view

  require Logger

  alias Deployex.Tracer, as: DeployexT
  alias DeployexWeb.Components.MultiSelectList

  @impl true
  def render(assigns) do
    unselected_services_keys =
      assigns.node_info.services_keys -- assigns.node_info.selected_services_keys

    unselected_modules_keys =
      assigns.node_info.modules_keys -- assigns.node_info.selected_modules_keys

    unselected_functions_keys =
      assigns.node_info.functions_keys -- assigns.node_info.selected_functions_keys

    trace_state = DeployexT.state()

    trace_idle? = trace_state.status == :idle
    trace_owner? = trace_state.session_id == assigns.trace_session_id

    show_tracing_options = trace_idle? and trace_owner? and assigns.show_tracing_options

    assigns =
      assigns
      |> assign(unselected_services_keys: unselected_services_keys)
      |> assign(unselected_modules_keys: unselected_modules_keys)
      |> assign(unselected_functions_keys: unselected_functions_keys)
      |> assign(trace_idle?: trace_idle?)
      |> assign(trace_owner?: trace_owner?)
      |> assign(show_tracing_options: show_tracing_options)

    ~H"""
    <div class="min-h-screen bg-white">
      <div class="flex">
        <MultiSelectList.content
          id="tracing-multi-select"
          selected_text="Selected Items"
          selected={[
            %{name: "services", keys: @node_info.selected_services_keys},
            %{name: "modules", keys: @node_info.selected_modules_keys},
            %{name: "functions", keys: @node_info.selected_functions_keys}
          ]}
          unselected={[
            %{name: "services", keys: @unselected_services_keys},
            %{name: "modules", keys: @unselected_modules_keys},
            %{name: "functions", keys: @unselected_functions_keys}
          ]}
          show_options={@show_tracing_options}
        />
        <button
          :if={@trace_idle? and @trace_owner?}
          id="tracing-multi-select-run"
          phx-click="tracing-apps-run"
          class="phx-submit-loading:opacity-75 rounded-lg bg-cyan-500 transform active:scale-75 transition-transform hover:bg-cyan-900 mb-1 py-2 px-3 mt-2 mr-2 text-sm font-semibold leading-6 text-white active:text-white/80"
        >
          Run
        </button>

        <button
          :if={@trace_idle? == false and @trace_owner?}
          id="tracing-multi-select-stop"
          phx-click="tracing-apps-stop"
          class="phx-submit-loading:opacity-75 rounded-lg bg-red-500 transform active:scale-75 transition-transform hover:bg-cyan-900 mb-1 py-2 px-3 mt-2 mr-2 text-sm font-semibold leading-6 text-white active:text-white/80"
        >
          Stop
        </button>
      </div>
      <div class="p-2">
        <div class="bg-white w-full shadow-lg rounded">
          <.table_logs id="live-logs" h_max_size="max-h-[400px]" rows={@streams.tracing_messages}>
            <:col :let={{_id, tracing_message}} label="SERVICE">
              <span><%= tracing_message.service %></span>
            </:col>
            <:col :let={{_id, tracing_message}} label="CONTENT">
              <%= tracing_message.content %>
            </:col>
          </.table_logs>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) when is_connected?(socket) do
    # Subscribe to notifications if any node is UP or Down
    :net_kernel.monitor_nodes(true)

    {:ok,
     socket
     |> assign(:node_info, update_node_info())
     |> assign(:node_data, %{})
     |> assign(:trace_session_id, nil)
     |> assign(:show_tracing_options, false)
     |> stream(:tracing_messages, [])}
  end

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:node_info, node_info_new())
     |> assign(:node_data, %{})
     |> assign(:trace_session_id, nil)
     |> assign(:show_tracing_options, false)
     |> stream(:tracing_messages, [])}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Live Tracing")
  end

  @impl true
  def handle_event("toggle-options", _value, socket) do
    show_tracing_options = !socket.assigns.show_tracing_options

    {:noreply, socket |> assign(:show_tracing_options, show_tracing_options)}
  end

  def handle_event(
        "tracing-apps-stop",
        _data,
        %{assigns: %{trace_session_id: trace_session_id}} = socket
      ) do
    DeployexT.stop_trace(trace_session_id)
    {:noreply, assign(socket, :trace_session_id, nil)}
  end

  def handle_event("tracing-apps-run", _data, %{assigns: %{node_info: node_info}} = socket) do
    tracer_state = DeployexT.state()

    if tracer_state.status == :idle do
      functions_to_monitor =
        Enum.reduce(node_info.selected_services_keys, [], fn service_key, service_acc ->
          service_info = Enum.find(node_info.node, &(&1.service == service_key))

          service_acc ++
            Enum.reduce(node_info.selected_modules_keys, [], fn module_key, module_acc ->
              module_key_atom = String.to_existing_atom(module_key)

              node_functions_info =
                Enum.find(service_info.functions, &(&1.module == module_key_atom))

              functions =
                Enum.reduce(node_info.selected_functions_keys, [], fn function_key,
                                                                      function_acc ->
                  function = Map.get(node_functions_info.functions, function_key, nil)

                  if module_key in service_info.modules_keys and function do
                    function_acc ++
                      [
                        %{
                          node: String.to_existing_atom(service_key),
                          module: module_key_atom,
                          function: function.name,
                          arity: function.arity
                        }
                      ]
                  else
                    function_acc
                  end
                end)

              # If the module doesn't have any of the requested functions the default is to
              # include the whole module
              if functions == [] do
                module_acc ++
                  [
                    %{
                      node: String.to_existing_atom(service_key),
                      module: module_key_atom,
                      function: :_,
                      arity: :_
                    }
                  ]
              else
                module_acc ++ functions
              end
            end)
        end)

      case DeployexT.start_trace(functions_to_monitor) do
        {:ok, %{session_id: session_id}} ->
          {:noreply,
           socket
           |> assign(:trace_session_id, session_id)
           |> stream(:tracing_messages, [], reset: true)}

        {:error, _} ->
          {:noreply, assign(socket, :trace_session_id, nil)}
      end
    else
      {:noreply, assign(socket, :trace_session_id, nil)}
    end
  end

  def handle_event(
        "multi-select-remove-item",
        %{"item" => "services", "key" => service_key},
        %{assigns: %{node_info: node_info}} = socket
      ) do
    node_info =
      update_node_info(
        node_info.selected_services_keys -- [service_key],
        node_info.selected_modules_keys,
        node_info.selected_functions_keys
      )

    {:noreply,
     socket
     |> assign(:node_info, node_info)}
  end

  def handle_event(
        "multi-select-remove-item",
        %{"item" => "modules", "key" => module_key},
        %{assigns: %{node_info: node_info}} = socket
      ) do
    node_info =
      update_node_info(
        node_info.selected_services_keys,
        node_info.selected_modules_keys -- [module_key],
        node_info.selected_functions_keys
      )

    {:noreply,
     socket
     |> assign(:node_info, node_info)}
  end

  def handle_event(
        "multi-select-remove-item",
        %{"item" => "functions", "key" => function_key},
        %{assigns: %{node_info: node_info}} = socket
      ) do
    node_info =
      update_node_info(
        node_info.selected_services_keys,
        node_info.selected_modules_keys,
        node_info.selected_functions_keys -- [function_key]
      )

    {:noreply,
     socket
     |> assign(:node_info, node_info)}
  end

  def handle_event(
        "multi-select-add-item",
        %{"item" => "services", "key" => service_key},
        %{assigns: %{node_info: node_info}} = socket
      ) do
    node_info =
      update_node_info(
        node_info.selected_services_keys ++ [service_key],
        node_info.selected_modules_keys,
        node_info.selected_functions_keys
      )

    {:noreply,
     socket
     |> assign(:node_info, node_info)}
  end

  def handle_event(
        "multi-select-add-item",
        %{"item" => "modules", "key" => module_key},
        %{assigns: %{node_info: node_info}} = socket
      ) do
    node_info =
      update_node_info(
        node_info.selected_services_keys,
        node_info.selected_modules_keys ++ [module_key],
        node_info.selected_functions_keys
      )

    {:noreply,
     socket
     |> assign(:node_info, node_info)}
  end

  def handle_event(
        "multi-select-add-item",
        %{"item" => "functions", "key" => function_key},
        %{assigns: %{node_info: node_info}} = socket
      ) do
    node_info =
      update_node_info(
        node_info.selected_services_keys,
        node_info.selected_modules_keys,
        node_info.selected_functions_keys ++ [function_key]
      )

    {:noreply,
     socket
     |> assign(:node_info, node_info)}
  end

  @impl true
  def handle_info({:nodeup, _node}, %{assigns: %{node_info: node_info}} = socket) do
    node_info =
      update_node_info(
        node_info.selected_services_keys,
        node_info.selected_modules_keys,
        node_info.selected_functions_keys
      )

    {:noreply, assign(socket, :node_info, node_info)}
  end

  def handle_info({:nodedown, node}, %{assigns: %{node_info: node_info}} = socket) do
    service_key = node |> to_string

    node_info =
      update_node_info(
        node_info.selected_services_keys -- [service_key],
        node_info.selected_modules_keys,
        node_info.selected_functions_keys
      )

    {:noreply,
     socket
     |> assign(:node_info, node_info)}
  end

  def handle_info({:new_trace_message, _session_id, node, index, message}, socket) do
    Logger.info("Message: #{node} - [#{index}] :: #{message}")

    data = %{
      service: node,
      id: Deployex.Common.uuid4(),
      content: message
    }

    {:noreply, stream(socket, :tracing_messages, [data])}
  end

  def handle_info({event, _session_id}, socket)
      when event in [:trace_session_timeout, :stop_tracing] do
    {:noreply,
     socket
     |> assign(:trace_session_id, nil)
     |> assign(:show_tracing_options, false)}
  end

  defp node_info_new do
    %{
      services_keys: [],
      modules_keys: [],
      functions_keys: [],
      selected_services_keys: [],
      selected_modules_keys: [],
      selected_functions_keys: [],
      node: []
    }
  end

  defp update_node_info, do: update_node_info([], [], [])

  defp update_node_info(selected_services_keys, selected_modules_keys, selected_functions_keys) do
    initial_map =
      %{
        node_info_new()
        | selected_services_keys: selected_services_keys,
          selected_modules_keys: selected_modules_keys,
          selected_functions_keys: selected_functions_keys
      }

    Enum.reduce(Node.list() ++ [Node.self()], initial_map, fn instance_node,
                                                              %{
                                                                services_keys: services_keys,
                                                                modules_keys: modules_keys,
                                                                functions_keys: functions_keys,
                                                                node: node
                                                              } = acc ->
      service = instance_node |> to_string
      service_selected? = service in selected_services_keys

      [name, _hostname] = String.split(service, "@")
      services_keys = (services_keys ++ [service]) |> Enum.sort()

      instance_module_keys =
        if service_selected? do
          DeployexT.get_modules(instance_node) |> Enum.map(&to_string/1)
        else
          []
        end

      {instance_functions_keys, functions} =
        Enum.reduce(instance_module_keys, {[], []}, fn module, {keys, fun} ->
          if module in selected_modules_keys do
            module_functions_info =
              DeployexT.get_module_functions_info(instance_node, String.to_existing_atom(module))

            function_keys = Map.keys(module_functions_info.functions) |> Enum.map(&to_string/1)
            {keys ++ function_keys, fun ++ [module_functions_info]}
          else
            {keys, fun}
          end
        end)

      modules_keys = (modules_keys ++ instance_module_keys) |> Enum.sort() |> Enum.uniq()
      functions_keys = (functions_keys ++ instance_functions_keys) |> Enum.sort() |> Enum.uniq()

      node =
        if service_selected? do
          [
            %{
              name: name,
              modules_keys: instance_module_keys,
              function_keys: instance_functions_keys,
              service: service,
              functions: functions
            }
            | node
          ]
        else
          node
        end

      %{
        acc
        | services_keys: services_keys,
          modules_keys: modules_keys,
          functions_keys: functions_keys,
          node: node
      }
    end)
  end
end
