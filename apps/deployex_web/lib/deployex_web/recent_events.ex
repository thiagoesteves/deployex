defmodule DeployexWeb.RecentEvents do
  @moduledoc """
  `on_mount` hook that keeps this host's recent events in the `:recent_events` assign, as bell items.

  It handles the `Foundation.Notifications.Recent` broadcasts itself, so a LiveView does not subscribe to them.
  """
  import Phoenix.Component, only: [assign: 3, update: 3]
  import Phoenix.LiveView, only: [attach_hook: 4, connected?: 1, detach_hook: 3]

  alias Foundation.Notifications.Recent

  @limit 30

  def on_mount(:default, _params, _session, socket) do
    socket =
      assign(socket, :recent_events, Recent.list() |> Enum.flat_map(&item/1) |> Enum.take(@limit))

    if connected?(socket) do
      Recent.subscribe()
      {:cont, attach_hook(socket, :recent_events, :handle_info, &__MODULE__.handle_recent/2)}
    else
      {:cont, socket}
    end
  end

  # A page that shows the events itself, like Logs, also gets each one as {:recent_notification, recent}
  def on_mount(:forward, _params, _session, socket) do
    if connected?(socket) do
      socket = detach_hook(socket, :recent_events, :handle_info)
      {:cont, attach_hook(socket, :recent_events, :handle_info, &__MODULE__.forward_recent/2)}
    else
      {:cont, socket}
    end
  end

  @doc false
  def forward_recent({:recent_notification, %Recent{}} = message, socket) do
    {:halt, socket} = handle_recent(message, socket)
    {:cont, socket}
  end

  def forward_recent(_message, socket), do: {:cont, socket}

  # An external capture, so a hot upgrade of this module does not break the hook in a running LiveView
  @doc false
  def handle_recent({:recent_notification, %Recent{} = recent}, socket) do
    {:halt, update(socket, :recent_events, &Enum.take(item(recent) ++ &1, @limit))}
  end

  def handle_recent(_message, socket), do: {:cont, socket}

  @doc """
  Returns the bell item of an event, in a list, or an empty list for an event the bell does not show.
  """
  @spec item(Recent.t()) :: [map()]
  def item(%Recent{event: event, payload: payload} = recent) do
    case describe(event, payload) do
      nil ->
        []

      {tone, title, detail} ->
        [
          %{
            id: recent.id,
            at: recent.at,
            tone: tone,
            title: title,
            detail: detail,
            href: history_href(payload, recent.at)
          }
        ]
    end
  end

  @doc """
  Returns the tone and a one-line text of any event, for the events source on the Logs page.
  """
  @spec line(Recent.t()) :: {atom(), String.t()}
  def line(%Recent{event: event, payload: payload}) do
    case describe(event, payload) do
      {tone, title, ""} ->
        {tone, title}

      {tone, title, detail} ->
        {tone, "#{title} · #{detail}"}

      nil ->
        {:info,
         Enum.join(
           [event | Enum.flat_map([:sname, :version, :name], &List.wrap(payload[&1]))],
           " "
         )}
    end
  end

  defp describe("version_ghosted", p),
    do: {:ghost, "#{p[:name]} #{p[:version]} ghosted", reason(p[:reason])}

  defp describe("pre_command_failed", p),
    do: {:error, "#{p[:sname]} pre_command failed", to_string(p[:command])}

  defp describe("crash_restart", p),
    do: {:warning, "#{p[:sname]} crash restart", restarts(p[:crash_restart_count])}

  defp describe("watchdog_threshold_warning", %{action: :warning} = p),
    do:
      {:warning, "#{short(p[:node])} #{p[:type]} at #{p[:current_percentage]}% of the limit",
       "warning at #{p[:warning_threshold_percent]}%"}

  defp describe("watchdog_threshold_exceeded", p),
    do:
      {:error, "#{short(p[:node])} #{p[:type]} at #{p[:current_percentage]}% of the limit",
       if(p[:action] == :restart, do: "restarted", else: "restart is off")}

  defp describe("config_changed", p),
    do: {:warning, changes(p[:changes_count]) <> " pending", fields(p[:fields])}

  defp describe("config_change_applied", p),
    do: {:info, changes(p[:changes_count]) <> " applied", fields(p[:fields])}

  defp describe("certificate_failed", p),
    do: {:error, "TLS certificate renewal failed", "#{p[:app_name]}: #{inspect(p[:reason])}"}

  defp describe("certificate_renewed", p),
    do: {:info, "TLS certificate renewed", to_string(p[:app_name])}

  defp describe("deployment_complete", %{status: :error} = p),
    do: {:error, "#{p[:sname]} deployment failed", to_string(p[:message])}

  defp describe(_event, _payload), do: nil

  defp reason(nil), do: "this host does not deploy it again"
  defp reason(reason), do: to_string(reason)

  defp restarts(1), do: "1 crash restart"
  defp restarts(count), do: "#{count} crash restarts"

  defp changes(1), do: "1 config change"
  defp changes(count), do: "#{count} config changes"

  defp fields(fields) when is_list(fields), do: Enum.map_join(fields, ", ", &to_string/1)
  defp fields(_fields), do: ""

  # Every item opens History at the event's time, with the events and the logs of the instance it names
  defp history_href(payload, at) do
    sources = Enum.join(["events" | instance(payload)], ",")
    "/logs/history?" <> URI.encode_query(source: sources, since: DateTime.to_unix(at))
  end

  defp instance(%{sname: sname}) when is_binary(sname) and sname != "", do: [sname]
  defp instance(%{node: node}) when is_atom(node) and not is_nil(node), do: [short(node)]
  defp instance(_payload), do: []

  defp short(node) when is_atom(node) and not is_nil(node),
    do: node |> Atom.to_string() |> String.split("@") |> hd()

  defp short(node), do: to_string(node)
end
