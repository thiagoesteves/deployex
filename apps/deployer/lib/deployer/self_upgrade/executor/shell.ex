defmodule Deployer.SelfUpgrade.Executor.Shell do
  @moduledoc """
  Builds the self-upgrade command for the deployex.sh installer.

  `hot_upgrade_command/1` returns `deployex.sh --hot-upgrade` with `--set-version`, so the
  target version comes from the reconciler, not the on-disk config.

  On an instance provisioned before this feature the on-disk `deployex.sh` predates
  `--set-version` (and cloud-init does not refresh it on a version bump), so the run is
  gated on the script actually supporting the flag. Without the gate the old script would
  reject the flag, the worker would latch the version, and self-upgrade would be silently
  dead. See the hot-upgrades guide for the one-time refresh.
  """

  @behaviour Deployer.SelfUpgrade.Executor.Adapter

  require Logger

  @impl true
  @spec hot_upgrade_command(String.t()) ::
          {:ok, Deployer.SelfUpgrade.Executor.Adapter.command()} | {:error, any()}
  def hot_upgrade_command(version) do
    with :ok <- ensure_installer_supports_flags() do
      {:ok, command("--hot-upgrade", version)}
    end
  end

  # The installer must know --set-version. An older on-box script does not, and would
  # otherwise fail with a cryptic "Invalid option" that the worker latches. Report a clear,
  # actionable error instead.
  defp ensure_installer_supports_flags do
    path = script()

    case File.read(path) do
      {:ok, contents} ->
        if String.contains?(contents, "--set-version") do
          :ok
        else
          Logger.error(
            "Self-upgrade: #{path} predates --set-version. Refresh it with the new release's " <>
              "deployex.sh before self-upgrade can run (see the hot-upgrades guide)."
          )

          {:error, :installer_outdated}
        end

      {:error, reason} ->
        Logger.error("Self-upgrade: cannot read installer at #{path}: #{inspect(reason)}")
        {:error, {:installer_unreadable, reason}}
    end
  end

  defp command(op, version) do
    args = [op, config_file(), "--set-version", version] ++ dist_args()

    # The installer runs `deployex rpc` against the running node. That RPC needs
    # the live distribution cookie, which the secrets provider may have set via
    # Node.set_cookie/2 at boot, leaving the OS RELEASE_COOKIE env at its stale
    # default. Pass the live cookie so the ephemeral rpc node connects.
    env = [{"RELEASE_COOKIE", Node.get_cookie() |> to_string()}]

    {script(), args, [stderr_to_stdout: true, env: env]}
  end

  defp opts, do: Application.get_env(:deployer, Deployer.SelfUpgrade, [])
  defp script, do: opts()[:script] || "/home/root/deployex.sh"

  # The yaml DeployEx itself loaded. The systemd unit sets DEPLOYEX_CONFIG_YAML_PATH.
  defp config_file do
    yaml_path = System.get_env("DEPLOYEX_CONFIG_YAML_PATH")
    opts()[:config_file] || yaml_path || "/home/root/deployex.yaml"
  end

  defp dist_args, do: dist_args(opts()[:dist_base_url])

  # `dist_base_url` is a base with per-version paths (e.g. .../releases/download), so
  # append the installer's {version} placeholder unless the URL already has one. The
  # installer uses a --dist URL without a placeholder as-is (flat bucket).
  @doc false
  @spec dist_args(String.t() | nil) :: [String.t()]
  def dist_args(nil), do: []

  def dist_args(url) do
    if String.contains?(url, "{version}"),
      do: ["--dist", url],
      else: ["--dist", String.trim_trailing(url, "/") <> "/{version}"]
  end
end
