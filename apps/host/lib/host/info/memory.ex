defmodule Host.Info.Memory do
  @moduledoc """
  Reads host memory info across Linux, macOS, and Windows platforms.
  """

  alias Host.Commander

  @type t :: %__MODULE__{
          memory_free: nil | non_neg_integer(),
          memory_total: nil | non_neg_integer()
        }

  defstruct memory_free: nil,
            memory_total: nil

  ### ==========================================================================
  ### Public APIs
  ### ==========================================================================

  @spec get_linux() :: t()
  def get_linux do
    case Commander.run("free -b", [:stdout, :sync]) do
      {:ok, [{:stdout, stdout_free}]} ->
        free_list =
          stdout_free
          |> Enum.join()
          |> String.split("\n", trim: true)
          |> Enum.at(1)
          |> String.split()

        memory_total = free_list |> Enum.at(1) |> String.to_integer()
        memory_free = free_list |> Enum.at(6) |> String.to_integer()
        %__MODULE__{memory_total: memory_total, memory_free: memory_free}

      _ ->
        %__MODULE__{}
    end
  end

  @spec get_macos() :: t()
  def get_macos do
    with {:ok, [{:stdout, stdout_vm_stat}]} <- Commander.run("vm_stat", [:stdout, :sync]),
         {:ok, [{:stdout, stdout_hw_memsize}]} <-
           Commander.run("sysctl -n hw.memsize", [:stdout, :sync]) do
      info_list = stdout_vm_stat |> Enum.join() |> String.split("\n")

      [page_size_text] =
        String.split(
          Enum.at(info_list, 0),
          ["Mach Virtual Memory Statistics: (page size of ", " bytes)"],
          trim: true
        )

      [page_free_text] = String.split(Enum.at(info_list, 1), ["Pages free:", "."], trim: true)

      page_size = page_size_text |> String.trim() |> String.to_integer()
      page_free = page_free_text |> String.trim() |> String.to_integer()

      memory_total = stdout_hw_memsize |> Enum.join() |> String.trim() |> String.to_integer()

      %__MODULE__{memory_total: memory_total, memory_free: page_size * page_free}
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
end
