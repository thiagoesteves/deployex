defmodule DeployexWeb.AgentApi.Router do
  use DeployexWeb, :router

  pipeline :read do
    plug :accepts, ["json"]
    plug DeployexWeb.AgentApi.Auth, scope: "read"
  end

  scope "/v1", DeployexWeb.AgentApi do
    pipe_through :read

    get "/node", NodeController, :show
    get "/apps", AppController, :index
    get "/apps/:name", AppController, :show
    get "/apps/:name/versions", AppController, :versions
    get "/apps/:name/ghosted", AppController, :ghosted
  end
end
