defmodule Host.Info.Cpu do
  @moduledoc """
  Reads host cpu info across Linux, macOS, and Windows platforms.
  """

  alias Host.Commander

  @type t :: %__MODULE__{
          cpu: nil | non_neg_integer(),
          cpus: nil | non_neg_integer()
        }

  defstruct cpu: nil,
            cpus: nil

  ### ==========================================================================
  ### Public APIs
  ### ==========================================================================

  @spec get_linux() :: t()
  def get_linux do
    with {:ok, [{:stdout, stdout_nproc}]} <- Commander.run("nproc", [:stdout, :sync]),
         {:ok, [{:stdout, stdout_pcpu}]} <-
           Commander.run("ps -eo pcpu", [:stdout, :sync]) do
      cpus = stdout_nproc |> Enum.join() |> String.trim() |> String.to_integer()

      [_title | cpu_utilization] =
        stdout_pcpu
        |> Enum.join()
        |> String.split("\n", trim: true)

      cpu = cpu_sum(cpu_utilization)
      %__MODULE__{cpus: cpus, cpu: Float.round(cpu, 2)}
    else
      _ ->
        %__MODULE__{}
    end
  end

  @spec get_macos() :: t()
  def get_macos do
    with {:ok, [{:stdout, stdout_hw_ncpu}]} <-
           Commander.run("sysctl -n hw.ncpu", [:stdout, :sync]),
         {:ok, [{:stdout, stdout_ps_cpu}]} <- Commander.run("ps -A -o %cpu", [:stdout, :sync]) do
      cpus = stdout_hw_ncpu |> Enum.join() |> String.trim() |> String.to_integer()

      [_title | cpu_utilization] =
        stdout_ps_cpu
        |> Enum.join()
        |> String.split("\n", trim: true)

      cpu = cpu_sum(cpu_utilization)

      %__MODULE__{cpus: cpus, cpu: Float.round(cpu, 2)}
    else
      _ ->
        %__MODULE__{}
    end
  end

  @spec get_windows() :: t()
  def get_windows, do: %__MODULE__{}

  ### ==========================================================================
  ### Private Functions
  ### ==========================================================================

  defp cpu_sum(cpu_list) do
    Enum.reduce(cpu_list, 0.0, fn cpu_line, acc ->
      case cpu_line |> String.trim() |> Float.parse() do
        {cpu, _} ->
          acc + cpu

        _ ->
          acc
      end
    end)
  end
end
