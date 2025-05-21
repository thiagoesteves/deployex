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
    ...> assert Catalog.setup("node-1234") == :ok
    ...> assert Catalog.setup(nil) == :ok
  """
  @impl true
  @spec setup(String.t()) :: :ok
  def setup(sname), do: default().setup(sname)

  @doc """
  Ensure all folders for the respective node are cleaned

    ## Examples

    iex> alias Foundation.Catalog
    ...> assert Catalog.cleanup("node-1234") == :ok
    ...> assert Catalog.cleanup(nil) == :ok
  """
  @impl true
  @spec cleanup(String.t() | nil) :: :ok
  def cleanup(sname), do: default().cleanup(sname)

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
  Create a new sname for a monitored application

  ## Examples

    iex> alias Foundation.Catalog

  """
  @impl true
  @spec create_sname(String.t()) :: String.t()
  def create_sname(name), do: default().create_sname(name)

  @doc """
  Convert sname to node

  ## Examples

    iex> alias Foundation.Catalog
    ...> {:ok, hostname} = :inet.gethostname()
    ...> name = "testapp-1"
    ...> node = (name <> "@" <> to_string(hostname)) |> String.to_atom()
    ...> assert node == Catalog.sname_to_node("testapp-1")

  """
  @impl true
  @spec sname_to_node(String.t()) :: node()
  def sname_to_node(sname), do: default().sname_to_node(sname)

  @doc """
  Return the sname info

  ## Examples

    iex> alias Foundation.Catalog
    ...> assert %Catalog.Sname{name: "testapp", suffix: "1"} = Catalog.sname_info("testapp-1")
    ...> assert %Catalog.Sname{name: "testapp", suffix: "2"} = Catalog.sname_info("testapp-2")
    ...> assert %Catalog.Sname{name: "testapp", suffix: "3"} = Catalog.sname_info("testapp-3")
    ...> refute Catalog.sname_info(nil)
    ...> refute Catalog.sname_info("testapp-1-1")
  """
  @impl true
  @spec sname_info(String.t()) :: Foundation.Catalog.Sname.t() | nil
  def sname_info(sname), do: default().sname_info(sname)

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
    ...> assert Catalog.stdout_path("deployex") == "/var/log/deployex/deployex-stdout.log"
    ...> assert Catalog.stdout_path("testapp-1") == "/tmp/testapp/testapp/testapp-1-stdout.log"
    ...> assert Catalog.stdout_path("testapp-2") == "/tmp/testapp/testapp/testapp-2-stdout.log"
    ...> assert Catalog.stdout_path("testapp-3") == "/tmp/testapp/testapp/testapp-3-stdout.log"
  """
  @impl true
  @spec stdout_path(String.t()) :: String.t() | nil
  def stdout_path(sname), do: default().stdout_path(sname)

  @doc """
  Return the path for the stderr log file

  ## Examples

    iex> alias Foundation.Catalog
    ...> assert Catalog.stderr_path("deployex") == "/var/log/deployex/deployex-stderr.log"
    ...> assert Catalog.stderr_path("testapp-1") == "/tmp/testapp/testapp/testapp-1-stderr.log"
    ...> assert Catalog.stderr_path("testapp-2") == "/tmp/testapp/testapp/testapp-2-stderr.log"
    ...> assert Catalog.stderr_path("testapp-3") == "/tmp/testapp/testapp/testapp-3-stderr.log"
  """
  @impl true
  @spec stderr_path(String.t()) :: String.t() | nil
  def stderr_path(sname), do: default().stderr_path(sname)

  @doc """
  Retrieve the bin path for the respective instance (current)

  ## Examples

    iex> alias Foundation.Catalog
    ...> assert Catalog.bin_path("deployex", "elixir", :current) == "/opt/deployex/bin/deployex"
    ...> assert Catalog.bin_path("testapp-1", "elixir", :current) == "/tmp/deployex/test/varlib/service/testapp/testapp-1/current/bin/testapp"
    ...> assert Catalog.bin_path("testapp-2", "elixir", :current) == "/tmp/deployex/test/varlib/service/testapp/testapp-2/current/bin/testapp"
    ...> assert Catalog.bin_path("testapp-3", "elixir", :current) == "/tmp/deployex/test/varlib/service/testapp/testapp-3/current/bin/testapp"
    ...> assert Catalog.bin_path("deployex", "gleam", :current) == "/opt/deployex/bin/deployex"
    ...> assert Catalog.bin_path("testapp-1", "gleam", :current) == "/tmp/deployex/test/varlib/service/testapp/testapp-1/current/erlang-shipment"
    ...> assert Catalog.bin_path("testapp-2", "gleam", :current) == "/tmp/deployex/test/varlib/service/testapp/testapp-2/current/erlang-shipment"
    ...> assert Catalog.bin_path("testapp-3", "gleam", :current) == "/tmp/deployex/test/varlib/service/testapp/testapp-3/current/erlang-shipment"
    ...> assert Catalog.bin_path("deployex", "erlang", :current) == "/opt/deployex/bin/deployex"
    ...> assert Catalog.bin_path("testapp-1", "erlang", :current) == "/tmp/deployex/test/varlib/service/testapp/testapp-1/current/bin/testapp"
    ...> assert Catalog.bin_path("testapp-2", "erlang", :current) == "/tmp/deployex/test/varlib/service/testapp/testapp-2/current/bin/testapp"
    ...> assert Catalog.bin_path("testapp-3", "erlang", :current) == "/tmp/deployex/test/varlib/service/testapp/testapp-3/current/bin/testapp"
    ...> assert Catalog.bin_path("deployex", "elixir", :new) == "/opt/deployex/bin/deployex"
    ...> assert Catalog.bin_path("testapp-1", "elixir", :new) == "/tmp/deployex/test/varlib/service/testapp/testapp-1/new/bin/testapp"
    ...> assert Catalog.bin_path("testapp-2", "elixir", :new) == "/tmp/deployex/test/varlib/service/testapp/testapp-2/new/bin/testapp"
    ...> assert Catalog.bin_path("testapp-3", "elixir", :new) == "/tmp/deployex/test/varlib/service/testapp/testapp-3/new/bin/testapp"
    ...> assert Catalog.bin_path("deployex", "gleam", :new) == "/opt/deployex/bin/deployex"
    ...> assert Catalog.bin_path("testapp-1", "gleam", :new) == "/tmp/deployex/test/varlib/service/testapp/testapp-1/new/erlang-shipment"
    ...> assert Catalog.bin_path("testapp-2", "gleam", :new) == "/tmp/deployex/test/varlib/service/testapp/testapp-2/new/erlang-shipment"
    ...> assert Catalog.bin_path("testapp-3", "gleam", :new) == "/tmp/deployex/test/varlib/service/testapp/testapp-3/new/erlang-shipment"
    ...> assert Catalog.bin_path("deployex", "erlang", :new) == "/opt/deployex/bin/deployex"
    ...> assert Catalog.bin_path("testapp-1", "erlang", :new) == "/tmp/deployex/test/varlib/service/testapp/testapp-1/new/bin/testapp"
    ...> assert Catalog.bin_path("testapp-2", "erlang", :new) == "/tmp/deployex/test/varlib/service/testapp/testapp-2/new/bin/testapp"
    ...> assert Catalog.bin_path("testapp-3", "erlang", :new) == "/tmp/deployex/test/varlib/service/testapp/testapp-3/new/bin/testapp"
    ...> refute Catalog.bin_path("testapp-1", "", :current)
    ...> refute Catalog.bin_path("testapp-1", "elixir", :any)
    ...> refute Catalog.bin_path("deployex-", "elixir", :any)
  """
  @impl true
  @spec bin_path(String.t(), String.t(), Foundation.Catalog.Adapter.bin_service()) :: String.t()

  def bin_path(sname, monitored_app_lang, bin_service),
    do: default().bin_path(sname, monitored_app_lang, bin_service)

  @doc """
  Base path for the state and service data

  ## Examples

    iex> alias Foundation.Catalog
    ...> assert Catalog.service_path("testapp") == "/tmp/deployex/test/varlib/service/testapp"
  """
  @impl true
  @spec service_path(String.t()) :: String.t()
  def service_path(name), do: default().service_path(name)

  @doc """
  Path for retrieving the new app data

  ## Examples

    iex> alias Foundation.Catalog
    ...> assert Catalog.new_path("testapp-0") == "/tmp/deployex/test/varlib/service/testapp/testapp-0/new"
    ...> assert Catalog.new_path("testapp-1") == "/tmp/deployex/test/varlib/service/testapp/testapp-1/new"
    ...> assert Catalog.new_path("testapp-2") == "/tmp/deployex/test/varlib/service/testapp/testapp-2/new"
    ...> assert Catalog.new_path("testapp-3") == "/tmp/deployex/test/varlib/service/testapp/testapp-3/new"
  """
  @impl true
  @spec new_path(String.t()) :: String.t()
  def new_path(sname), do: default().new_path(sname)

  @doc """
  Path where the app will be running from

  ## Examples

    iex> alias Foundation.Catalog
    ...> assert Catalog.current_path("testapp-0") == "/tmp/deployex/test/varlib/service/testapp/testapp-0/current"
    ...> assert Catalog.current_path("testapp-1") == "/tmp/deployex/test/varlib/service/testapp/testapp-1/current"
    ...> assert Catalog.current_path("testapp-2") == "/tmp/deployex/test/varlib/service/testapp/testapp-2/current"
    ...> assert Catalog.current_path("testapp-3") == "/tmp/deployex/test/varlib/service/testapp/testapp-3/current"
  """
  @impl true
  @spec current_path(String.t()) :: String.t()
  def current_path(sname), do: default().current_path(sname)

  @doc """
  Path to move the previous app files

  ## Examples

    iex> alias Foundation.Catalog
    ...> assert Catalog.previous_path("testapp-0") == "/tmp/deployex/test/varlib/service/testapp/testapp-0/previous"
    ...> assert Catalog.previous_path("testapp-1") == "/tmp/deployex/test/varlib/service/testapp/testapp-1/previous"
    ...> assert Catalog.previous_path("testapp-2") == "/tmp/deployex/test/varlib/service/testapp/testapp-2/previous"
    ...> assert Catalog.previous_path("testapp-3") == "/tmp/deployex/test/varlib/service/testapp/testapp-3/previous"
  """
  @impl true
  @spec previous_path(String.t()) :: String.t()
  def previous_path(sname), do: default().previous_path(sname)

  @doc """
  Retrieve the history of set versions
  """
  @impl true
  @spec versions() :: list()
  def versions, do: default().versions()

  @doc """
  Retrieve the history of set versions by sname
  """
  @impl true
  @spec versions(String.t()) :: list()
  def versions(sname), do: default().versions(sname)

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
