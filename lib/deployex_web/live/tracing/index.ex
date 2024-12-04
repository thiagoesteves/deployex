defmodule DeployexWeb.TracingLive do
  use DeployexWeb, :live_view

  require Logger

  alias Deployex.Tracer, as: DeployexT
  alias DeployexWeb.Components.MultiSelectList

  @default_max_messages "3"
  @default_session_timeout_seconds "30"

  @impl true
  def render(assigns) do
    unselected_services_keys =
      assigns.node_info.services_keys -- assigns.node_info.selected_services_keys

    unselected_modules_keys =
      assigns.node_info.modules_keys -- assigns.node_info.selected_modules_keys

    unselected_functions_keys =
      assigns.node_info.functions_keys -- assigns.node_info.selected_functions_keys

    unselected_match_spec_keys =
      assigns.node_info.match_spec_keys -- assigns.node_info.selected_match_spec_keys

    trace_state = DeployexT.state()

    trace_idle? = trace_state.status == :idle
    trace_owner? = trace_state.session_id == assigns.trace_session_id

    # Hide options when running
    show_tracing_options = trace_idle? and trace_owner? and assigns.show_tracing_options

    match_spec_info = ~H"""
    <a
      href="https://www.erlang.org/docs/24/apps/erts/match_spec"
      class="font-medium text-blue-600 underline dark:text-blue-500 hover:no-underline"
    >
      (more_info)
    </a>
    """

    assigns =
      assigns
      |> assign(unselected_services_keys: unselected_services_keys)
      |> assign(unselected_modules_keys: unselected_modules_keys)
      |> assign(unselected_functions_keys: unselected_functions_keys)
      |> assign(unselected_match_spec_keys: unselected_match_spec_keys)
      |> assign(match_spec_info: match_spec_info)
      |> assign(trace_idle?: trace_idle?)
      |> assign(trace_idle?: trace_idle?)
      |> assign(trace_owner?: trace_owner?)
      |> assign(show_tracing_options: show_tracing_options)

    ~H"""
    <div class="min-h-screen bg-white">
      <div class="flex items-center mt-1">
        <div
          id="live-tracing-alert"
          class="p-2 border-l-8 border-red-400 rounded-l-lg bg-gray-300 text-red-500"
          role="alert"
        >
          <div class="flex items-center">
            <div class="flex items-center py-8">
              <svg
                class="flex-shrink-0 w-4 h-4 me-2"
                aria-hidden="true"
                xmlns="http://www.w3.org/2000/svg"
                fill="currentColor"
                viewBox="0 0 20 20"
              >
                <path d="M10 .5a9.5 9.5 0 1 0 9.5 9.5A9.51 9.51 0 0 0 10 .5ZM9.5 4a1.5 1.5 0 1 1 0 3 1.5 1.5 0 0 1 0-3ZM12 15H8a1 1 0 0 1 0-2h1v-3H8a1 1 0 0 1 0-2h2a1 1 0 0 1 1 1v4h1a1 1 0 0 1 0 2Z" />
              </svg>
              <span class="sr-only">Info</span>
              <h3 class="text-sm font-medium">Attention</h3>
            </div>
            <div class="ml-2 mr-2 mt-2 mb-2 text-xs">
              Incorrect use of the <b>:dbg</b>
              tracer in production can lead to performance degradation, latency and crashes.
              <b>DeployEx Live tracing</b>
              enforces limits on the maximum number of messages and applies a timeout (in seconds)
              to ensure the debugger doesn't remain active unintentionally. Check out the
              <a
                href="https://www.erlang.org/docs/24/man/dbg"
                class="font-medium text-blue-600 underline dark:text-blue-500 hover:no-underline"
              >
                Erlang Debugger
              </a>
              for more detailed information.
            </div>

            <.form
              for={@form}
              id="tracing-update-form"
              class="flex ml-2 mr-2 text-xs text-center whitespace-nowrap gap-5"
              phx-change="form-update"
            >
              <.input
                field={@form[:max_messages]}
                type="number"
                step="1"
                min="1"
                max="50"
                label="Messages"
              />

              <.input
                field={@form[:session_timeout_seconds]}
                type="number"
                step="15"
                min="30"
                max="300"
                label="Timeout(s)"
              />
            </.form>
          </div>
        </div>
        <button
          :if={@trace_idle? and @trace_owner?}
          id="tracing-multi-select-run"
          phx-click="tracing-apps-run"
          class="phx-submit-loading:opacity-75 rounded-r-xl bg-green-500 transform active:scale-75 transition-transform hover:bg-green-600 py-10 w-64 text-sm font-semibold  text-white active:text-white/80"
        >
          RUN
        </button>
        <button
          :if={@trace_idle? == false and @trace_owner?}
          id="tracing-multi-select-stop"
          phx-click="tracing-apps-stop"
          class="phx-submit-loading:opacity-75 rounded-r-xl bg-red-500 transform active:scale-75 transition-transform hover:bg-red-600 py-10 w-64 text-sm font-semibold text-white active:text-white/80 animate-pulse"
        >
          STOP
        </button>

        <button
          :if={not @trace_owner?}
          class="phx-submit-loading:opacity-75 rounded-r-xl bg-red-500 transform active:scale-75 transition-transform hover:bg-red-600 py-10 w-64 text-sm font-semibold text-white active:text-white/80 animate-pulse"
        >
          IN USE
        </button>
      </div>
      <div class="flex">
        <MultiSelectList.content
          id="tracing-multi-select"
          selected_text="Selected Items"
          selected={[
            %{name: "services", keys: @node_info.selected_services_keys},
            %{name: "modules", keys: @node_info.selected_modules_keys},
            %{name: "functions", keys: @node_info.selected_functions_keys},
            %{name: "match_spec", keys: @node_info.selected_match_spec_keys}
          ]}
          unselected={[
            %{name: "services", keys: @unselected_services_keys},
            %{name: "modules", keys: @unselected_modules_keys},
            %{name: "functions", keys: @unselected_functions_keys},
            %{name: "match_spec", keys: @unselected_match_spec_keys, info: @match_spec_info}
          ]}
          show_options={@show_tracing_options}
        />
      </div>
      <div class="p-2">
        <div class="bg-white w-full shadow-lg rounded">
          <.table_logs id="live-logs" h_max_size="max-h-[400px]" rows={@streams.tracing_messages}>
            <:col :let={{_id, tracing_message}} label="SERVICE">
              <span><%= tracing_message.service %></span>
            </:col>
            <:col :let={{_id, tracing_message}} label="INDEX">
              <span><%= tracing_message.index %></span>
            </:col>
            <:col :let={{_id, tracing_message}} label="TYPE">
              <span><%= tracing_message.type %></span>
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
     |> assign(form: to_form(default_form_options()))
     |> stream(:tracing_messages, [])}
  end

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:node_info, node_info_new())
     |> assign(:node_data, %{})
     |> assign(:trace_session_id, nil)
     |> assign(:show_tracing_options, false)
     |> assign(form: to_form(default_form_options()))
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
        "form-update",
        %{"max_messages" => max_messages, "session_timeout_seconds" => session_timeout_seconds},
        socket
      ) do
    {:noreply,
     assign(socket,
       form:
         to_form(%{
           "max_messages" => max_messages,
           "session_timeout_seconds" => session_timeout_seconds
         })
     )}
  end

  def handle_event(
        "tracing-apps-stop",
        _data,
        %{assigns: %{trace_session_id: trace_session_id}} = socket
      ) do
    DeployexT.stop_trace(trace_session_id)
    {:noreply, assign(socket, :trace_session_id, nil)}
  end

  def handle_event(
        "tracing-apps-run",
        _data,
        %{assigns: %{node_info: node_info, form: form}} = socket
      ) do
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

                  # credo:disable-for-lines:14
                  if module_key in service_info.modules_keys and function do
                    function_acc ++
                      [
                        %{
                          node: String.to_existing_atom(service_key),
                          module: module_key_atom,
                          function: function.name,
                          arity: function.arity,
                          match_spec: node_info.selected_match_spec_keys
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
                      arity: :_,
                      match_spec: node_info.selected_match_spec_keys
                    }
                  ]
              else
                module_acc ++ functions
              end
            end)
        end)

      case DeployexT.start_trace(functions_to_monitor, %{
             max_messages: String.to_integer(form.params["max_messages"]),
             session_timeout_ms: String.to_integer(form.params["session_timeout_seconds"]) * 1_000
           }) do
        {:ok, %{session_id: session_id}} ->
          {:noreply,
           socket
           |> assign(:trace_session_id, session_id)
           |> stream(:tracing_messages, [], reset: true)}

        # coveralls-ignore-start
        {:error, _} ->
          {:noreply, assign(socket, :trace_session_id, nil)}
          # coveralls-ignore-stop
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
        node_info.selected_functions_keys,
        node_info.selected_match_spec_keys
      )

    {:noreply, assign(socket, :node_info, node_info)}
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
        node_info.selected_functions_keys,
        node_info.selected_match_spec_keys
      )

    {:noreply, assign(socket, :node_info, node_info)}
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
        node_info.selected_functions_keys -- [function_key],
        node_info.selected_match_spec_keys
      )

    {:noreply, assign(socket, :node_info, node_info)}
  end

  def handle_event(
        "multi-select-remove-item",
        %{"item" => "match_spec", "key" => match_spec_key},
        %{assigns: %{node_info: node_info}} = socket
      ) do
    node_info =
      update_node_info(
        node_info.selected_services_keys,
        node_info.selected_modules_keys,
        node_info.selected_functions_keys,
        node_info.selected_match_spec_keys -- [match_spec_key]
      )

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
        node_info.selected_modules_keys,
        node_info.selected_functions_keys,
        node_info.selected_match_spec_keys
      )

    {:noreply, assign(socket, :node_info, node_info)}
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
        node_info.selected_functions_keys,
        node_info.selected_match_spec_keys
      )

    {:noreply, assign(socket, :node_info, node_info)}
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
        node_info.selected_functions_keys ++ [function_key],
        node_info.selected_match_spec_keys
      )

    {:noreply, assign(socket, :node_info, node_info)}
  end

  def handle_event(
        "multi-select-add-item",
        %{"item" => "match_spec", "key" => match_spec_key},
        %{assigns: %{node_info: node_info}} = socket
      ) do
    node_info =
      update_node_info(
        node_info.selected_services_keys,
        node_info.selected_modules_keys,
        node_info.selected_functions_keys,
        node_info.selected_match_spec_keys ++ [match_spec_key]
      )

    {:noreply, assign(socket, :node_info, node_info)}
  end

  @impl true
  def handle_info({:nodeup, _node}, %{assigns: %{node_info: node_info}} = socket) do
    node_info =
      update_node_info(
        node_info.selected_services_keys,
        node_info.selected_modules_keys,
        node_info.selected_functions_keys,
        node_info.selected_match_spec_keys
      )

    {:noreply, assign(socket, :node_info, node_info)}
  end

  def handle_info({:nodedown, node}, %{assigns: %{node_info: node_info}} = socket) do
    service_key = node |> to_string

    node_info =
      update_node_info(
        node_info.selected_services_keys -- [service_key],
        node_info.selected_modules_keys,
        node_info.selected_functions_keys,
        node_info.selected_match_spec_keys
      )

    {:noreply, assign(socket, :node_info, node_info)}
  end

  def handle_info({:new_trace_message, _session_id, node, index, type, message}, socket) do
    data = %{
      service: node,
      id: Deployex.Common.uuid4(),
      index: index,
      type: type,
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

  defp default_form_options do
    %{
      "max_messages" => @default_max_messages,
      "session_timeout_seconds" => @default_session_timeout_seconds
    }
  end

  defp node_info_new do
    match_spec_keys =
      DeployexT.get_default_functions_matchspecs()
      |> Map.keys()
      |> Enum.sort()

    %{
      services_keys: [],
      modules_keys: [],
      functions_keys: [],
      match_spec_keys: match_spec_keys,
      selected_services_keys: [],
      selected_modules_keys: [],
      selected_functions_keys: [],
      selected_match_spec_keys: [],
      node: []
    }
  end

  defp update_node_info, do: update_node_info([], [], [], [])

  defp update_node_info(
         selected_services_keys,
         selected_modules_keys,
         selected_functions_keys,
         selected_match_spec_keys
       ) do
    initial_map =
      %{
        node_info_new()
        | selected_services_keys: selected_services_keys,
          selected_modules_keys: selected_modules_keys,
          selected_functions_keys: selected_functions_keys,
          selected_match_spec_keys: selected_match_spec_keys
      }

    Enum.reduce(Node.list() ++ [Node.self()], initial_map, fn instance_node,
                                                              %{
                                                                services_keys: services_keys,
                                                                modules_keys: modules_keys,
                                                                functions_keys: functions_keys,
                                                                match_spec_keys: match_spec_keys,
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
          # credo:disable-for-lines:6
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
              match_spec_keys: match_spec_keys,
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
          match_spec_keys: match_spec_keys,
          node: node
      }
    end)
  end
end
