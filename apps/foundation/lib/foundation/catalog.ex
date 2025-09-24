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
    ...> assert Catalog.setup("testapp") == :ok
    ...> assert Catalog.setup(nil) == :ok
  """
  @impl true
  @spec setup(String.t()) :: :ok
  def setup(sname), do: default().setup(sname)

  @doc """
  Ensure all folders for the respective node are cleaned

    ## Examples

    iex> alias Foundation.Catalog
    ...> assert Catalog.cleanup("testapp") == :ok
    ...> assert Catalog.cleanup("node-1234-1") == :ok
    ...> assert Catalog.cleanup(nil) == :ok
  """
  @impl true
  @spec cleanup(String.t() | nil) :: :ok
  def cleanup(sname), do: default().cleanup(sname)

  @doc """
  This function return a list with all monitored applications
  monitored

  ## Examples

    iex> alias Foundation.Catalog
    ...> assert Catalog.applications == [ %{env: ["SECRET=value", "PHX_SERVER=true"], language: "elixir", name: "myelixir", replicas: 3, replica_ports: [%{base: 4444, key: "PORT"}]}, %{env: ["SECRET=value", "PHX_SERVER=true"], name: "myerlang", replicas: 3, replica_ports: [%{base: 5555, key: "PORT"}], language: "erlang"}, %{env: ["SECRET=value", "PHX_SERVER=true"], name: "mygleam", replicas: 3, replica_ports: [%{base: 6666, key: "PORT"}], language: "gleam"} ]
  """
  @impl true
  @spec applications() :: list()
  def applications, do: default().applications()

  @doc """
  Create a new sname for a monitored application

  ## Examples

    iex> alias Foundation.Catalog
    ...> assert "testapp-" <> _suffix = Catalog.create_sname("testapp")

  """
  @impl true
  @spec create_sname(String.t()) :: String.t()
  def create_sname(name), do: default().create_sname(name)

  @doc """
  Return the respective node details: name, hostname, suffix, etc

  ## Examples

    iex> alias Foundation.Catalog
    ...> assert %Foundation.Catalog.Node{name: "myelixir", hostname: _,  suffix: _suffix} = Catalog.node_info(:"myelixir-1@nohost")
    ...> assert %Foundation.Catalog.Node{name: "myelixir", hostname: _,  suffix: _suffix} = Catalog.node_info(:"myelixir-2@nohost")
    ...> assert %Foundation.Catalog.Node{name: "myelixir", hostname: _,  suffix: _suffix} = Catalog.node_info(:"myelixir-3@nohost")
    ...> assert %Foundation.Catalog.Node{name: "deployex", hostname: _,  suffix: _suffix} = Catalog.node_info(:"deployex@nohost")
    ...> assert %Foundation.Catalog.Node{name: "deployex", hostname: _,  suffix: _suffix} = Catalog.node_info(:"nonode@nohost")
    ...> refute Catalog.node_info(:"myelixir-1-1@host")
  """
  @impl true
  @spec node_info(String.t() | node() | nil) :: Foundation.Catalog.Node.t() | nil
  def node_info(node_or_sname), do: default().node_info(node_or_sname)

  @doc """
  Return the path for the stdout log file

  ## Examples

    iex> alias Foundation.Catalog
    ...> assert Catalog.stdout_path("deployex") == "/var/log/deployex/deployex-stdout.log"
    ...> assert Catalog.stdout_path("myelixir-1") == "/tmp/deployex/test/varlog/myelixir/myelixir-1-stdout.log"
    ...> assert Catalog.stdout_path("myelixir-2") == "/tmp/deployex/test/varlog/myelixir/myelixir-2-stdout.log"
    ...> assert Catalog.stdout_path("myelixir-3") == "/tmp/deployex/test/varlog/myelixir/myelixir-3-stdout.log"
  """
  @impl true
  @spec stdout_path(String.t()) :: String.t() | nil
  def stdout_path(sname), do: default().stdout_path(sname)

  @doc """
  Return the path for the stderr log file

  ## Examples

    iex> alias Foundation.Catalog
    ...> assert Catalog.stderr_path("deployex") == "/var/log/deployex/deployex-stderr.log"
    ...> assert Catalog.stderr_path("myelixir-1") == "/tmp/deployex/test/varlog/myelixir/myelixir-1-stderr.log"
    ...> assert Catalog.stderr_path("myelixir-2") == "/tmp/deployex/test/varlog/myelixir/myelixir-2-stderr.log"
    ...> assert Catalog.stderr_path("myelixir-3") == "/tmp/deployex/test/varlog/myelixir/myelixir-3-stderr.log"
  """
  @impl true
  @spec stderr_path(String.t()) :: String.t() | nil
  def stderr_path(sname), do: default().stderr_path(sname)

  @doc """
  Retrieve the bin path for the respective sname

  ## Examples

    iex> alias Foundation.Catalog
    ...> assert Catalog.bin_path("deployex", :current) == "/tmp/deployex/test/opt/deployex"
    ...> assert Catalog.bin_path("myelixir-1", :current) == "/tmp/deployex/test/varlib/service/myelixir/myelixir-1/current/bin/myelixir"
    ...> assert Catalog.bin_path("myelixir-2", :current) == "/tmp/deployex/test/varlib/service/myelixir/myelixir-2/current/bin/myelixir"
    ...> assert Catalog.bin_path("myelixir-3", :current) == "/tmp/deployex/test/varlib/service/myelixir/myelixir-3/current/bin/myelixir"
    ...> assert Catalog.bin_path("deployex", :current) == "/tmp/deployex/test/opt/deployex"
    ...> assert Catalog.bin_path("mygleam-1", :current) == "/tmp/deployex/test/varlib/service/mygleam/mygleam-1/current/erlang-shipment"
    ...> assert Catalog.bin_path("mygleam-2", :current) == "/tmp/deployex/test/varlib/service/mygleam/mygleam-2/current/erlang-shipment"
    ...> assert Catalog.bin_path("mygleam-3", :current) == "/tmp/deployex/test/varlib/service/mygleam/mygleam-3/current/erlang-shipment"
    ...> assert Catalog.bin_path("deployex",  :current) == "/tmp/deployex/test/opt/deployex"
    ...> assert Catalog.bin_path("myerlang-1", :current) == "/tmp/deployex/test/varlib/service/myerlang/myerlang-1/current/bin/myerlang"
    ...> assert Catalog.bin_path("myerlang-2", :current) == "/tmp/deployex/test/varlib/service/myerlang/myerlang-2/current/bin/myerlang"
    ...> assert Catalog.bin_path("myerlang-3", :current) == "/tmp/deployex/test/varlib/service/myerlang/myerlang-3/current/bin/myerlang"
    ...> assert Catalog.bin_path("deployex", :new) == "/tmp/deployex/test/opt/deployex"
    ...> assert Catalog.bin_path("myelixir-1", :new) == "/tmp/deployex/test/varlib/service/myelixir/myelixir-1/new/bin/myelixir"
    ...> assert Catalog.bin_path("myelixir-2", :new) == "/tmp/deployex/test/varlib/service/myelixir/myelixir-2/new/bin/myelixir"
    ...> assert Catalog.bin_path("myelixir-3", :new) == "/tmp/deployex/test/varlib/service/myelixir/myelixir-3/new/bin/myelixir"
    ...> assert Catalog.bin_path("deployex", :new) == "/tmp/deployex/test/opt/deployex"
    ...> assert Catalog.bin_path("mygleam-1", :new) == "/tmp/deployex/test/varlib/service/mygleam/mygleam-1/new/erlang-shipment"
    ...> assert Catalog.bin_path("mygleam-2", :new) == "/tmp/deployex/test/varlib/service/mygleam/mygleam-2/new/erlang-shipment"
    ...> assert Catalog.bin_path("mygleam-3", :new) == "/tmp/deployex/test/varlib/service/mygleam/mygleam-3/new/erlang-shipment"
    ...> assert Catalog.bin_path("deployex", :new) == "/tmp/deployex/test/opt/deployex"
    ...> assert Catalog.bin_path("myerlang-1", :new) == "/tmp/deployex/test/varlib/service/myerlang/myerlang-1/new/bin/myerlang"
    ...> assert Catalog.bin_path("myerlang-2", :new) == "/tmp/deployex/test/varlib/service/myerlang/myerlang-2/new/bin/myerlang"
    ...> assert Catalog.bin_path("myerlang-3", :new) == "/tmp/deployex/test/varlib/service/myerlang/myerlang-3/new/bin/myerlang"
  """
  @impl true
  @spec bin_path(String.t(), Foundation.Catalog.Adapter.bin_service()) :: String.t()

  def bin_path(sname, bin_service),
    do: default().bin_path(sname, bin_service)

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
    ...> assert Catalog.new_path("myelixir-0") == "/tmp/deployex/test/varlib/service/myelixir/myelixir-0/new"
    ...> assert Catalog.new_path("myelixir-1") == "/tmp/deployex/test/varlib/service/myelixir/myelixir-1/new"
    ...> assert Catalog.new_path("myelixir-2") == "/tmp/deployex/test/varlib/service/myelixir/myelixir-2/new"
    ...> assert Catalog.new_path("myelixir-3") == "/tmp/deployex/test/varlib/service/myelixir/myelixir-3/new"
    ...> refute Catalog.new_path(nil)
  """
  @impl true
  @spec new_path(String.t()) :: String.t()
  def new_path(sname), do: default().new_path(sname)

  @doc """
  Path where the app will be running from

  ## Examples

    iex> alias Foundation.Catalog
    ...> assert Catalog.current_path("myelixir-0") == "/tmp/deployex/test/varlib/service/myelixir/myelixir-0/current"
    ...> assert Catalog.current_path("myelixir-1") == "/tmp/deployex/test/varlib/service/myelixir/myelixir-1/current"
    ...> assert Catalog.current_path("myelixir-2") == "/tmp/deployex/test/varlib/service/myelixir/myelixir-2/current"
    ...> assert Catalog.current_path("myelixir-3") == "/tmp/deployex/test/varlib/service/myelixir/myelixir-3/current"
    ...> refute Catalog.current_path(nil)
  """
  @impl true
  @spec current_path(String.t()) :: String.t()
  def current_path(sname), do: default().current_path(sname)

  @doc """
  Path to move the previous app files

  ## Examples

    iex> alias Foundation.Catalog
    ...> assert Catalog.previous_path("myelixir-0") == "/tmp/deployex/test/varlib/service/myelixir/myelixir-0/previous"
    ...> assert Catalog.previous_path("myelixir-1") == "/tmp/deployex/test/varlib/service/myelixir/myelixir-1/previous"
    ...> assert Catalog.previous_path("myelixir-2") == "/tmp/deployex/test/varlib/service/myelixir/myelixir-2/previous"
    ...> assert Catalog.previous_path("myelixir-3") == "/tmp/deployex/test/varlib/service/myelixir/myelixir-3/previous"
    ...> refute Catalog.previous_path(nil)
  """
  @impl true
  @spec previous_path(String.t()) :: String.t()
  def previous_path(sname), do: default().previous_path(sname)

  @doc """
  Retrieve the history of set versions by sname
  """
  @impl true
  @spec versions(String.t(), Keyword.t()) :: list()
  def versions(name, options), do: default().versions(name, options)

  @doc """
  Add a version to the version history

  """
  @impl true
  @spec add_version(map()) :: :ok
  def add_version(version), do: default().add_version(version)

  @doc """
  Retrieve the ghosted version history for the respective application
  """
  @impl true
  @spec ghosted_versions(String.t()) :: list()
  def ghosted_versions(name), do: default().ghosted_versions(name)

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
  @spec config(String.t()) :: Foundation.Catalog.Config.t()
  def config(name), do: default().config(name) || %Foundation.Catalog.Config{}

  @doc """
  Update the current deployex dynamic configuration
  """
  @impl true
  @spec config_update(String.t(), Foundation.Catalog.Config.t()) ::
          {:ok, Foundation.Catalog.Config.t()}
  def config_update(name, config), do: default().config_update(name, config)

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================
  defp default, do: Application.fetch_env!(:foundation, __MODULE__)[:adapter]
end
