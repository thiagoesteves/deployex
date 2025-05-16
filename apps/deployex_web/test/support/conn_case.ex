defmodule DeployexWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use DeployexWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate
  import DeployexWeb.AccountsFixtures

  alias DeployexWeb.Fixture.Nodes, as: FixtureNodes
  alias DeployexWeb.Helper

  using do
    quote do
      # The default endpoint for testing
      @endpoint DeployexWeb.Endpoint

      use DeployexWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import DeployexWeb.ConnCase
    end
  end

  setup _tags do
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc """
  Setup helper that login the default admin user.

      setup :log_in_default_user

  It stores an updated connection and a registered user in the
  test context.
  """
  def log_in_default_user(%{conn: conn}) do
    user = user_fixture()
    %{conn: log_in_user(conn, user), user: user}
  end

  @doc """
  Logs the given `user` into the `conn`.

  It returns an updated `conn`.
  """
  def log_in_user(conn, user) do
    token =
      Foundation.Accounts.generate_user_session_token(user)

    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_token, token)
  end

  @doc """
  Adds the test node name in the context

  It returns an updated `context`.
  """
  def add_test_node(context) do
    name = "test_app"
    suffix = "abc123"
    sname = "#{name}-#{suffix}"
    node = FixtureNodes.test_node(name, suffix)
    node_id = Helper.normalize_id(node)

    context
    |> Map.put(:node, node)
    |> Map.put(:suffix, suffix)
    |> Map.put(:sname, sname)
    |> Map.put(:name, name)
    |> Map.put(:node_id, node_id)
  end
end
