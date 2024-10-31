defmodule Deployex.UpgradeAppTest do
  use ExUnit.Case, async: false

  import Mox
  import Mock
  import ExUnit.CaptureLog

  alias Deployex.Fixture.Storage, as: FixtureStorage
  alias Deployex.Storage
  alias Deployex.Upgrade.Application, as: UpgradeApp

  @valid_appup_file """
      { "0.2.0",
      [{ "0.1.0",
          [{update,test_app_sm,{advanced,[]},brutal_purge,brutal_purge,[]},
           {load_module,testapp_wbs_server,brutal_purge,brutal_purge,
                        [test_app_sm]}] }],
      [{ "0.1.0",
          [{load_module,testapp_wbs_server,brutal_purge,brutal_purge,
                        [test_app_sm]},
           {update,test_app_sm,{advanced,[]},brutal_purge,brutal_purge,[]}] }]
  }.
  """

  @incorrect_version_appup_file """
      { "9.9.9",
      [{ "0.1.0",
          [{update,test_app_sm,{advanced,[]},brutal_purge,brutal_purge,[]},
           {load_module,testapp_wbs_server,brutal_purge,brutal_purge,
                        [test_app_sm]}] }],
      [{ "0.1.0",
          [{load_module,testapp_wbs_server,brutal_purge,brutal_purge,
                        [test_app_sm]},
           {update,test_app_sm,{advanced,[]},brutal_purge,brutal_purge,[]}] }]
  }.
  """

  @invalid_appup_file """
  { "9.9.9",
  [{ "0.1.0",
      [{update,test_app_sm,{advanced,[]},brutal_purge,brutal_purge,[]},
       {load_module,testapp_wbs_server,brutal_purge,brutal_purge,
                    [test_app_sm]}] }],
  """

  @release_file """
  {release,{"testapp","0.1.3"},
       {erts,"14.1.1"},
       [{kernel,"9.1"},
        {stdlib,"5.1.1"},
        {crypto,"5.3"},
        {cowlib,"2.10.1"},
        {asn1,"5.2"},
        {public_key,"1.14.1"},
        {ssl,"11.0.3"},
        {ranch,"1.7.1"},
        {cowboy,"2.8.0"},
        {gproc,"0.9.0"},
        {jsone,"1.5.5"},
        {inets,"9.0.2"},
        {testapp,"0.1.3"},
        {sasl,"4.2.1"}]}.
  """
  @releases_file [
    {~c"testapp", ~c"0.2.0",
     [
       ~c"kernel-9.1",
       ~c"stdlib-5.1.1",
       ~c"crypto-5.3",
       ~c"cowlib-2.10.1",
       ~c"asn1-5.2",
       ~c"public_key-1.14.1",
       ~c"ssl-11.0.3",
       ~c"ranch-1.7.1",
       ~c"cowboy-2.8.0",
       ~c"gproc-0.9.0",
       ~c"jsone-1.5.5",
       ~c"inets-9.0.2",
       ~c"testapp-0.2.0",
       ~c"sasl-4.2.1"
     ], :permanent},
    {~c"testapp", ~c"0.1.0",
     [
       ~c"kernel-9.1",
       ~c"stdlib-5.1.1",
       ~c"crypto-5.3",
       ~c"cowlib-2.10.1",
       ~c"asn1-5.2",
       ~c"public_key-1.14.1",
       ~c"ssl-11.0.3",
       ~c"ranch-1.7.1",
       ~c"cowboy-2.8.0",
       ~c"gproc-0.9.0",
       ~c"jsone-1.5.5",
       ~c"inets-9.0.2",
       ~c"testapp-0.1.0",
       ~c"sasl-4.2.1"
     ], :old}
  ]

  @expected_timeout 300_000

  setup do
    FixtureStorage.cleanup()
    {:ok, hostname} = :inet.gethostname()

    app_name = "testapp"
    instance = 1

    %{
      node: :"#{app_name}-#{instance}@#{hostname}",
      app_name: app_name,
      instance: instance,
      from_version: "0.1.0",
      to_version: "0.2.0",
      base_path: Application.get_env(:deployex, :base_path)
    }
  end

  test "connect/1 success connecting to the monitored app", %{
    node: node,
    instance: instance
  } do
    with_mock Node, connect: fn ^node -> true end do
      assert {:ok, ^node} = UpgradeApp.connect(instance)
    end
  end

  test "connect/1 error while trying to connect to the monitored app", %{
    node: node,
    instance: instance
  } do
    with_mock Node, connect: fn ^node -> false end do
      assert capture_log(fn ->
               assert {:error, :not_connecting} = UpgradeApp.connect(instance)
             end) =~ "Error while trying to connect with node:"
    end
  end

  test "check/1 Elixir full deployment", %{
    app_name: app_name,
    instance: instance,
    from_version: from_version,
    to_version: to_version
  } do
    assert capture_log(fn ->
             assert {:ok, :full_deployment} =
                      UpgradeApp.check(
                        instance,
                        app_name,
                        "elixir",
                        ".",
                        from_version,
                        to_version
                      )
           end) =~ "HOT UPGRADE version NOT DETECTED, full deployment required, result"
  end

  test "check/1 Elixir valid appup, return hot upgrade detected", %{
    app_name: app_name,
    instance: instance,
    from_version: from_version,
    to_version: to_version,
    base_path: base_path
  } do
    new_lib_ebin_path = "#{Storage.new_path(instance)}/lib/#{app_name}-#{to_version}/ebin"
    current_releases_path = "#{Storage.current_path(instance)}/releases/#{to_version}"
    File.mkdir_p!(new_lib_ebin_path)
    File.mkdir_p!(current_releases_path)
    File.write("#{new_lib_ebin_path}/#{app_name}.appup", @valid_appup_file)
    File.write("#{base_path}/#{app_name}-#{to_version}.tar.gz", "")

    assert capture_log(fn ->
             assert {:ok, :hot_upgrade} =
                      UpgradeApp.check(
                        instance,
                        app_name,
                        "elixir",
                        "#{base_path}/#{app_name}-#{to_version}.tar.gz",
                        from_version,
                        to_version
                      )

             assert File.exists?("#{current_releases_path}/#{app_name}.tar.gz")
           end) =~ "HOT UPGRADE version DETECTED, from: #{from_version} to: #{to_version}"
  end

  test "check/1 Elixir invalid appup version, return hot upgrade detected", %{
    app_name: app_name,
    instance: instance,
    from_version: from_version,
    to_version: to_version
  } do
    new_lib_ebin_path = "#{Storage.new_path(instance)}/lib/#{app_name}-#{to_version}/ebin"
    File.mkdir_p!(new_lib_ebin_path)
    File.write("#{new_lib_ebin_path}/#{app_name}.appup", @incorrect_version_appup_file)

    assert capture_log(fn ->
             assert {:ok, :full_deployment} =
                      UpgradeApp.check(
                        instance,
                        app_name,
                        "elixir",
                        ".",
                        from_version,
                        to_version
                      )
           end) =~ "HOT UPGRADE version NOT DETECTED, full deployment required, result"
  end

  test "check/1 Elixir invalid appup file, return hot upgrade detected", %{
    app_name: app_name,
    instance: instance,
    from_version: from_version,
    to_version: to_version
  } do
    new_lib_ebin_path = "#{Storage.new_path(instance)}/lib/testapp-0.2.0/ebin"
    File.mkdir_p!(new_lib_ebin_path)
    File.write("#{new_lib_ebin_path}/testapp.appup", @invalid_appup_file)

    assert capture_log(fn ->
             assert {:ok, :full_deployment} =
                      UpgradeApp.check(
                        instance,
                        app_name,
                        "elixir",
                        ".",
                        from_version,
                        to_version
                      )
           end) =~ "Error while reading appup file, reason:"
  end

  test "check/1 Erlang full deployment", %{
    app_name: app_name,
    instance: instance,
    from_version: from_version,
    to_version: to_version
  } do
    assert capture_log(fn ->
             assert {:ok, :full_deployment} =
                      UpgradeApp.check(
                        instance,
                        app_name,
                        "erlang",
                        ".",
                        from_version,
                        to_version
                      )
           end) =~ "HOT UPGRADE version NOT DETECTED, full deployment required, result"
  end

  test "check/1 Erlang valid appup, return hot upgrade detected", %{
    app_name: app_name,
    instance: instance,
    from_version: from_version,
    to_version: to_version,
    base_path: base_path
  } do
    new_lib_ebin_path = "#{Storage.new_path(instance)}/lib/#{app_name}-#{to_version}/ebin"
    new_lib_priv_path = "#{Storage.new_path(instance)}/lib/#{app_name}-#{to_version}/priv"
    new_releases_path = "#{Storage.new_path(instance)}/releases"
    current_releases_path = "#{Storage.current_path(instance)}/releases/#{to_version}"

    File.mkdir_p!(new_lib_ebin_path)
    File.mkdir_p!(new_lib_priv_path)
    File.mkdir_p!(new_releases_path)
    File.mkdir_p!(current_releases_path)

    File.write("#{new_lib_priv_path}/#{app_name}.appup", @valid_appup_file)
    File.write("#{new_releases_path}/#{app_name}.rel", @release_file)
    File.write("#{base_path}/#{app_name}-#{to_version}.tar.gz", "")

    assert capture_log(fn ->
             assert {:ok, :hot_upgrade} =
                      UpgradeApp.check(
                        instance,
                        app_name,
                        "erlang",
                        "#{base_path}/#{app_name}-#{to_version}.tar.gz",
                        from_version,
                        to_version
                      )

             assert File.exists?("#{new_releases_path}/#{app_name}-#{to_version}.rel")
             refute File.exists?("#{new_releases_path}/#{app_name}.rel")
             assert File.exists?("#{current_releases_path}/#{app_name}.tar.gz")
           end) =~ "HOT UPGRADE version DETECTED, from: #{from_version} to: #{to_version}"
  end

  test "check/1 Gleam full deployment", %{
    app_name: app_name,
    instance: instance,
    from_version: from_version,
    to_version: to_version
  } do
    assert capture_log(fn ->
             assert {:ok, :full_deployment} =
                      UpgradeApp.check(instance, app_name, "gleam", ".", from_version, to_version)
           end) =~ "HOT UPGRADE version NOT DETECTED, full deployment required, result"
  end

  test "which_releases/1", %{node: node} do
    Deployex.RpcMock
    |> expect(:call, fn ^node, :release_handler, :which_releases, [], @expected_timeout ->
      @releases_file
    end)

    assert [permanent: ~c"0.2.0", old: ~c"0.1.0"] = UpgradeApp.which_releases(node)
  end

  test "make_relup/1 Elixir success", %{
    node: node,
    app_name: app_name,
    instance: instance,
    from_version: from_version,
    to_version: to_version
  } do
    root = ~c"/tmp/deployex/varlib/service/#{app_name}/1/current"

    Deployex.RpcMock
    |> expect(:call, fn ^node, :code, :root_dir, [], @expected_timeout ->
      root
    end)
    |> expect(:call, fn ^node, :systools, :make_relup, _params, @expected_timeout ->
      :ok
    end)

    assert :ok =
             UpgradeApp.make_relup(node, instance, app_name, "elixir", from_version, to_version)
  end

  test "make_relup/1 Elixir error", %{
    node: node,
    app_name: app_name,
    instance: instance,
    from_version: from_version,
    to_version: to_version
  } do
    root = ~c"/tmp/deployex/varlib/service/#{app_name}/1/current"

    Deployex.RpcMock
    |> expect(:call, fn ^node, :code, :root_dir, [], @expected_timeout ->
      root
    end)
    |> expect(:call, fn ^node, :systools, :make_relup, _params, @expected_timeout ->
      :badrpc
    end)

    assert capture_log(fn ->
             assert {:error, :make_relup} =
                      UpgradeApp.make_relup(
                        node,
                        instance,
                        app_name,
                        "elixir",
                        from_version,
                        to_version
                      )
           end) =~ "systools:make_relup failed, reason: :badrpc"
  end

  test "make_relup/1 Erlang success", %{
    node: node,
    app_name: app_name,
    instance: instance,
    from_version: from_version,
    to_version: to_version
  } do
    root = ~c"/tmp/deployex/varlib/service/#{app_name}/1/current"

    new_lib_priv_path = "#{Storage.new_path(instance)}/lib/#{app_name}-#{to_version}/priv"
    current_lib_ebin_path = "#{Storage.current_path(instance)}/lib/#{app_name}-#{to_version}/ebin"
    current_releases_path = "#{Storage.current_path(instance)}/releases"

    File.mkdir_p!(new_lib_priv_path)
    File.mkdir_p!(current_lib_ebin_path)
    File.mkdir_p!(current_releases_path)

    File.write("#{new_lib_priv_path}/#{app_name}.appup", @valid_appup_file)
    File.write("#{current_releases_path}/#{app_name}.rel", @release_file)

    Deployex.RpcMock
    |> expect(:call, fn ^node, :code, :root_dir, [], @expected_timeout ->
      root
    end)
    |> expect(:call, fn ^node, :systools, :make_relup, _params, @expected_timeout ->
      :ok
    end)

    assert :ok =
             UpgradeApp.make_relup(node, instance, app_name, "erlang", from_version, to_version)

    assert File.exists?("#{current_lib_ebin_path}/#{app_name}.appup")
    assert File.exists?("#{current_releases_path}/#{app_name}-#{to_version}.rel")
    refute File.exists?("#{current_releases_path}/#{app_name}.rel")
  end

  test "unpack_release/1 success", %{node: node, app_name: app_name, to_version: to_version} do
    release_link = "#{to_version}/#{app_name}" |> to_charlist

    Deployex.RpcMock
    |> expect(:call, fn ^node,
                        :release_handler,
                        :unpack_release,
                        [^release_link],
                        @expected_timeout ->
      {:ok, to_version}
    end)

    assert :ok = UpgradeApp.unpack_release(node, app_name, to_version)
  end

  test "unpack_release/1 error", %{node: node, app_name: app_name, to_version: to_version} do
    release_link = "#{to_version}/#{app_name}" |> to_charlist

    Deployex.RpcMock
    |> expect(:call, fn ^node,
                        :release_handler,
                        :unpack_release,
                        [^release_link],
                        @expected_timeout ->
      :badrpc
    end)

    assert capture_log(fn ->
             assert {:error, :badrpc} = UpgradeApp.unpack_release(node, app_name, to_version)
           end) =~ "Error while unpacking the release #{to_version}, reason: :badrpc"
  end

  test "check_install_release/1 success", %{node: node, to_version: to_version} do
    Deployex.RpcMock
    |> expect(:call, fn ^node,
                        :release_handler,
                        :check_install_release,
                        [^to_version],
                        @expected_timeout ->
      {:ok, :any, :any}
    end)

    assert :ok = UpgradeApp.check_install_release(node, to_version)
  end

  test "check_install_release/1 error", %{node: node, to_version: to_version} do
    Deployex.RpcMock
    |> expect(:call, fn ^node,
                        :release_handler,
                        :check_install_release,
                        [^to_version],
                        @expected_timeout ->
      {:error, :badrpc}
    end)

    assert capture_log(fn ->
             assert {:error, :badrpc} = UpgradeApp.check_install_release(node, to_version)
           end) =~ "release_handler:check_install_release failed, reason: :badrpc"
  end

  test "install_release/1 success", %{node: node, to_version: to_version} do
    Deployex.RpcMock
    |> expect(:call, fn ^node,
                        :release_handler,
                        :install_release,
                        [^to_version, [{:update_paths, true}]],
                        @expected_timeout ->
      {:ok, :any, :any}
    end)

    assert :ok = UpgradeApp.install_release(node, to_version)
  end

  test "install_release/1 error", %{node: node, to_version: to_version} do
    Deployex.RpcMock
    |> expect(:call, fn ^node,
                        :release_handler,
                        :install_release,
                        [^to_version, [{:update_paths, true}]],
                        @expected_timeout ->
      {:error, :badrpc}
    end)

    assert capture_log(fn ->
             assert {:error, :badrpc} = UpgradeApp.install_release(node, to_version)
           end) =~ "release_handler:install_release failed, reason: :badrpc"
  end

  test "permfy/1 Elixir success", %{
    node: node,
    app_name: app_name,
    instance: instance,
    to_version: to_version
  } do
    Deployex.RpcMock
    |> expect(:call, fn ^node,
                        :release_handler,
                        :make_permanent,
                        [^to_version],
                        @expected_timeout ->
      :ok
    end)

    assert :ok = UpgradeApp.permfy(node, instance, app_name, "elixir", to_version)
  end

  test "permfy/1 Elixir error", %{
    node: node,
    app_name: app_name,
    instance: instance,
    to_version: to_version
  } do
    Deployex.RpcMock
    |> expect(:call, fn ^node,
                        :release_handler,
                        :make_permanent,
                        [^to_version],
                        @expected_timeout ->
      :badrpc
    end)

    assert capture_log(fn ->
             assert {:error, :badrpc} =
                      UpgradeApp.permfy(node, instance, app_name, "elixir", to_version)
           end) =~
             "Error while trying to set a permanent version for #{to_version}, reason: :badrpc"
  end

  test "permfy/1 Erlang success", %{
    node: node,
    app_name: app_name,
    instance: instance,
    to_version: to_version
  } do
    current_bin_path = "#{Storage.current_path(instance)}/bin"

    File.mkdir_p!(current_bin_path)

    File.write("#{current_bin_path}/#{app_name}-#{to_version}", to_version)
    File.rm("#{current_bin_path}/#{app_name}")

    Deployex.RpcMock
    |> expect(:call, fn ^node,
                        :release_handler,
                        :make_permanent,
                        [^to_version],
                        @expected_timeout ->
      :ok
    end)

    assert :ok = UpgradeApp.permfy(node, instance, app_name, "erlang", to_version)
    assert File.exists?("#{current_bin_path}/#{app_name}")
  end

  test "return_original_sys_config/1 Elixir success", %{
    instance: instance,
    to_version: to_version
  } do
    current_releases_version_path = "#{Storage.current_path(instance)}/releases/#{to_version}"

    File.mkdir_p!(current_releases_version_path)

    File.write("#{current_releases_version_path}/original.sys.config", "empty")
    File.rm("#{current_releases_version_path}/sys.config")

    assert :ok = UpgradeApp.return_original_sys_config(instance, "elixir", to_version)
    assert File.exists?("#{current_releases_version_path}/sys.config")
  end

  test "return_original_sys_config/1 Erlang success", %{
    instance: instance,
    to_version: to_version
  } do
    assert :ok = UpgradeApp.return_original_sys_config(instance, "erlang", to_version)
  end

  test "update_sys_config_from_installed_version/1 Elixir success", %{
    node: node,
    instance: instance,
    to_version: to_version
  } do
    current_releases_version_path = "#{Storage.current_path(instance)}/releases/#{to_version}"

    File.mkdir_p!(current_releases_version_path)
    File.cp!("./test/support/files/sys.config", "#{current_releases_version_path}/sys.config")

    Deployex.RpcMock
    |> stub(:call, fn ^node, _module, :load, [_cfg, _arg], @expected_timeout ->
      :ok
    end)

    assert :ok =
             UpgradeApp.update_sys_config_from_installed_version(
               node,
               instance,
               "elixir",
               to_version
             )
  end

  test "update_sys_config_from_installed_version/1 Elixir error", %{
    node: node,
    instance: instance,
    to_version: to_version
  } do
    current_releases_version_path = "#{Storage.current_path(instance)}/releases/#{to_version}"

    File.mkdir_p!(current_releases_version_path)
    File.cp!("./test/support/files/sys.config", "#{current_releases_version_path}/sys.config")

    Deployex.RpcMock
    |> stub(:call, fn ^node, _module, :load, [_cfg, _arg], @expected_timeout ->
      :ok
    end)

    with_mock File, rename: fn _source, _destination -> {:error, :any} end do
      assert capture_log(fn ->
               assert {:error, :any} =
                        UpgradeApp.update_sys_config_from_installed_version(
                          node,
                          instance,
                          "elixir",
                          to_version
                        )
             end) =~ "Error while updating sys.config to: #{to_version}, reason: :any"
    end
  end

  test "update_sys_config_from_installed_version/1 Erlang success", %{
    node: node,
    instance: instance,
    to_version: to_version
  } do
    assert :ok =
             UpgradeApp.update_sys_config_from_installed_version(
               node,
               instance,
               "erlang",
               to_version
             )
  end

  test "execute/5 Elixir success", %{
    node: node,
    app_name: app_name,
    instance: instance,
    from_version: from_version,
    to_version: to_version
  } do
    current_releases_version_path = "#{Storage.current_path(instance)}/releases/#{to_version}"

    File.mkdir_p!(current_releases_version_path)
    File.cp!("./test/support/files/sys.config", "#{current_releases_version_path}/sys.config")

    Deployex.RpcMock
    |> stub(:call, fn
      ^node, :release_handler, :unpack_release, _params, @expected_timeout ->
        {:ok, to_version}

      ^node, :code, :root_dir, [], @expected_timeout ->
        ~c"/tmp/deployex/varlib/service/#{app_name}/1/current"

      ^node, :systools, :make_relup, _params, @expected_timeout ->
        :ok

      ^node, :release_handler, :check_install_release, _params, @expected_timeout ->
        {:ok, :any, :any}

      ^node, _module, :load, [_cfg, _arg], @expected_timeout ->
        :ok

      ^node, :release_handler, :install_release, _params, @expected_timeout ->
        {:ok, :any, :any}

      ^node, :release_handler, :make_permanent, _params, @expected_timeout ->
        :ok
    end)

    with_mock Node, connect: fn ^node -> true end do
      assert :ok =
               UpgradeApp.execute(instance, app_name, "elixir", from_version, to_version)
    end
  end

  test "execute/5 Elixir error", %{app_name: app_name, instance: instance} do
    assert {:error, :invalid_version} = UpgradeApp.execute(instance, app_name, "elixir", nil, nil)
  end
end
