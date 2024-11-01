defmodule Deployex.Common do
  @moduledoc """
  This module contains functions to be shared among other modules
  """

  import Deployex.Macros

  @sec_in_minute 60
  @sec_in_hour 3_600
  @sec_in_day 86_400
  @sec_in_months 2_628_000

  @deploy_ref_size 6

  ### ==========================================================================
  ### Public functions
  ### ==========================================================================

  @doc """
  Return a random alphanumeric string

  ## Examples

    iex> alias Deployex.Common
    ...> n = 20
    ...> assert Common.random_small_alphanum(n) |> String.length() == n
  """
  @spec random_small_alphanum(integer()) :: String.t()
  def random_small_alphanum(n \\ @deploy_ref_size) do
    Enum.map(1..n, fn _ ->
      Enum.concat(?0..?9, ?a..?z)
      |> Enum.shuffle()
      |> Enum.random()
    end)
    |> to_string
  end

  @doc """
  Return a random number for a given range

  ## Examples

    iex> alias Deployex.Common
    ...> assert Common.random_number(5,5) == 5
    ...> assert Common.random_number(1,100) >= 1
    ...> assert Common.random_number(1,100) <= 100
  """
  @spec random_number(non_neg_integer(), non_neg_integer()) :: non_neg_integer()
  def random_number(from, to) do
    Enum.random(from..to)
  end

  @doc """
  Return if mutual TLS is supported

  ## Examples

    iex> alias Deployex.Common
    ...> assert Common.check_mtls == :not_supported
  """
  @spec check_mtls() :: :supported | :not_supported
  def check_mtls do
    if :init.get_arguments()[:ssl_dist_optfile] do
      :supported
    else
      :not_supported
    end
  end

  @doc """
  Return the current configured cookie

  ## Examples

    iex> alias Deployex.Common
    ...> assert Common.cookie == :cookie
  """
  @spec cookie() :: atom()
  def cookie do
    if_not_test do
      Node.get_cookie()
    else
      :cookie
    end
  end

  @doc """
  Return the PATH without deployex bin/erts

  ## Examples

    iex> alias Deployex.Common
    ...> assert Common.remove_deployex_from_path != ""
  """
  @spec remove_deployex_from_path :: String.t()
  def remove_deployex_from_path do
    bindir = System.get_env("BINDIR", "")
    deployex_bin_dir = Application.fetch_env!(:deployex, :bin_dir)

    paths =
      "PATH"
      |> System.get_env("")
      |> String.split([":"])

    Enum.join(paths -- [bindir, deployex_bin_dir], ":")
  end

  @doc """
  This function converts diff time to string

  ## Examples

    iex> alias Deployex.Common
    ...> assert Common.uptime_to_string(nil) == "-/-"
    ...> start_time = System.monotonic_time() - (:timer.seconds(1) * 1000000)
    ...> assert Common.uptime_to_string(start_time) == "now"
    ...> start_time = System.monotonic_time() - (:timer.seconds(30) * 1000000)
    ...> assert Common.uptime_to_string(start_time) == "<1m ago"
    ...> start_time = System.monotonic_time() - (:timer.seconds(60) * 1000000)
    ...> assert Common.uptime_to_string(start_time) == "1m ago"
    ...> start_time = System.monotonic_time() - (:timer.hours(1) * 1000000)
    ...> assert Common.uptime_to_string(start_time) == "1h ago"
    ...> start_time = System.monotonic_time() - (:timer.hours(24) * 1000000)
    ...> assert Common.uptime_to_string(start_time) == "1d ago"
    ...> start_time = System.monotonic_time() - (:timer.hours(24 * 35) * 1000000)
    ...> assert Common.uptime_to_string(start_time) == "1m ago"
  """
  def uptime_to_string(nil), do: "-/-"

  def uptime_to_string(start_time) do
    diff = System.convert_time_unit(System.monotonic_time() - start_time, :native, :second)

    case diff do
      uptime when uptime < 10 -> "now"
      uptime when uptime < @sec_in_minute -> "<1m ago"
      uptime when uptime < @sec_in_hour -> "#{trunc(uptime / @sec_in_minute)}m ago"
      uptime when uptime < @sec_in_day -> "#{trunc(uptime / @sec_in_hour)}h ago"
      uptime when uptime <= @sec_in_months -> "#{trunc(uptime / @sec_in_day)}d ago"
      uptime -> "#{trunc(uptime / @sec_in_months)}m ago"
    end
  end

  @doc """
  This function calls gen_server with try catch

  NOTE: This function needs to use try/catch because rescue (suggested by credo)
        doesn't handle :exit

  ## Examples

    iex> alias Deployex.Common
    ...> {:ok, valid_pid} = GenServer.start_link(Deployex.MyGenServer, [])
    ...> invalid_pid = spawn(fn -> :ok end)
    ...> assert Common.call_gen_server(valid_pid, "any-message") == :ok
    ...> assert Common.call_gen_server(invalid_pid, "any-message") == {:error, :rescued}
    ...> {:ok, pid} = GenServer.start_link(Deployex.MyGenServer, [])
    ...> valid_name = %{a: 1}
    ...> assert :yes == :global.register_name(valid_name, pid)
    ...> assert Common.call_gen_server(valid_name, "any-message") == :ok
    ...> assert Common.call_gen_server(%{}, "any-message") == {:error, :rescued}
  """
  @spec call_gen_server(pid() | map() | atom(), any()) :: :ok | {:ok, any()} | {:error, any()}
  def call_gen_server(key, message) when is_pid(key) or is_atom(key) do
    try do
      GenServer.call(key, message)
    catch
      _, _ ->
        {:error, :rescued}
    end
  end

  def call_gen_server(key, message) do
    try do
      GenServer.call({:global, key}, message)
    catch
      _, _ ->
        {:error, :rescued}
    end
  end

  @doc """
  This function converts string keys maps to structure maps

  ## Examples

    iex> alias Deployex.Common
    ...> %Deployex.Storage.Config{mode: :manual, manual_version: nil} = Common.cast_schema_fields(%{"mode" => "manual"}, %Deployex.Storage.Config{}, atoms: [:mode])
    ...> %Deployex.Storage.Config{mode: :manual, manual_version: nil} = Common.cast_schema_fields(%{mode: "manual"}, %Deployex.Storage.Config{}, atoms: [:mode])
    ...> %Deployex.Storage.Config{mode: :automatic, manual_version: "v1"} = Common.cast_schema_fields(%{manual_version: "v1"}, %Deployex.Storage.Config{}, atoms: [:mode])
    ...> %Deployex.Storage.Config{mode: :automatic, manual_version: nil} = Common.cast_schema_fields(nil, %Deployex.Storage.Config{}, atoms: [:mode])
  """
  def cast_schema_fields(data, struct, attrs \\ [])

  def cast_schema_fields(nil, struct, _attrs) do
    struct
  end

  def cast_schema_fields(data, struct, attrs) do
    atoms = Keyword.get(attrs, :atoms, [])
    struct_keys = struct |> Map.keys() |> List.delete(:__struct__)

    struct_keys
    |> Enum.reduce(struct, fn key, acc ->
      value = Map.get(data, key) || Map.get(data, key |> to_string(), nil)

      value =
        if key in atoms and value != nil do
          value |> String.to_existing_atom()
        else
          value
        end

      if value, do: acc |> Map.put(key, value), else: acc
    end)
  end

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================
end
