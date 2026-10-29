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

  @doc """
  Reads the memory in use the way Activity Monitor shows it, as app memory, wired and compressed pages.
  `Pages free` alone is small on almost any Mac, because macOS keeps memory in caches that it gives back.
  """
  @spec get_macos() :: t()
  def get_macos do
    with {:ok, [{:stdout, stdout_vm_stat}]} <- Commander.run("vm_stat", [:stdout, :sync]),
         {:ok, [{:stdout, stdout_hw_memsize}]} <-
           Commander.run("sysctl -n hw.memsize", [:stdout, :sync]),
         {page_size, pages} <- parse_vm_stat(Enum.join(stdout_vm_stat)),
         {memory_total, ""} <-
           stdout_hw_memsize |> Enum.join() |> String.trim() |> Integer.parse() do
      %__MODULE__{
        memory_total: memory_total,
        memory_free: macos_free(page_size, pages, memory_total)
      }
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

  # Used is app memory (anonymous less purgeable pages), wired and compressed pages, as Activity Monitor
  # counts it. An older vm_stat with no anonymous pages counts free, inactive, speculative and purgeable
  defp macos_free(page_size, %{"Anonymous pages" => anonymous} = pages, memory_total) do
    used =
      anonymous - Map.get(pages, "Pages purgeable", 0) + Map.get(pages, "Pages wired down", 0) +
        Map.get(pages, "Pages occupied by compressor", 0)

    max(memory_total - used * page_size, 0)
  end

  defp macos_free(page_size, pages, _memory_total) do
    ["Pages free", "Pages inactive", "Pages speculative", "Pages purgeable"]
    |> Enum.map(&Map.get(pages, &1, 0))
    |> Enum.sum()
    |> Kernel.*(page_size)
  end

  # Each line reads "Label:   1234." after a header with the page size
  defp parse_vm_stat(text) do
    [header | lines] = String.split(text, "\n", trim: true)

    with [_, size] <- Regex.run(~r/page size of (\d+) bytes/, header) do
      pages =
        for line <- lines,
            [label, value] <- [String.split(line, ":", parts: 2)],
            {count, "."} <- [value |> String.trim() |> Integer.parse()],
            into: %{} do
          {label |> String.trim() |> String.trim("\""), count}
        end

      {String.to_integer(size), pages}
    end
  end
end
