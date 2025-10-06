defmodule Deployer.Github do
  @moduledoc """
  This module contains deployex information about the latest release
  """

  use GenServer

  require Logger

  alias Foundation.Common

  @type t :: %__MODULE__{
          tag_name: String.t(),
          prerelease: false,
          created_at: String.t() | nil,
          updated_at: String.t() | nil,
          published_at: String.t() | nil
        }

  defstruct tag_name: "",
            prerelease: false,
            created_at: nil,
            updated_at: nil,
            published_at: nil

  @update_github_interval :timer.hours(1)
  @deployex_latest_tag "https://api.github.com/repos/thiagoesteves/deployex/releases/latest"

  ### ==========================================================================
  ### Callback GenServer functions
  ### ==========================================================================
  def start_link(args) do
    name = Keyword.get(args, :name, __MODULE__)

    GenServer.start_link(__MODULE__, args, name: name)
  end

  @impl true
  def init(args) do
    args
    |> Keyword.get(:update_github_interval, @update_github_interval)
    |> :timer.send_interval(:updated_github_info)

    {:ok, update_github_info()}
  end

  @impl true
  def handle_info(:updated_github_info, state) do
    {:noreply, update_github_info(state)}
  end

  @impl true
  def handle_call(:latest_release, _from, state) do
    {:reply, {:ok, state}, state}
  end

  def update_github_info(state \\ %__MODULE__{}) do
    response =
      :get
      |> Finch.build(@deployex_latest_tag, [], [])
      |> Finch.request(Deployer.Finch)

    case response do
      {:ok, %{body: body}} ->
        info = Jason.decode!(body)

        %__MODULE__{
          tag_name: info["tag_name"],
          prerelease: info["prerelease"],
          created_at: info["created_at"],
          updated_at: info["updated_at"],
          published_at: info["published_at"]
        }

      {:error, reason} ->
        Logger.error(
          "Error while trying to get github repo information, reason: #{inspect(reason)}"
        )

        # NOTE: Keep the latest state, since github can be
        state
    end
  end

  ### ==========================================================================
  ### Public functions
  ### ==========================================================================
  @spec latest_release(module :: module()) :: {:ok, __MODULE__.t()}
  def latest_release(module \\ __MODULE__) do
    Common.call_gen_server(module, :latest_release)
  end
end
