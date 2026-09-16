defmodule DeployexWeb.ProcessLabel do
  @moduledoc """
  `on_mount` hook that labels the LiveView process with its view and the signed-in user.

  LiveView processes are never registered, so without a label they show up in observability
  tools (the embedded Observer Web dashboard, `:etop`, `Process.info/1`, crash reports) as a
  bare pid. The label makes it possible to tell which of a dozen identical-looking processes is
  the Applications page someone left open versus the Terminal session that is holding a port.

  Wire it up as the *last* `on_mount` entry of a `live_session`, so that hooks assigning
  `:current_user` have already run:

      live_session :require_authenticated_user,
        on_mount: [
          {DeployexWeb.UserAuth, :ensure_authenticated},
          {DeployexWeb.UiSettings, :mount_ui_settings},
          DeployexWeb.ProcessLabel
        ] do
  """

  @doc """
  Labels the LiveView process as `{:live_view, view, username}`, or `{:live_view, view}` when
  there is no signed-in user (the login page).

  Labels are arbitrary terms rather than unique names, so no uniqueness or collision handling is
  needed - two browser tabs on the same page legitimately carry the same label.
  """
  def on_mount(:default, _params, _session, socket) do
    # on_mount also runs in the short-lived HTTP process that renders the static page. Labelling
    # that process would name a request handler after a LiveView, so only the connected process -
    # the long-lived one worth identifying - is labelled.
    if Phoenix.LiveView.connected?(socket) do
      Process.set_label(label(socket))
    end

    {:cont, socket}
  end

  defp label(%{view: view, assigns: %{current_user: %{username: username}}}),
    do: {:live_view, view, username}

  defp label(%{view: view}), do: {:live_view, view}
end
