defmodule Foundation.Catalog do
  @moduledoc """
  This module will provide catalog abstraction
  """

  @behaviour Foundation.Catalog.Adapter

  alias Foundation.Accounts

  ### ==========================================================================
  ### Public functions
  ### ==========================================================================

  @doc """
  Ensure all directories are initialised

    ## Examples

    iex> alias Foundation.Catalog
    ...> assert Catalog.setup() == :ok
  """
  @impl true
  @spec setup() :: :ok
  def setup, do: default().setup()

  @doc """
  This function return the number of replicas configured

  ## Examples

    iex> alias Foundation.Catalog
    ...> assert Catalog.replicas == 3
  """
  @impl true
  @spec replicas() :: integer()
  def replicas, do: default().replicas()

  @doc """
  This function return a list with all replicas that needs to be
  monitored

  ## Examples

    iex> alias Foundation.Catalog
    ...> assert Catalog.replicas_list == [1, 2, 3]
  """
  @impl true
  @spec replicas_list() :: list()
  def replicas_list, do: default().replicas_list()

  @doc """
  This function return a list with all replicas that needs to be
  monitored, including deployex

  ## Examples

    iex> alias Foundation.Catalog
    ...> assert Catalog.instance_list == [0, 1, 2, 3]
  """
  @impl true
  @spec instance_list() :: list()
  def instance_list, do: default().instance_list()

  @doc """
  Return the app name that will be monitored

  ## Examples

    iex> alias Foundation.Catalog
    ...> assert Catalog.monitored_app_name() == "testapp"
  """
  @impl true
  @spec monitored_app_name() :: binary()
  def monitored_app_name, do: default().monitored_app_name()

  @doc """
  Return the app language that will be monitored

  ## Examples

    iex> alias Foundation.Catalog
    ...> assert Catalog.monitored_app_lang() == "elixir"
  """
  @impl true
  @spec monitored_app_lang() :: binary()
  def monitored_app_lang, do: default().monitored_app_lang()

  @doc """
  Return the app environment vars that will be set

  ## Examples

    iex> alias Foundation.Catalog
    ...> assert Catalog.monitored_app_env() == []
  """
  @impl true
  @spec monitored_app_env() :: list()
  def monitored_app_env, do: default().monitored_app_env()

  @doc """
  Return the monitored app phoenix port

  ## Examples

    iex> alias Foundation.Catalog
    ...> assert Catalog.monitored_app_start_port() == 4444
  """
  @impl true
  @spec monitored_app_start_port() :: integer()
  def monitored_app_start_port, do: default().monitored_app_start_port()

  @doc """
  Return a list of expected nodes, including deployex (instance 0)

  ## Examples

    iex> alias Foundation.Catalog
    ...> nodes = Enum.map(Catalog.expected_nodes(), &Atom.to_string/1)
    ...> assert Enum.any?(nodes, fn node -> String.contains?(node, "deployex") end)
    ...> assert Enum.any?(nodes, fn node -> String.contains?(node, "testapp-1") end)
    ...> assert Enum.any?(nodes, fn node -> String.contains?(node, "testapp-2") end)
    ...> assert Enum.any?(nodes, fn node -> String.contains?(node, "testapp-3") end)

  """
  @impl true
  @spec expected_nodes() :: list()
  def expected_nodes, do: default().expected_nodes()

  @doc """
  Return the path for the stdout log file

  ## Examples

    iex> alias Foundation.Catalog
    ...> assert Catalog.stdout_path(0) == "/var/log/deployex/deployex-stdout.log"
    ...> assert Catalog.stdout_path(1) == "/tmp/testapp/testapp/testapp-1-stdout.log"
    ...> assert Catalog.stdout_path(2) == "/tmp/testapp/testapp/testapp-2-stdout.log"
    ...> assert Catalog.stdout_path(3) == "/tmp/testapp/testapp/testapp-3-stdout.log"
  """
  @impl true
  @spec stdout_path(integer()) :: binary()
  def stdout_path(instance), do: default().stdout_path(instance)

  @doc """
  Return the path for the stderr log file

  ## Examples

    iex> alias Foundation.Catalog
    ...> assert Catalog.stderr_path(0) == "/var/log/deployex/deployex-stderr.log"
    ...> assert Catalog.stderr_path(1) == "/tmp/testapp/testapp/testapp-1-stderr.log"
    ...> assert Catalog.stderr_path(2) == "/tmp/testapp/testapp/testapp-2-stderr.log"
    ...> assert Catalog.stderr_path(3) == "/tmp/testapp/testapp/testapp-3-stderr.log"
  """
  @impl true
  @spec stderr_path(integer()) :: binary()
  def stderr_path(instance), do: default().stderr_path(instance)

  @doc """
  Return the sname of the application with the correct instance suffix

  ## Examples

    iex> alias Foundation.Catalog
    ...> assert Catalog.sname(0) == "deployex"
    ...> assert Catalog.sname(1) == "testapp-1"
    ...> assert Catalog.sname(2) == "testapp-2"
    ...> assert Catalog.sname(3) == "testapp-3"
  """
  @impl true
  @spec sname(integer()) :: String.t()
  def sname(instance), do: default().sname(instance)

  @doc """
  Retrieve the bin path for the respective instance (current)

  ## Examples

    iex> alias Foundation.Catalog
    ...> assert Catalog.bin_path(0, "elixir", :current) == "/opt/deployex/bin/deployex"
    ...> assert Catalog.bin_path(1, "elixir", :current) == "/tmp/deployex/test/varlib/service/testapp/1/current/bin/testapp"
    ...> assert Catalog.bin_path(2, "elixir", :current) == "/tmp/deployex/test/varlib/service/testapp/2/current/bin/testapp"
    ...> assert Catalog.bin_path(3, "elixir", :current) == "/tmp/deployex/test/varlib/service/testapp/3/current/bin/testapp"
    ...> assert Catalog.bin_path(0, "gleam", :current) == "/opt/deployex/bin/deployex"
    ...> assert Catalog.bin_path(1, "gleam", :current) == "/tmp/deployex/test/varlib/service/testapp/1/current/erlang-shipment"
    ...> assert Catalog.bin_path(2, "gleam", :current) == "/tmp/deployex/test/varlib/service/testapp/2/current/erlang-shipment"
    ...> assert Catalog.bin_path(3, "gleam", :current) == "/tmp/deployex/test/varlib/service/testapp/3/current/erlang-shipment"
    ...> assert Catalog.bin_path(0, "erlang", :current) == "/opt/deployex/bin/deployex"
    ...> assert Catalog.bin_path(1, "erlang", :current) == "/tmp/deployex/test/varlib/service/testapp/1/current/bin/testapp"
    ...> assert Catalog.bin_path(2, "erlang", :current) == "/tmp/deployex/test/varlib/service/testapp/2/current/bin/testapp"
    ...> assert Catalog.bin_path(3, "erlang", :current) == "/tmp/deployex/test/varlib/service/testapp/3/current/bin/testapp"
    ...> assert Catalog.bin_path(0, "elixir", :new) == "/opt/deployex/bin/deployex"
    ...> assert Catalog.bin_path(1, "elixir", :new) == "/tmp/deployex/test/varlib/service/testapp/1/new/bin/testapp"
    ...> assert Catalog.bin_path(2, "elixir", :new) == "/tmp/deployex/test/varlib/service/testapp/2/new/bin/testapp"
    ...> assert Catalog.bin_path(3, "elixir", :new) == "/tmp/deployex/test/varlib/service/testapp/3/new/bin/testapp"
    ...> assert Catalog.bin_path(0, "gleam", :new) == "/opt/deployex/bin/deployex"
    ...> assert Catalog.bin_path(1, "gleam", :new) == "/tmp/deployex/test/varlib/service/testapp/1/new/erlang-shipment"
    ...> assert Catalog.bin_path(2, "gleam", :new) == "/tmp/deployex/test/varlib/service/testapp/2/new/erlang-shipment"
    ...> assert Catalog.bin_path(3, "gleam", :new) == "/tmp/deployex/test/varlib/service/testapp/3/new/erlang-shipment"
    ...> assert Catalog.bin_path(0, "erlang", :new) == "/opt/deployex/bin/deployex"
    ...> assert Catalog.bin_path(1, "erlang", :new) == "/tmp/deployex/test/varlib/service/testapp/1/new/bin/testapp"
    ...> assert Catalog.bin_path(2, "erlang", :new) == "/tmp/deployex/test/varlib/service/testapp/2/new/bin/testapp"
    ...> assert Catalog.bin_path(3, "erlang", :new) == "/tmp/deployex/test/varlib/service/testapp/3/new/bin/testapp"
  """
  @impl true
  @spec bin_path(integer(), String.t(), Foundation.Catalog.Adapter.bin_service()) :: String.t()

  def bin_path(instance, monitored_app_lang, bin_service),
    do: default().bin_path(instance, monitored_app_lang, bin_service)

  @doc """
  Base path for the state and service data

  ## Examples

    iex> alias Foundation.Catalog
    ...> assert Catalog.base_path() == "/tmp/deployex/test/varlib"
  """
  @impl true
  @spec base_path :: String.t()
  def base_path, do: default().base_path()

  @doc """
  Path for retrieving the new app data

  ## Examples

    iex> alias Foundation.Catalog
    ...> assert Catalog.new_path(0) == "/tmp/deployex/test/varlib/service/testapp/0/new"
    ...> assert Catalog.new_path(1) == "/tmp/deployex/test/varlib/service/testapp/1/new"
    ...> assert Catalog.new_path(2) == "/tmp/deployex/test/varlib/service/testapp/2/new"
    ...> assert Catalog.new_path(3) == "/tmp/deployex/test/varlib/service/testapp/3/new"
  """
  @impl true
  @spec new_path(integer()) :: binary()
  def new_path(instance), do: default().new_path(instance)

  @doc """
  Path where the app will be running from

  ## Examples

    iex> alias Foundation.Catalog
    ...> assert Catalog.current_path(0) == "/tmp/deployex/test/varlib/service/testapp/0/current"
    ...> assert Catalog.current_path(1) == "/tmp/deployex/test/varlib/service/testapp/1/current"
    ...> assert Catalog.current_path(2) == "/tmp/deployex/test/varlib/service/testapp/2/current"
    ...> assert Catalog.current_path(3) == "/tmp/deployex/test/varlib/service/testapp/3/current"
  """
  @impl true
  @spec current_path(integer()) :: binary()
  def current_path(instance), do: default().current_path(instance)

  @doc """
  Path to move the previous app files

  ## Examples

    iex> alias Foundation.Catalog
    ...> assert Catalog.previous_path(0) == "/tmp/deployex/test/varlib/service/testapp/0/previous"
    ...> assert Catalog.previous_path(1) == "/tmp/deployex/test/varlib/service/testapp/1/previous"
    ...> assert Catalog.previous_path(2) == "/tmp/deployex/test/varlib/service/testapp/2/previous"
    ...> assert Catalog.previous_path(3) == "/tmp/deployex/test/varlib/service/testapp/3/previous"
  """
  @impl true
  @spec previous_path(integer()) :: binary()
  def previous_path(instance), do: default().previous_path(instance)

  @doc """
  Retrieve the history of set versions
  """
  @impl true
  @spec versions() :: list()
  def versions, do: default().versions()

  @doc """
  Retrieve the history of set versions by instance
  """
  @impl true
  @spec versions(integer()) :: list()
  def versions(instance), do: default().versions(instance)

  @doc """
  Add a version to the version history

  """
  @impl true
  @spec add_version(map()) :: :ok
  def add_version(version), do: default().add_version(version)

  @doc """
  Retrieve the ghosted version history
  """
  @impl true
  @spec ghosted_versions() :: list()
  def ghosted_versions, do: default().ghosted_versions()

  @doc """
  Add a version to the ghosted version history
  """
  @impl true
  @spec add_ghosted_version(map()) :: {:ok, list()}
  def add_ghosted_version(version), do: default().add_ghosted_version(version)

  @doc """
  Add a user session token (This data is not persistent)
  """
  @impl true
  @spec add_user_session_token(Accounts.UserToken.t()) :: :ok
  def add_user_session_token(token), do: default().add_user_session_token(token)

  @doc """
  Retrieve the user session token by token
  """
  @impl true
  @spec get_user_session_token_by_token(String.t()) :: Accounts.UserToken.t() | nil
  def get_user_session_token_by_token(token), do: default().get_user_session_token_by_token(token)

  @doc """
  Retrieve the current deployex dynamic configuration
  """
  @impl true
  @spec config() :: Foundation.Catalog.Config.t()
  def config, do: default().config() || %Foundation.Catalog.Config{}

  @doc """
  Update the current deployex dynamic configuration
  """
  @impl true
  @spec config_update(Foundation.Catalog.Config.t()) :: {:ok, Foundation.Catalog.Config.t()}
  def config_update(config), do: default().config_update(config)

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================
  defp default, do: Application.fetch_env!(:foundation, __MODULE__)[:adapter]
end
