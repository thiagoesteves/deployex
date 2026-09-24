defmodule Deployer.SelfUpgrade.Executor.Shell do
  @moduledoc """
  Executes a self-upgrade by shelling out to the deployex.sh installer.

  `hot_upgrade/1` runs `deployex.sh --hot-upgrade`, passing `--set-version` so the
  target version comes from the reconciler, not the on-disk config.
  """

  @behaviour Deployer.SelfUpgrade.Executor.Adapter

  require Logger

  @impl true
  @spec hot_upgrade(String.t()) :: :ok | {:error, any()}
  def hot_upgrade(version), do: run("--hot-upgrade", version)

  defp run(op, version) do
    args = [op, config_file(), "--set-version", version] ++ dist_args()

    # The installer runs `deployex rpc` against the running node. That RPC needs
    # the live distribution cookie, which the secrets provider may have set via
    # Node.set_cookie/2 at boot, leaving the OS RELEASE_COOKIE env at its stale
    # default. Pass the live cookie so the ephemeral rpc node connects.
    env = [{"RELEASE_COOKIE", Node.get_cookie() |> to_string()}]

    case System.cmd(script(), args, stderr_to_stdout: true, env: env) do
      {out, 0} ->
        Logger.info("Self-upgrade #{op} to #{version} ok: #{out}")
        :ok

      {out, code} ->
        Logger.error("Self-upgrade #{op} to #{version} failed (#{code}): #{out}")
        {:error, {:exit, code}}
    end
  end

  defp opts, do: Application.get_env(:deployer, Deployer.SelfUpgrade, [])
  defp script, do: opts()[:script] || "/home/root/deployex.sh"
  defp config_file, do: opts()[:config_file] || "/home/root/deployex.yaml"

  defp dist_args do
    case opts()[:dist_base_url] do
      nil -> []
      url -> ["--dist", url]
    end
  end
end
