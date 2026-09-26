defmodule Deployer.SelfUpgrade.Executor.ShellTest do
  # Not async: hot_upgrade_command/1 reads the application env and DEPLOYEX_CONFIG_YAML_PATH.
  use ExUnit.Case, async: false

  alias Deployer.SelfUpgrade.Executor.Shell

  describe "hot_upgrade_command/1" do
    @describetag :tmp_dir

    setup %{tmp_dir: tmp_dir} do
      script = Path.join(tmp_dir, "deployex.sh")
      File.write!(script, "# supports --set-version\n")

      config = Application.get_env(:deployer, Deployer.SelfUpgrade)
      yaml_path = System.get_env("DEPLOYEX_CONFIG_YAML_PATH")
      Application.put_env(:deployer, Deployer.SelfUpgrade, script: script)

      on_exit(fn ->
        Application.put_env(:deployer, Deployer.SelfUpgrade, config)

        if yaml_path,
          do: System.put_env("DEPLOYEX_CONFIG_YAML_PATH", yaml_path),
          else: System.delete_env("DEPLOYEX_CONFIG_YAML_PATH")
      end)

      %{script: script}
    end

    test "passes the yaml file DeployEx runs with", %{script: script} do
      System.put_env("DEPLOYEX_CONFIG_YAML_PATH", "/etc/deployex/deployex.yaml")

      assert {:ok, {^script, ["--hot-upgrade", "/etc/deployex/deployex.yaml" | _], _opts}} =
               Shell.hot_upgrade_command("1.2.3")
    end

    test "falls back to /home/root/deployex.yaml", %{script: script} do
      System.delete_env("DEPLOYEX_CONFIG_YAML_PATH")

      assert {:ok, {^script, ["--hot-upgrade", "/home/root/deployex.yaml" | _], _opts}} =
               Shell.hot_upgrade_command("1.2.3")
    end
  end

  describe "dist_args/1" do
    test "no base URL passes no --dist" do
      assert Shell.dist_args(nil) == []
    end

    test "a base URL gets the {version} placeholder appended" do
      assert Shell.dist_args("https://github.com/o/deployex/releases/download") ==
               ["--dist", "https://github.com/o/deployex/releases/download/{version}"]

      assert Shell.dist_args("https://github.com/o/deployex/releases/download/") ==
               ["--dist", "https://github.com/o/deployex/releases/download/{version}"]
    end

    test "a URL with a {version} placeholder is passed as-is" do
      assert Shell.dist_args("https://example.com/{version}/rel") ==
               ["--dist", "https://example.com/{version}/rel"]
    end
  end
end
