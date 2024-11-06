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

  @doc """
  Generates a random, version 4 UUID.
  """
  @spec uuid4() :: binary()
  def uuid4(), do: encode(bingenerate())

  @doc """
  Generates a random, version 4 UUID in the binary format.
  """
  @spec bingenerate() :: binary()
  def bingenerate() do
    <<u0::48, _::4, u1::12, _::2, u2::62>> = :crypto.strong_rand_bytes(16)
    <<u0::48, 4::4, u1::12, 2::2, u2::62>>
  end

  @spec encode(binary()) :: binary()
  defp encode(
         <<a1::4, a2::4, a3::4, a4::4, a5::4, a6::4, a7::4, a8::4, b1::4, b2::4, b3::4, b4::4,
           c1::4, c2::4, c3::4, c4::4, d1::4, d2::4, d3::4, d4::4, e1::4, e2::4, e3::4, e4::4,
           e5::4, e6::4, e7::4, e8::4, e9::4, e10::4, e11::4, e12::4>>
       ) do
    <<e(a1), e(a2), e(a3), e(a4), e(a5), e(a6), e(a7), e(a8), ?-, e(b1), e(b2), e(b3), e(b4), ?-,
      e(c1), e(c2), e(c3), e(c4), ?-, e(d1), e(d2), e(d3), e(d4), ?-, e(e1), e(e2), e(e3), e(e4),
      e(e5), e(e6), e(e7), e(e8), e(e9), e(e10), e(e11), e(e12)>>
  end

  @compile {:inline, e: 1}

  defp e(0), do: ?0
  defp e(1), do: ?1
  defp e(2), do: ?2
  defp e(3), do: ?3
  defp e(4), do: ?4
  defp e(5), do: ?5
  defp e(6), do: ?6
  defp e(7), do: ?7
  defp e(8), do: ?8
  defp e(9), do: ?9
  defp e(10), do: ?a
  defp e(11), do: ?b
  defp e(12), do: ?c
  defp e(13), do: ?d
  defp e(14), do: ?e
  defp e(15), do: ?f

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================
end
