defmodule DeployexWeb.AgentApi.Endpoint do
  @moduledoc """
  The agent API endpoint, on its own port and off by default.

  It serves only the `/v1` API and its socket, with no session and no dashboard route.
  """
  use Phoenix.Endpoint, otp_app: :deployex_web

  # The token comes in the sec-websocket-protocol header, so it never shows in a URL
  socket "/v1/socket", DeployexWeb.AgentApi.Socket,
    auth_token: true,
    websocket: true,
    longpoll: false

  plug Plug.RequestId

  plug Plug.Telemetry,
    event_prefix: [:phoenix, :endpoint],
    log: {DeployexWeb.Logger, :log, []}

  # Only the mode call reads a body, a few bytes of JSON. Other content types pass unparsed,
  # so a call with no body never fails before the token check
  plug Plug.Parsers,
    parsers: [:json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library(),
    length: 4_096

  plug DeployexWeb.AgentApi.Router
end
