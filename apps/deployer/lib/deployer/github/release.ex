defmodule Deployer.Github.Release do
  @moduledoc """
  This module contains deployex information about the latest release
  """

  use GenServer

  require Logger

  alias Foundation.Common

  @type t :: %__MODULE__{
          tag_name: String.t(),
          prerelease: boolean(),
          new_release?: boolean(),
          created_at: String.t() | nil,
          updated_at: String.t() | nil,
          published_at: String.t() | nil
        }

  defstruct tag_name: "",
            prerelease: false,
            new_release?: false,
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

    with {:ok, %{body: body}} <- response,
         {:ok, info} <- Jason.decode(body) do
      tag_name = info["tag_name"]
      prerelease = info["prerelease"]
      current_version = Application.spec(:foundation, :vsn) |> to_string

      new_release? =
        tag_name != nil and prerelease == false and new_release?(current_version, tag_name)

      %__MODULE__{
        tag_name: tag_name,
        prerelease: prerelease,
        new_release?: new_release?,
        created_at: info["created_at"],
        updated_at: info["updated_at"],
        published_at: info["published_at"]
      }
    else
      _any ->
        # NOTE: Keep the latest state, since the application may not have acceess to
        #       network or GitHub is not available
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

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================
  defp new_release?(current_version, tag_version) do
    with {:ok, current} <- parse_version(current_version),
         {:ok, tag} <- parse_version(tag_version) do
      compare_versions(current, tag) == :lt
    else
      _ -> false
    end
  end

  defp parse_version(version) do
    case Version.parse(version) do
      {:ok, parsed} -> {:ok, parsed}
      :error -> :error
    end
  end

  defp compare_versions(v1, v2) do
    Version.compare(v1, v2)
  end
end
