defmodule Deployex.Storage do
  @moduledoc """
  This module will provide storage abstraction
  """

  @behaviour Deployex.Storage.Adapter

  defmodule Config do
    @moduledoc """
    Structure to handle the deployex configuration
    """
    @type t :: %__MODULE__{mode: :manual | :automatic, manual_version: map() | nil}

    @derive Jason.Encoder

    defstruct mode: :automatic,
              manual_version: nil
  end

  ### ==========================================================================
  ### Public functions
  ### ==========================================================================

  @doc """
  Ensure all directories are initialised
  """
  @impl true
  @spec setup() :: :ok
  def setup, do: default().setup()

  @doc """
  This function return the number of replicas configured

  ## Examples

    iex> alias Deployex.Storage
    ...> assert Storage.replicas == 3
  """
  @impl true
  @spec replicas() :: integer()
  def replicas, do: default().replicas()

  @doc """
  This function return a list with all replicas that needs to be
  monitored

  ## Examples

    iex> alias Deployex.Storage
    ...> assert Storage.replicas_list == [1, 2, 3]
  """
  @impl true
  @spec replicas_list() :: list()
  def replicas_list, do: default().replicas_list()

  @doc """
  This function return a list with all replicas that needs to be
  monitored, including deployex

  ## Examples

    iex> alias Deployex.Storage
    ...> assert Storage.instance_list == [0, 1, 2, 3]
  """
  @impl true
  @spec instance_list() :: list()
  def instance_list, do: default().instance_list()

  @doc """
  Return the app name that will be monitored

  ## Examples

    iex> alias Deployex.Storage
    ...> assert Storage.monitored_app_name() == "testapp"
  """
  @impl true
  @spec monitored_app_name() :: binary()
  def monitored_app_name, do: default().monitored_app_name()

  @doc """
  Return the app language that will be monitored

  ## Examples

    iex> alias Deployex.Storage
    ...> assert Storage.monitored_app_lang() == "elixir"
  """
  @impl true
  @spec monitored_app_lang() :: binary()
  def monitored_app_lang, do: default().monitored_app_lang()

  @doc """
  Return the monitored app phoenix port

  ## Examples

    iex> alias Deployex.Storage
    ...> assert Storage.monitored_app_start_port() == 4444
  """
  @impl true
  @spec monitored_app_start_port() :: integer()
  def monitored_app_start_port, do: default().monitored_app_start_port()

  @doc """
  Return the path for the stdout log file

  ## Examples

    iex> alias Deployex.Storage
    ...> assert Storage.stdout_path(0) == "/var/log/deployex/deployex-stdout.log"
    ...> assert Storage.stdout_path(1) == "/tmp/testapp/testapp/testapp-1-stdout.log"
    ...> assert Storage.stdout_path(2) == "/tmp/testapp/testapp/testapp-2-stdout.log"
    ...> assert Storage.stdout_path(3) == "/tmp/testapp/testapp/testapp-3-stdout.log"
  """
  @impl true
  @spec stdout_path(integer()) :: binary()
  def stdout_path(instance), do: default().stdout_path(instance)

  @doc """
  Return the path for the stderr log file

  ## Examples

    iex> alias Deployex.Storage
    ...> assert Storage.stderr_path(0) == "/var/log/deployex/deployex-stderr.log"
    ...> assert Storage.stderr_path(1) == "/tmp/testapp/testapp/testapp-1-stderr.log"
    ...> assert Storage.stderr_path(2) == "/tmp/testapp/testapp/testapp-2-stderr.log"
    ...> assert Storage.stderr_path(3) == "/tmp/testapp/testapp/testapp-3-stderr.log"
  """
  @impl true
  @spec stderr_path(integer()) :: binary()
  def stderr_path(instance), do: default().stderr_path(instance)

  @doc """
  Return the sname of the application with the correct instance suffix

  ## Examples

    iex> alias Deployex.Storage
    ...> assert Storage.sname(0) == "deployex"
    ...> assert Storage.sname(1) == "testapp-1"
    ...> assert Storage.sname(2) == "testapp-2"
    ...> assert Storage.sname(3) == "testapp-3"
  """
  @impl true
  @spec sname(integer()) :: String.t()
  def sname(instance), do: default().sname(instance)

  @doc """
  Retrieve the bin path for the respective instance (current)

  ## Examples

    iex> alias Deployex.Storage
    ...> assert Storage.bin_path(0, "elixir", :current) == "/opt/deployex/bin/deployex"
    ...> assert Storage.bin_path(1, "elixir", :current) == "/tmp/deployex/test/varlib/service/testapp/1/current/bin/testapp"
    ...> assert Storage.bin_path(2, "elixir", :current) == "/tmp/deployex/test/varlib/service/testapp/2/current/bin/testapp"
    ...> assert Storage.bin_path(3, "elixir", :current) == "/tmp/deployex/test/varlib/service/testapp/3/current/bin/testapp"
    ...> assert Storage.bin_path(0, "gleam", :current) == "/opt/deployex/bin/deployex"
    ...> assert Storage.bin_path(1, "gleam", :current) == "/tmp/deployex/test/varlib/service/testapp/1/current/erlang-shipment"
    ...> assert Storage.bin_path(2, "gleam", :current) == "/tmp/deployex/test/varlib/service/testapp/2/current/erlang-shipment"
    ...> assert Storage.bin_path(3, "gleam", :current) == "/tmp/deployex/test/varlib/service/testapp/3/current/erlang-shipment"
    ...> assert Storage.bin_path(0, "erlang", :current) == "/opt/deployex/bin/deployex"
    ...> assert Storage.bin_path(1, "erlang", :current) == "/tmp/deployex/test/varlib/service/testapp/1/current/bin/testapp"
    ...> assert Storage.bin_path(2, "erlang", :current) == "/tmp/deployex/test/varlib/service/testapp/2/current/bin/testapp"
    ...> assert Storage.bin_path(3, "erlang", :current) == "/tmp/deployex/test/varlib/service/testapp/3/current/bin/testapp"
    ...> assert Storage.bin_path(0, "elixir", :new) == "/opt/deployex/bin/deployex"
    ...> assert Storage.bin_path(1, "elixir", :new) == "/tmp/deployex/test/varlib/service/testapp/1/new/bin/testapp"
    ...> assert Storage.bin_path(2, "elixir", :new) == "/tmp/deployex/test/varlib/service/testapp/2/new/bin/testapp"
    ...> assert Storage.bin_path(3, "elixir", :new) == "/tmp/deployex/test/varlib/service/testapp/3/new/bin/testapp"
    ...> assert Storage.bin_path(0, "gleam", :new) == "/opt/deployex/bin/deployex"
    ...> assert Storage.bin_path(1, "gleam", :new) == "/tmp/deployex/test/varlib/service/testapp/1/new/erlang-shipment"
    ...> assert Storage.bin_path(2, "gleam", :new) == "/tmp/deployex/test/varlib/service/testapp/2/new/erlang-shipment"
    ...> assert Storage.bin_path(3, "gleam", :new) == "/tmp/deployex/test/varlib/service/testapp/3/new/erlang-shipment"
    ...> assert Storage.bin_path(0, "erlang", :new) == "/opt/deployex/bin/deployex"
    ...> assert Storage.bin_path(1, "erlang", :new) == "/tmp/deployex/test/varlib/service/testapp/1/new/bin/testapp"
    ...> assert Storage.bin_path(2, "erlang", :new) == "/tmp/deployex/test/varlib/service/testapp/2/new/bin/testapp"
    ...> assert Storage.bin_path(3, "erlang", :new) == "/tmp/deployex/test/varlib/service/testapp/3/new/bin/testapp"
  """
  @impl true
  @spec bin_path(integer(), String.t(), Deployex.Storage.Adapter.bin_service()) :: String.t()

  def bin_path(instance, monitored_app_lang, bin_service),
    do: default().bin_path(instance, monitored_app_lang, bin_service)

  @doc """
  Base path for the state and service data

  ## Examples

    iex> alias Deployex.Storage
    ...> assert Storage.base_path() == "/tmp/deployex/test/varlib"
  """
  @impl true
  @spec base_path :: String.t()
  def base_path, do: default().base_path()

  @doc """
  Path for retrieving the new app data

  ## Examples

    iex> alias Deployex.Storage
    ...> assert Storage.new_path(0) == "/tmp/deployex/test/varlib/service/testapp/0/new"
    ...> assert Storage.new_path(1) == "/tmp/deployex/test/varlib/service/testapp/1/new"
    ...> assert Storage.new_path(2) == "/tmp/deployex/test/varlib/service/testapp/2/new"
    ...> assert Storage.new_path(3) == "/tmp/deployex/test/varlib/service/testapp/3/new"
  """
  @impl true
  @spec new_path(integer()) :: binary()
  def new_path(instance), do: default().new_path(instance)

  @doc """
  Path where the app will be running from

  ## Examples

    iex> alias Deployex.Storage
    ...> assert Storage.current_path(0) == "/tmp/deployex/test/varlib/service/testapp/0/current"
    ...> assert Storage.current_path(1) == "/tmp/deployex/test/varlib/service/testapp/1/current"
    ...> assert Storage.current_path(2) == "/tmp/deployex/test/varlib/service/testapp/2/current"
    ...> assert Storage.current_path(3) == "/tmp/deployex/test/varlib/service/testapp/3/current"
  """
  @impl true
  @spec current_path(integer()) :: binary()
  def current_path(instance), do: default().current_path(instance)

  @doc """
  Path to move the previous app files

  ## Examples

    iex> alias Deployex.Storage
    ...> assert Storage.previous_path(0) == "/tmp/deployex/test/varlib/service/testapp/0/previous"
    ...> assert Storage.previous_path(1) == "/tmp/deployex/test/varlib/service/testapp/1/previous"
    ...> assert Storage.previous_path(2) == "/tmp/deployex/test/varlib/service/testapp/2/previous"
    ...> assert Storage.previous_path(3) == "/tmp/deployex/test/varlib/service/testapp/3/previous"
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
  @spec add_user_session_token(Deployex.Accounts.UserToken.t()) :: :ok
  def add_user_session_token(token), do: default().add_user_session_token(token)

  @doc """
  Retrieve the user session token by token
  """
  @impl true
  @spec get_user_session_token_by_token(String.t()) :: Deployex.Accounts.UserToken.t() | nil
  def get_user_session_token_by_token(token), do: default().get_user_session_token_by_token(token)

  @doc """
  Retrieve the current deployex dynamic configuration
  """
  @impl true
  @spec config() :: Deployex.Storage.Config.t()
  def config, do: default().config() || %Deployex.Storage.Config{}

  @doc """
  Update the current deployex dynamic configuration
  """
  @impl true
  @spec config_update(Deployex.Storage.Config.t()) :: {:ok, Deployex.Storage.Config.t()}
  def config_update(config), do: default().config_update(config)

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================
  defp default, do: Application.fetch_env!(:deployex, __MODULE__)[:adapter]
end
