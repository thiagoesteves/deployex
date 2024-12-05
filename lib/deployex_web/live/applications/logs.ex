defmodule DeployexWeb.ApplicationsLive.Logs do
  use DeployexWeb, :live_component

  require Logger

  alias Deployex.Log
  alias Deployex.Terminal

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {"#{@title} [#{@id}]"}
        <:subtitle>{@subtitle}</:subtitle>
      </.header>

      <div class="bg-white w-full shadow-lg rounded">
        <.table_logs id={"application-live-logs-#{@id}"} rows={@streams.log_messages}>
          <:col :let={{_id, log_message}} label="CONTENT">
            <div class="flex">
              <span
                class="w-[5px] rounded ml-1 mr-1"
                style={"background-color: #{log_message.color};"}
              >
              </span>
              <span>{log_message.content}</span>
            </div>
          </:col>
        </.table_logs>
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
      |> stream(:log_messages, [])

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

  defp handle_log_update(
         %{assigns: %{id: instance, terminal_message: nil, action: action}} = socket
       ) do
    log_file = log_path(instance, action)

    socket
    |> tail_if_exists(log_file)
  end

  defp handle_log_update(
         %{
           assigns: %{
             terminal_message: %{message: message, metadata: metadata},
             log_counter: log_counter
           }
         } = socket
       ) do
    messages =
      message
      |> String.split(["\n", "\r"], trim: true)
      |> Enum.with_index(fn content, index ->
        log_key =
          case metadata do
            :logs_stdout -> "stdout"
            :logs_stderr -> "stderr"
          end

        color = Log.log_message_color(content, log_key)

        %{id: log_counter + index, content: content, color: color}
      end)

    update_log_counter = log_counter + length(messages)

    socket
    |> assign(:log_counter, update_log_counter)
    |> stream(:log_messages, messages)
  end

  defp log_path(instance, :logs_stdout) do
    instance
    |> String.to_integer()
    |> Deployex.Storage.stdout_path()
  end

  defp log_path(instance, :logs_stderr) do
    instance
    |> String.to_integer()
    |> Deployex.Storage.stderr_path()
  end

  defp tail_if_exists(%{assigns: %{id: id, action: action}} = socket, path) do
    if File.exists?(path) do
      commands = "tail -f -n 10 #{path}"
      options = [:stdout]

      {:ok, _pid} =
        Terminal.new(%Terminal{
          instance: id,
          commands: commands,
          options: options,
          target: self(),
          metadata: action
        })

      socket
      |> assign(:subtitle, "File: " <> path)
    else
      socket
      |> assign(:subtitle, "File not found")
    end
  end
end
