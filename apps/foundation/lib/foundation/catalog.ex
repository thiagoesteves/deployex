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
  Ensure all directories are initialised for deployex app

    ## Examples

    iex> alias Foundation.Catalog
    ...> assert Catalog.setup() == :ok
  """
  @impl true
  @spec setup() :: :ok
  def setup, do: default().setup()

  @doc """
  Ensure all directories are initialised for the respective node

    ## Examples

    iex> alias Foundation.Catalog
    ...> import ExUnit.CaptureLog
    ...> assert Catalog.setup(:"node-1@host") == :ok
    ...> assert Catalog.setup(nil) == :ok
    ...> assert capture_log(fn -> Catalog.setup(:"node-") == {:error, :invalid_node} end) =~ "Setup failed due to invalid node format: node-"
  """
  @impl true
  @spec setup(node()) :: {:error, :invalid_node}
  def setup(node), do: default().setup(node)

  @doc """
  Ensure all folders for the respective node are cleaned

    ## Examples

    iex> alias Foundation.Catalog
    ...> import ExUnit.CaptureLog
    ...> assert Catalog.cleanup(:"node-1@host") == :ok
    ...> assert capture_log(fn -> Catalog.cleanup(:"node-") == {:error, :invalid_node} end) =~ "Cleanup failed due to invalid node format: node-"
  """
  @impl true
  @spec cleanup(node() | nil) :: {:error, :invalid_node}
  def cleanup(node), do: default().cleanup(node)

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
  Return the app name that will be monitored

  ## Examples

    iex> alias Foundation.Catalog
    ...> assert Catalog.monitored_app_name() == "testapp"
  """
  @impl true
  @spec monitored_app_name() :: String.t()
  def monitored_app_name, do: default().monitored_app_name()

  @doc """
  Return the app language that will be monitored

  ## Examples

    iex> alias Foundation.Catalog
    ...> assert Catalog.monitored_app_lang() == "elixir"
  """
  @impl true
  @spec monitored_app_lang() :: String.t()
  def monitored_app_lang, do: default().monitored_app_lang()

  @doc """
  Return the app environment vars that will be set

  ## Examples

    iex> alias Foundation.Catalog
    ...> assert Catalog.monitored_app_env() == ["SECRET=value", "PHX_SERVER=true"]
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
  Return the respective node details: name, hostname and instance

  ## Examples

    iex> alias Foundation.Catalog
    ...> assert %Foundation.Catalog.Node{name_string: "testapp", hostname: _,  suffix: _suffix} = Catalog.node_info(:"testapp-1@nohost")
    ...> assert %Foundation.Catalog.Node{name_string: "testapp", hostname: _,  suffix: _suffix} = Catalog.node_info(:"testapp-2@nohost")
    ...> assert %Foundation.Catalog.Node{name_string: "testapp", hostname: _,  suffix: _suffix} = Catalog.node_info(:"testapp-3@nohost")
    ...> refute Catalog.node_info(:"testapp-")
    ...> refute Catalog.node_info(:"testapp-1-1@host")

  """
  @impl true
  @spec node_info(String.t() | node()) :: Foundation.Catalog.Node.t() | nil
  def node_info(node), do: default().node_info(node)

  @doc """
  Return the respective node details based on a sname

  ## Examples

    iex> alias Foundation.Catalog
    ...> assert %Foundation.Catalog.Node{name_string: "testapp", hostname: _,  suffix: _suffix} = Catalog.node_info_from_sname("testapp-1")
    ...> assert %Foundation.Catalog.Node{name_string: "testapp", hostname: _,  suffix: _suffix} = Catalog.node_info_from_sname("testapp-2")
    ...> assert %Foundation.Catalog.Node{name_string: "testapp", hostname: _,  suffix: _suffix} = Catalog.node_info_from_sname("testapp-3")

  """
  @impl true
  @spec node_info_from_sname(String.t()) :: Foundation.Catalog.Node.t() | nil
  def node_info_from_sname(node), do: default().node_info_from_sname(node)

  @doc """
  Return the path for the stdout log file

  ## Examples

    iex> alias Foundation.Catalog
    ...> import ExUnit.CaptureLog
    ...> assert Catalog.stdout_path(:"deployex@hostname") == "/var/log/deployex/deployex-stdout.log"
    ...> assert Catalog.stdout_path(:"testapp-1@hostname") == "/tmp/testapp/testapp/testapp-1-stdout.log"
    ...> assert Catalog.stdout_path(:"testapp-2@hostname") == "/tmp/testapp/testapp/testapp-2-stdout.log"
    ...> assert Catalog.stdout_path(:"testapp-3@hostname") == "/tmp/testapp/testapp/testapp-3-stdout.log"
    ...> assert capture_log(fn -> refute Catalog.stdout_path(:"testapp-") end) =~ "Stdout path failed due to invalid node format: testapp-"
  """
  @impl true
  @spec stdout_path(node()) :: String.t() | {:error, :invalid_format}
  def stdout_path(node), do: default().stdout_path(node)

  @doc """
  Return the path for the stderr log file

  ## Examples

    iex> alias Foundation.Catalog
    ...> import ExUnit.CaptureLog
    ...> assert Catalog.stderr_path(:"deployex@hostname") == "/var/log/deployex/deployex-stderr.log"
    ...> assert Catalog.stderr_path(:"testapp-1@hostname") == "/tmp/testapp/testapp/testapp-1-stderr.log"
    ...> assert Catalog.stderr_path(:"testapp-2@hostname") == "/tmp/testapp/testapp/testapp-2-stderr.log"
    ...> assert Catalog.stderr_path(:"testapp-3@hostname") == "/tmp/testapp/testapp/testapp-3-stderr.log"
    ...> assert capture_log(fn -> refute Catalog.stderr_path(:"testapp-") end) =~ "Stderr path failed due to invalid node format: testapp-"
  """
  @impl true
  @spec stderr_path(node()) :: String.t() | {:error, :invalid_format}
  def stderr_path(node), do: default().stderr_path(node)

  @doc """
  Retrieve the bin path for the respective instance (current)

  ## Examples

    iex> alias Foundation.Catalog
    ...> assert Catalog.bin_path(:"deployex@hostname", "elixir", :current) == "/opt/deployex/bin/deployex"
    ...> assert Catalog.bin_path(:"testapp-1@hostname", "elixir", :current) == "/tmp/deployex/test/varlib/service/testapp/testapp-1/current/bin/testapp"
    ...> assert Catalog.bin_path(:"testapp-2@hostname", "elixir", :current) == "/tmp/deployex/test/varlib/service/testapp/testapp-2/current/bin/testapp"
    ...> assert Catalog.bin_path(:"testapp-3@hostname", "elixir", :current) == "/tmp/deployex/test/varlib/service/testapp/testapp-3/current/bin/testapp"
    ...> assert Catalog.bin_path(:"deployex@hostname", "gleam", :current) == "/opt/deployex/bin/deployex"
    ...> assert Catalog.bin_path(:"testapp-1@hostname", "gleam", :current) == "/tmp/deployex/test/varlib/service/testapp/testapp-1/current/erlang-shipment"
    ...> assert Catalog.bin_path(:"testapp-2@hostname", "gleam", :current) == "/tmp/deployex/test/varlib/service/testapp/testapp-2/current/erlang-shipment"
    ...> assert Catalog.bin_path(:"testapp-3@hostname", "gleam", :current) == "/tmp/deployex/test/varlib/service/testapp/testapp-3/current/erlang-shipment"
    ...> assert Catalog.bin_path(:"deployex@hostname", "erlang", :current) == "/opt/deployex/bin/deployex"
    ...> assert Catalog.bin_path(:"testapp-1@hostname", "erlang", :current) == "/tmp/deployex/test/varlib/service/testapp/testapp-1/current/bin/testapp"
    ...> assert Catalog.bin_path(:"testapp-2@hostname", "erlang", :current) == "/tmp/deployex/test/varlib/service/testapp/testapp-2/current/bin/testapp"
    ...> assert Catalog.bin_path(:"testapp-3@hostname", "erlang", :current) == "/tmp/deployex/test/varlib/service/testapp/testapp-3/current/bin/testapp"
    ...> assert Catalog.bin_path(:"deployex@hostname", "elixir", :new) == "/opt/deployex/bin/deployex"
    ...> assert Catalog.bin_path(:"testapp-1@hostname", "elixir", :new) == "/tmp/deployex/test/varlib/service/testapp/testapp-1/new/bin/testapp"
    ...> assert Catalog.bin_path(:"testapp-2@hostname", "elixir", :new) == "/tmp/deployex/test/varlib/service/testapp/testapp-2/new/bin/testapp"
    ...> assert Catalog.bin_path(:"testapp-3@hostname", "elixir", :new) == "/tmp/deployex/test/varlib/service/testapp/testapp-3/new/bin/testapp"
    ...> assert Catalog.bin_path(:"deployex@hostname", "gleam", :new) == "/opt/deployex/bin/deployex"
    ...> assert Catalog.bin_path(:"testapp-1@hostname", "gleam", :new) == "/tmp/deployex/test/varlib/service/testapp/testapp-1/new/erlang-shipment"
    ...> assert Catalog.bin_path(:"testapp-2@hostname", "gleam", :new) == "/tmp/deployex/test/varlib/service/testapp/testapp-2/new/erlang-shipment"
    ...> assert Catalog.bin_path(:"testapp-3@hostname", "gleam", :new) == "/tmp/deployex/test/varlib/service/testapp/testapp-3/new/erlang-shipment"
    ...> assert Catalog.bin_path(:"deployex@hostname", "erlang", :new) == "/opt/deployex/bin/deployex"
    ...> assert Catalog.bin_path(:"testapp-1@hostname", "erlang", :new) == "/tmp/deployex/test/varlib/service/testapp/testapp-1/new/bin/testapp"
    ...> assert Catalog.bin_path(:"testapp-2@hostname", "erlang", :new) == "/tmp/deployex/test/varlib/service/testapp/testapp-2/new/bin/testapp"
    ...> assert Catalog.bin_path(:"testapp-3@hostname", "erlang", :new) == "/tmp/deployex/test/varlib/service/testapp/testapp-3/new/bin/testapp"
    ...> refute Catalog.bin_path(:"testapp-1@hostname", "", :current)
    ...> refute Catalog.bin_path(:"testapp-1@hostname", "elixir", :any)
    ...> refute Catalog.bin_path(:"deployex-", "elixir", :any)
  """
  @impl true
  @spec bin_path(node(), String.t(), Foundation.Catalog.Adapter.bin_service()) :: String.t()

  def bin_path(node, monitored_app_lang, bin_service),
    do: default().bin_path(node, monitored_app_lang, bin_service)

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
    ...> assert Catalog.new_path(:"testapp-0@hostname") == "/tmp/deployex/test/varlib/service/testapp/testapp-0/new"
    ...> assert Catalog.new_path(:"testapp-1@hostname") == "/tmp/deployex/test/varlib/service/testapp/testapp-1/new"
    ...> assert Catalog.new_path(:"testapp-2@hostname") == "/tmp/deployex/test/varlib/service/testapp/testapp-2/new"
    ...> assert Catalog.new_path(:"testapp-3@hostname") == "/tmp/deployex/test/varlib/service/testapp/testapp-3/new"
    ...> refute Catalog.new_path(:"testapp-")
  """
  @impl true
  @spec new_path(node()) :: String.t()
  def new_path(node), do: default().new_path(node)

  @doc """
  Path where the app will be running from

  ## Examples

    iex> alias Foundation.Catalog
    ...> assert Catalog.current_path(:"testapp-0@hostname") == "/tmp/deployex/test/varlib/service/testapp/testapp-0/current"
    ...> assert Catalog.current_path(:"testapp-1@hostname") == "/tmp/deployex/test/varlib/service/testapp/testapp-1/current"
    ...> assert Catalog.current_path(:"testapp-2@hostname") == "/tmp/deployex/test/varlib/service/testapp/testapp-2/current"
    ...> assert Catalog.current_path(:"testapp-3@hostname") == "/tmp/deployex/test/varlib/service/testapp/testapp-3/current"
    ...> refute Catalog.current_path(:"testapp-")
  """
  @impl true
  @spec current_path(node()) :: String.t()
  def current_path(node), do: default().current_path(node)

  @doc """
  Path to move the previous app files

  ## Examples

    iex> alias Foundation.Catalog
    ...> assert Catalog.previous_path(:"testapp-0@hostname") == "/tmp/deployex/test/varlib/service/testapp/testapp-0/previous"
    ...> assert Catalog.previous_path(:"testapp-1@hostname") == "/tmp/deployex/test/varlib/service/testapp/testapp-1/previous"
    ...> assert Catalog.previous_path(:"testapp-2@hostname") == "/tmp/deployex/test/varlib/service/testapp/testapp-2/previous"
    ...> assert Catalog.previous_path(:"testapp-3@hostname") == "/tmp/deployex/test/varlib/service/testapp/testapp-3/previous"
    ...> refute Catalog.previous_path(:"testapp-")
  """
  @impl true
  @spec previous_path(node()) :: String.t()
  def previous_path(node), do: default().previous_path(node)

  @doc """
  Retrieve the history of set versions
  """
  @impl true
  @spec versions() :: list()
  def versions, do: default().versions()

  @doc """
  Retrieve the history of set versions by node
  """
  @impl true
  @spec versions(node()) :: list()
  def versions(node), do: default().versions(node)

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
