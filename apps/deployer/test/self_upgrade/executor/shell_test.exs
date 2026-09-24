defmodule Deployer.SelfUpgrade.Executor.ShellTest do
  use ExUnit.Case, async: true

  alias Deployer.SelfUpgrade.Executor.Shell

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
