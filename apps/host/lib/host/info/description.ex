defmodule Host.Info.Description do
  @moduledoc """
  Reads host description across Linux, macOS, and Windows platforms.
  """

  alias Host.Commander

  @type t :: %__MODULE__{
          host: String.t(),
          description: nil | String.t()
        }

  defstruct host: "",
            description: nil

  ### ==========================================================================
  ### Public APIs
  ### ==========================================================================

  @spec get_linux() :: t()
  def get_linux do
    case Commander.run("cat /etc/os-release | grep VERSION= | sed 's/VERSION=//; s/\"//g'", [
           :stdout,
           :sync
         ]) do
      {:ok, [{:stdout, stdout}]} ->
        description = stdout |> Enum.join() |> String.trim()

        %__MODULE__{host: "Linux", description: description}

      _ ->
        %__MODULE__{host: "Linux"}
    end
  end

  @spec get_macos() :: t()
  def get_macos do
    case Commander.run("sw_vers -productVersion", [:stdout, :sync]) do
      {:ok, [{:stdout, stdout}]} ->
        description = stdout |> Enum.join() |> String.trim()

        %__MODULE__{host: "macOS", description: description}

      _ ->
        %__MODULE__{host: "macOS"}
    end
  end

  @spec get_windows() :: t()
  def get_windows, do: %__MODULE__{host: "Windows"}

  ### ==========================================================================
  ### Private Functions
  ### ==========================================================================
end
