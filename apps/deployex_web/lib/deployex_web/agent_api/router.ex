defmodule DeployexWeb.AgentApi.Router do
  use DeployexWeb, :router

  pipeline :read do
    plug :accepts, ["json"]
    plug DeployexWeb.AgentApi.Auth, scope: "read"
  end

  # The token check runs first, so a token with no operate scope is always audited. Only the
  # mode call has a body. Other content types pass unparsed
  pipeline :operate do
    plug DeployexWeb.AgentApi.Auth, scope: "operate"
    plug :accepts, ["json"]

    plug Plug.Parsers,
      parsers: [:json],
      pass: ["*/*"],
      json_decoder: Phoenix.json_library(),
      length: 4_096
  end

  scope "/v1", DeployexWeb.AgentApi do
    pipe_through :read

    get "/node", NodeController, :show
    get "/apps", AppController, :index
    get "/apps/:name", AppController, :show
    get "/apps/:name/versions", AppController, :versions
    get "/apps/:name/ghosted", AppController, :ghosted
  end

  scope "/v1", DeployexWeb.AgentApi do
    pipe_through :operate

    post "/apps/:name/restart", OperateController, :restart
    delete "/apps/:name/ghosted/:version", OperateController, :remove_ghosted
    delete "/apps/:name/ghosted", OperateController, :clear_ghosted
    put "/apps/:name/mode", OperateController, :set_mode
  end
end
