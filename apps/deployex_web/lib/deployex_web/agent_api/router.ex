defmodule DeployexWeb.AgentApi.Router do
  use DeployexWeb, :router

  pipeline :read do
    plug :accepts, ["json"]
    plug DeployexWeb.AgentApi.Auth, scope: "read"
  end

  pipeline :operate do
    plug :accepts, ["json"]
    plug DeployexWeb.AgentApi.Auth, scope: "operate"
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
