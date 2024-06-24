defmodule DeployexWeb.ApplicationsLive.Logs do
  use DeployexWeb, :live_component

  require Logger

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        <%= "#{@title} [#{@id}]" %>
        <:subtitle><%= @subtitle %></:subtitle>
      </.header>

      <div
        id="topics"
        class="bg-gray-50 max-h-50 overflow-y-auto scroll-auto w-full mt-5"
        style="height: 100vh;"
        phx-update="stream"
      >
        <%= for {dom_id, log} <- @streams.logs do %>
          <p id={dom_id} class={["text-xs font-light", log.color]}>
            <%= log.msg %>
          </p>
        <% end %>
      </div>
    </div>
    """
  end

  @impl true
  def mount(socket) do
    socket =
      socket
      |> assign(:subtitle, "")
      |> assign(:log_counter, 0)
      |> stream(:logs, [])

    {:ok, socket}
  end

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> handle_log_update()

    {:ok, socket}
  end

  defp handle_log_update(%{assigns: %{id: "0", terminal_message: nil}} = socket) do
    log_file = Application.get_env(:deployex, :log_file)

    socket
    |> tail_if_exists(log_file)
  end

  defp handle_log_update(
         %{assigns: %{id: instance, terminal_message: nil, action: action}} = socket
       ) do
    log_file = log_path(instance, action)

    socket
    |> tail_if_exists(log_file)
  end

  defp handle_log_update(
         %{assigns: %{terminal_message: %{message: message}, log_counter: log_counter}} = socket
       ) do
    messages =
      message
      |> String.split(["\n", "\r"], trim: true)
      |> Enum.with_index(fn element, index ->
        color =
          case String.split(element, ["[", "]"], trim: true) do
            [_time, log_level, _] -> log_color(log_level)
            _ -> log_color("debug")
          end

        %{id: log_counter + index, msg: element, color: color}
      end)

    update_log_counter = log_counter + length(messages)

    socket
    |> assign(:log_counter, update_log_counter)
    |> stream(:logs, messages, at: 0)
  end

  defp handle_log_update(socket) do
    socket
  end

  defp log_path(instance, :logs_stdout) do
    instance
    |> String.to_integer()
    |> Deployex.AppConfig.stdout_path()
  end

  defp log_path(instance, :logs_stderr) do
    instance
    |> String.to_integer()
    |> Deployex.AppConfig.stderr_path()
  end

  defp tail_if_exists(%{assigns: %{id: id, action: action}} = socket, path) do
    if File.exists?(path) do
      commands = "tail -f -n 10 #{path}"
      options = [:stdout]

      case Deployex.Terminal.Supervisor.new(%Deployex.Terminal.Server{
             instance: id,
             commands: commands,
             options: options,
             target: self(),
             type: action
           }) do
        {:ok, _pid} ->
          socket
          |> assign(:subtitle, "File: " <> path)

        {:error, {:already_started, _pid}} ->
          message = "Maximum number of log terminals achieved for instance: #{id} type: #{action}"
          Logger.warning(message)

          socket
          |> assign(:subtitle, message)
      end
    else
      socket
      |> assign(:subtitle, "File not found")
    end
  end

  defp log_color("debug"), do: "text-gray-700"
  defp log_color("info"), do: "text-blue-500"
  defp log_color("warning"), do: "text-yellow-700"
  defp log_color("error"), do: "text-red-700"
  defp log_color(_), do: "text-gray-700"
end
