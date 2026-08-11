defmodule Deployer.HotUpgrade.ApplicationTest do
  use ExUnit.Case, async: false

  import Mox
  import Mock
  import ExUnit.CaptureLog

  alias Deployer.HotUpgrade.Application, as: UpgradeApp
  alias Deployer.HotUpgrade.Check
  alias Deployer.HotUpgrade.Execute
  alias Foundation.Catalog
  alias Foundation.Fixture.Catalog, as: FixtureCatalog

  setup :set_mox_global

  @valid_jellyfish_file """
    {
      "name": "testapp",
      "from": "0.1.0",
      "to": "0.2.0"
    }
  """

  @valid_jellyfish_library_file """
    {
      "name": "cowboy",
      "type": "dependency",
      "from": "0.1.0",
      "to": "0.2.0"
    }
  """

  @invalid_jellyfish_version """
    {
      "name": "testapp",
      "from": "9.9.9",
      "to": "0.2.0"
    }
  """

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

  @expected_timeout 60_000

  setup do
    FixtureCatalog.cleanup()

    app_name = "myelixir"

    sname = Catalog.create_sname(app_name)
    %{node: node} = Catalog.node_info(sname)
    Catalog.setup_new_node(sname)

    %{
      node: node,
      sname: sname,
      app_name: app_name,
      current_path: Catalog.current_path(sname),
      new_path: Catalog.new_path(sname),
      from_version: "0.1.0",
      to_version: "0.2.0",
      var_path: Application.get_env(:foundation, :var_path)
    }
  end

  # systools:make_relup/4 is stubbed in these tests, so the relup it would have produced on
  # the target has to be written by hand for the runtime config hook to patch
  defp write_relup!(path) do
    script = [{:load_object_code, {:testapp, ~c"0.2.0", [:test_app_sm]}}]
    File.write!(path, :io_lib.format(~c"~tp.~n", [{~c"0.2.0", [{~c"0.1.0", ~c"", script}], []}]))
  end

  @tag :capture_log
  test "connect/1 success connecting to the monitored app", %{node: node} do
    with_mock Node, connect: fn ^node -> true end do
      assert {:ok, ^node} = UpgradeApp.connect(node)
    end
  end

  @tag :capture_log
  test "connect/1 error while trying to connect to the monitored app", %{node: node} do
    with_mock Node, connect: fn ^node -> false end do
      assert capture_log(fn ->
               assert {:error, :not_connecting} = UpgradeApp.connect(node)
             end) =~ "Error while trying to connect with node:"
    end
  end

  @tag :capture_log
  test "check/1 Elixir full deployment", %{
    sname: sname,
    app_name: app_name,
    current_path: current_path,
    new_path: new_path,
    from_version: from_version,
    to_version: to_version
  } do
    assert capture_log(fn ->
             assert {:ok, %Check{deploy: :full_deployment}} =
                      UpgradeApp.check(%Check{
                        sname: sname,
                        name: app_name,
                        language: "elixir",
                        download_path: ".",
                        current_path: current_path,
                        new_path: new_path,
                        from_version: from_version,
                        to_version: to_version
                      })
           end) =~ "HOT UPGRADE version NOT DETECTED, full deployment required, reason"
  end

  @tag :capture_log
  test "check/1 Elixir valid appup, return hot upgrade detected", %{
    sname: sname,
    app_name: app_name,
    current_path: current_path,
    new_path: new_path,
    from_version: from_version,
    to_version: to_version,
    var_path: var_path
  } do
    new_lib_ebin_path = "#{new_path}/lib/#{app_name}-#{to_version}/ebin"
    current_releases_path = "#{current_path}/releases/#{to_version}"
    File.mkdir_p!(new_lib_ebin_path)
    File.mkdir_p!(current_releases_path)
    File.write("#{new_lib_ebin_path}/#{app_name}.appup", @valid_appup_file)
    File.write("#{new_lib_ebin_path}/jellyfish.json", @valid_jellyfish_file)
    File.write("#{var_path}/#{app_name}-#{to_version}.tar.gz", "")

    assert capture_log(fn ->
             assert {:ok, %Check{deploy: :hot_upgrade}} =
                      UpgradeApp.check(%Check{
                        sname: sname,
                        name: app_name,
                        language: "elixir",
                        download_path: "#{var_path}/#{app_name}-#{to_version}.tar.gz",
                        current_path: current_path,
                        new_path: new_path,
                        from_version: from_version,
                        to_version: to_version
                      })

             assert File.exists?("#{current_releases_path}/#{app_name}.tar.gz")
           end) =~
             "HOT UPGRADE version DETECTED - [%Deployer.HotUpgrade.Jellyfish{name: \"testapp\", type: \"project\", from: \"0.1.0\", to: \"0.2.0\"}]"
  end

  @tag :capture_log
  test "check/1 Elixir valid appup with library update, return hot upgrade detected", %{
    sname: sname,
    app_name: app_name,
    current_path: current_path,
    new_path: new_path,
    from_version: from_version,
    to_version: to_version,
    var_path: var_path
  } do
    new_lib_ebin_path = "#{new_path}/lib/#{app_name}-#{to_version}/ebin"
    current_releases_path = "#{current_path}/releases/#{to_version}"
    File.mkdir_p!(new_lib_ebin_path)
    File.mkdir_p!(current_releases_path)
    File.write("#{new_lib_ebin_path}/#{app_name}.appup", @valid_appup_file)
    File.write("#{new_lib_ebin_path}/jellyfish.json", @valid_jellyfish_library_file)
    File.write("#{var_path}/#{app_name}-#{to_version}.tar.gz", "")

    assert capture_log(fn ->
             assert {:ok, %Check{deploy: :hot_upgrade}} =
                      UpgradeApp.check(%Check{
                        sname: sname,
                        name: app_name,
                        language: "elixir",
                        download_path: "#{var_path}/#{app_name}-#{to_version}.tar.gz",
                        current_path: current_path,
                        new_path: new_path,
                        from_version: from_version,
                        to_version: to_version
                      })

             assert File.exists?("#{current_releases_path}/#{app_name}.tar.gz")
           end) =~
             "HOT UPGRADE version DETECTED - [%Deployer.HotUpgrade.Jellyfish{name: \"cowboy\", type: \"dependency\", from: \"0.1.0\", to: \"0.2.0\"}]"
  end

  @tag :capture_log
  test "check/1 Elixir invalid appup version, return hot upgrade not detected", %{
    sname: sname,
    app_name: app_name,
    current_path: current_path,
    new_path: new_path,
    from_version: from_version,
    to_version: to_version
  } do
    new_lib_ebin_path = "#{new_path}/lib/#{app_name}-#{to_version}/ebin"
    File.mkdir_p!(new_lib_ebin_path)
    File.write("#{new_lib_ebin_path}/#{app_name}.appup", @incorrect_version_appup_file)
    File.write("#{new_lib_ebin_path}/jellyfish.json", @valid_jellyfish_file)

    assert capture_log(fn ->
             assert {:ok, %Check{deploy: :full_deployment}} =
                      UpgradeApp.check(%Check{
                        sname: sname,
                        name: app_name,
                        language: "elixir",
                        download_path: ".",
                        current_path: current_path,
                        new_path: new_path,
                        from_version: from_version,
                        to_version: to_version
                      })
           end) =~
             "HOT UPGRADE version NOT DETECTED, full deployment required, reason: :no_match_versions"
  end

  @tag :capture_log
  test "check/1 Elixir invalid jellyfish version, return hot upgrade not detected", %{
    sname: sname,
    app_name: app_name,
    current_path: current_path,
    new_path: new_path,
    from_version: from_version,
    to_version: to_version
  } do
    new_lib_ebin_path = "#{new_path}/lib/#{app_name}-#{to_version}/ebin"
    File.mkdir_p!(new_lib_ebin_path)
    File.write("#{new_lib_ebin_path}/#{app_name}.appup", @incorrect_version_appup_file)
    File.write("#{new_lib_ebin_path}/jellyfish.json", @invalid_jellyfish_version)

    assert capture_log(fn ->
             assert {:ok, %Check{deploy: :full_deployment}} =
                      UpgradeApp.check(%Check{
                        sname: sname,
                        name: app_name,
                        language: "elixir",
                        download_path: ".",
                        current_path: current_path,
                        new_path: new_path,
                        from_version: from_version,
                        to_version: to_version
                      })
           end) =~
             "HOT UPGRADE version NOT DETECTED, full deployment required, reason: :no_match_versions"
  end

  @tag :capture_log
  test "check/1 Elixir invalid appup file, return hot upgrade not detected", %{
    sname: sname,
    app_name: app_name,
    current_path: current_path,
    new_path: new_path,
    from_version: from_version,
    to_version: to_version
  } do
    new_lib_ebin_path = "#{new_path}/lib/testapp-0.2.0/ebin"
    File.mkdir_p!(new_lib_ebin_path)
    File.write("#{new_lib_ebin_path}/testapp.appup", @invalid_appup_file)
    File.write("#{new_lib_ebin_path}/jellyfish.json", @valid_jellyfish_file)

    assert capture_log(fn ->
             assert {:ok, %Check{deploy: :full_deployment}} =
                      UpgradeApp.check(%Check{
                        sname: sname,
                        name: app_name,
                        language: "elixir",
                        download_path: ".",
                        current_path: current_path,
                        new_path: new_path,
                        from_version: from_version,
                        to_version: to_version
                      })
           end) =~
             "HOT UPGRADE version NOT DETECTED, full deployment required, reason: :error_reading_file"
  end

  @tag :capture_log
  test "check/1 Elixir appup file not found, return hot upgrade not detected", %{
    sname: sname,
    app_name: app_name,
    current_path: current_path,
    new_path: new_path,
    from_version: from_version,
    to_version: to_version
  } do
    new_lib_ebin_path = "#{new_path}/lib/testapp-0.2.0/ebin"
    File.mkdir_p!(new_lib_ebin_path)
    File.write("#{new_lib_ebin_path}/jellyfish.json", @valid_jellyfish_file)

    assert capture_log(fn ->
             assert :ok = UpgradeApp.prepare_new_path(app_name, "elixir", to_version, new_path)

             assert {:ok, %Check{deploy: :full_deployment}} =
                      UpgradeApp.check(%Check{
                        sname: sname,
                        name: app_name,
                        language: "elixir",
                        download_path: ".",
                        current_path: current_path,
                        new_path: new_path,
                        from_version: from_version,
                        to_version: to_version
                      })
           end) =~
             "HOT UPGRADE version NOT DETECTED, full deployment required, reason: :not_found"
  end

  @tag :capture_log
  test "check/1 Erlang full deployment", %{
    sname: sname,
    app_name: app_name,
    current_path: current_path,
    new_path: new_path,
    from_version: from_version,
    to_version: to_version
  } do
    assert capture_log(fn ->
             assert {:ok, %Check{deploy: :full_deployment}} =
                      UpgradeApp.check(%Check{
                        sname: sname,
                        name: app_name,
                        language: "erlang",
                        download_path: ".",
                        current_path: current_path,
                        new_path: new_path,
                        from_version: from_version,
                        to_version: to_version
                      })
           end) =~ "HOT UPGRADE version NOT DETECTED, full deployment required, result"
  end

  @tag :capture_log
  test "check/1 Erlang valid appup, return hot upgrade detected", %{
    sname: sname,
    app_name: app_name,
    current_path: current_path,
    new_path: new_path,
    from_version: from_version,
    to_version: to_version,
    var_path: var_path
  } do
    new_lib_ebin_path = "#{new_path}/lib/#{app_name}-#{to_version}/ebin"
    new_lib_priv_path = "#{new_path}/lib/#{app_name}-#{to_version}/priv/appup"
    new_releases_path = "#{new_path}/releases"
    current_releases_path = "#{current_path}/releases/#{to_version}"

    File.mkdir_p!(new_lib_ebin_path)
    File.mkdir_p!(new_lib_priv_path)
    File.mkdir_p!(new_releases_path)
    File.mkdir_p!(current_releases_path)

    File.write("#{new_lib_priv_path}/#{app_name}.appup", @valid_appup_file)
    File.write("#{new_releases_path}/#{app_name}.rel", @release_file)
    File.write("#{var_path}/#{app_name}-#{to_version}.tar.gz", "")

    assert capture_log(fn ->
             assert :ok = UpgradeApp.prepare_new_path(app_name, "erlang", to_version, new_path)

             assert {:ok, %Check{deploy: :hot_upgrade}} =
                      UpgradeApp.check(%Check{
                        sname: sname,
                        name: app_name,
                        language: "erlang",
                        download_path: "#{var_path}/#{app_name}-#{to_version}.tar.gz",
                        current_path: current_path,
                        new_path: new_path,
                        from_version: from_version,
                        to_version: to_version
                      })

             assert File.exists?("#{new_releases_path}/#{app_name}-#{to_version}.rel")
             refute File.exists?("#{new_releases_path}/#{app_name}.rel")
             assert File.exists?("#{current_releases_path}/#{app_name}.tar.gz")
           end) =~ "HOT UPGRADE version DETECTED, from: #{from_version} to: #{to_version}"
  end

  @tag :capture_log
  test "check/1 Gleam full deployment", %{
    sname: sname,
    app_name: app_name,
    current_path: current_path,
    new_path: new_path,
    from_version: from_version,
    to_version: to_version
  } do
    assert capture_log(fn ->
             assert {:ok, %Check{deploy: :full_deployment}} =
                      UpgradeApp.check(%Check{
                        sname: sname,
                        name: app_name,
                        language: "gleam",
                        download_path: ".",
                        current_path: current_path,
                        new_path: new_path,
                        from_version: from_version,
                        to_version: to_version
                      })
           end) =~ "HOT UPGRADE version NOT SUPPORTED, full deployment required"
  end

  @tag :capture_log
  test "which_releases/1", %{node: node} do
    Foundation.RpcMock
    |> expect(:call, fn ^node, :release_handler, :which_releases, [], @expected_timeout ->
      @releases_file
    end)

    assert [permanent: ~c"0.2.0", old: ~c"0.1.0"] = UpgradeApp.which_releases(node)
  end

  @tag :capture_log
  test "make_relup/1 Elixir success", %{
    node: node,
    sname: sname,
    app_name: app_name,
    current_path: current_path,
    new_path: new_path,
    from_version: from_version,
    to_version: to_version
  } do
    root = ~c"/tmp/deployex/varlib/service/#{app_name}/1/current"

    Foundation.RpcMock
    |> expect(:call, fn ^node, :code, :root_dir, [], @expected_timeout ->
      root
    end)
    |> expect(:call, fn ^node, :systools, :make_relup, _params, @expected_timeout ->
      {:ok, :relup, :systools_relup, []}
    end)

    assert :ok =
             UpgradeApp.make_relup(%Execute{
               node: node,
               sname: sname,
               name: app_name,
               language: "elixir",
               current_path: current_path,
               new_path: new_path,
               from_version: from_version,
               to_version: to_version
             })
  end

  @tag :capture_log
  test "make_relup/1 Elixir error", %{
    node: node,
    sname: sname,
    app_name: app_name,
    current_path: current_path,
    new_path: new_path,
    from_version: from_version,
    to_version: to_version
  } do
    root = ~c"/tmp/deployex/varlib/service/#{app_name}/1/current"

    Foundation.RpcMock
    |> expect(:call, fn ^node, :code, :root_dir, [], @expected_timeout ->
      root
    end)
    |> expect(:call, fn ^node, :systools, :make_relup, _params, @expected_timeout ->
      :badrpc
    end)

    assert capture_log(fn ->
             assert {:error, :make_relup} =
                      UpgradeApp.make_relup(%Execute{
                        node: node,
                        sname: sname,
                        name: app_name,
                        language: "elixir",
                        current_path: current_path,
                        new_path: new_path,
                        from_version: from_version,
                        to_version: to_version
                      })
           end) =~ "systools:make_relup failed, reason: :badrpc"
  end

  @tag :capture_log
  test "make_relup/1 Erlang success", %{
    node: node,
    sname: sname,
    app_name: app_name,
    current_path: current_path,
    new_path: new_path,
    from_version: from_version,
    to_version: to_version
  } do
    root = ~c"/tmp/deployex/varlib/service/#{app_name}/1/current"

    new_lib_priv_path = "#{new_path}/lib/#{app_name}-#{to_version}/priv/appup"
    current_lib_ebin_path = "#{current_path}/lib/#{app_name}-#{to_version}/ebin"
    current_releases_path = "#{current_path}/releases"

    File.mkdir_p!(new_lib_priv_path)
    File.mkdir_p!(current_lib_ebin_path)
    File.mkdir_p!(current_releases_path)

    File.write("#{new_lib_priv_path}/#{app_name}.appup", @valid_appup_file)
    File.write("#{current_releases_path}/#{app_name}.rel", @release_file)

    Foundation.RpcMock
    |> expect(:call, fn ^node, :code, :root_dir, [], @expected_timeout ->
      root
    end)
    |> expect(:call, fn ^node, :systools, :make_relup, _params, @expected_timeout ->
      {:ok, :relup, :systools_relup, []}
    end)

    assert :ok =
             UpgradeApp.make_relup(%Execute{
               node: node,
               sname: sname,
               name: app_name,
               language: "erlang",
               current_path: current_path,
               new_path: new_path,
               from_version: from_version,
               to_version: to_version
             })

    assert File.exists?("#{current_lib_ebin_path}/#{app_name}.appup")
    assert File.exists?("#{current_releases_path}/#{app_name}-#{to_version}.rel")
    refute File.exists?("#{current_releases_path}/#{app_name}.rel")
  end

  @tag :capture_log
  test "unpack_release/1 success", %{node: node, app_name: app_name, to_version: to_version} do
    release_link = "#{to_version}/#{app_name}" |> to_charlist

    Foundation.RpcMock
    |> expect(:call, fn ^node,
                        :release_handler,
                        :unpack_release,
                        [^release_link],
                        @expected_timeout ->
      {:ok, to_version}
    end)

    assert :ok =
             UpgradeApp.unpack_release(%Execute{
               node: node,
               name: app_name,
               to_version: to_version
             })
  end

  @tag :capture_log
  test "unpack_release/1 error", %{
    node: node,
    app_name: app_name,
    to_version: to_version
  } do
    release_link = "#{to_version}/#{app_name}" |> to_charlist

    Foundation.RpcMock
    |> expect(:call, fn ^node,
                        :release_handler,
                        :unpack_release,
                        [^release_link],
                        @expected_timeout ->
      :badrpc
    end)

    assert capture_log(fn ->
             assert {:error, :badrpc} =
                      UpgradeApp.unpack_release(%Execute{
                        node: node,
                        name: app_name,
                        to_version: to_version
                      })
           end) =~ "Error while unpacking the release #{to_version}, reason: :badrpc"
  end

  @tag :capture_log
  test "make_relup/1 logs the reason systools reports", %{
    node: node,
    sname: sname,
    app_name: app_name,
    current_path: current_path,
    new_path: new_path,
    from_version: from_version,
    to_version: to_version
  } do
    root = ~c"/tmp/deployex/varlib/service/#{app_name}/1/current"

    # the shape systools returns for the missing appup that broke a real upgrade
    error = {:file_problem, {~c"#{root}/lib/elixir-1.20.3/ebin/elixir.appup", {:open, :enoent}}}

    Foundation.RpcMock
    |> expect(:call, fn ^node, :code, :root_dir, [], @expected_timeout -> root end)
    |> expect(:call, fn ^node, :systools, :make_relup, params, @expected_timeout ->
      # silent is what makes systools return the reason instead of printing it to stdout
      assert :silent in List.last(params)
      {:error, :systools_relup, error}
    end)
    |> expect(:call, fn ^node, :systools_relup, :format_error, [^error], @expected_timeout ->
      ~c"Could not open file #{root}/lib/elixir-1.20.3/ebin/elixir.appup"
    end)

    log =
      capture_log(fn ->
        assert {:error, :make_relup} =
                 UpgradeApp.make_relup(%Execute{
                   node: node,
                   sname: sname,
                   name: app_name,
                   language: "elixir",
                   current_path: current_path,
                   new_path: new_path,
                   from_version: from_version,
                   to_version: to_version
                 })
      end)

    # the cause is in the log line, not on stdout detached from it
    assert log =~ "elixir-1.20.3/ebin/elixir.appup"
    assert log =~ "#{app_name} #{from_version} -> #{to_version}"
  end

  @tag :capture_log
  test "make_relup/1 falls back to the raw term when format_error is unusable", %{
    node: node,
    sname: sname,
    app_name: app_name,
    current_path: current_path,
    new_path: new_path,
    from_version: from_version,
    to_version: to_version
  } do
    root = ~c"/tmp/deployex/varlib/service/#{app_name}/1/current"

    Foundation.RpcMock
    |> expect(:call, fn ^node, :code, :root_dir, [], @expected_timeout -> root end)
    |> expect(:call, fn ^node, :systools, :make_relup, _params, @expected_timeout ->
      {:error, :systools_relup, :some_reason}
    end)
    |> expect(:call, fn ^node, :systools_relup, :format_error, _args, @expected_timeout ->
      {:badrpc, :nodedown}
    end)

    assert capture_log(fn ->
             assert {:error, :make_relup} =
                      UpgradeApp.make_relup(%Execute{
                        node: node,
                        sname: sname,
                        name: app_name,
                        language: "elixir",
                        current_path: current_path,
                        new_path: new_path,
                        from_version: from_version,
                        to_version: to_version
                      })
           end) =~ ":some_reason"
  end

  @tag :capture_log
  test "check_install_release/1 success", %{node: node, to_version: to_version} do
    Foundation.RpcMock
    |> expect(:call, fn ^node,
                        :release_handler,
                        :check_install_release,
                        [^to_version],
                        @expected_timeout ->
      {:ok, :any, :any}
    end)

    assert :ok =
             UpgradeApp.check_install_release(%Execute{
               node: node,
               to_version: to_version
             })
  end

  @tag :capture_log
  test "check_install_release/1 error", %{node: node, to_version: to_version} do
    Foundation.RpcMock
    |> expect(:call, fn ^node,
                        :release_handler,
                        :check_install_release,
                        [^to_version],
                        @expected_timeout ->
      {:error, :badrpc}
    end)

    assert capture_log(fn ->
             assert {:error, :badrpc} =
                      UpgradeApp.check_install_release(%Execute{
                        node: node,
                        to_version: to_version
                      })
           end) =~ "release_handler:check_install_release failed, reason: :badrpc"
  end

  @tag :capture_log
  test "install_release/1 success", %{node: node, to_version: to_version} do
    Foundation.RpcMock
    |> expect(:call, fn ^node,
                        :release_handler,
                        :install_release,
                        [^to_version, [{:update_paths, true}]],
                        @expected_timeout ->
      {:ok, :any, :any}
    end)

    assert :ok =
             UpgradeApp.install_release(%Execute{
               node: node,
               to_version: to_version
             })
  end

  @tag :capture_log
  test "install_release/1 error", %{node: node, to_version: to_version} do
    Foundation.RpcMock
    |> expect(:call, fn ^node,
                        :release_handler,
                        :install_release,
                        [^to_version, [{:update_paths, true}]],
                        @expected_timeout ->
      {:error, :badrpc}
    end)

    assert capture_log(fn ->
             assert {:error, :badrpc} =
                      UpgradeApp.install_release(%Execute{
                        node: node,
                        to_version: to_version
                      })
           end) =~ "release_handler:install_release failed, reason: :badrpc"
  end

  @tag :capture_log
  test "permfy/1 Elixir success", %{
    node: node,
    app_name: app_name,
    new_path: new_path,
    to_version: to_version
  } do
    Foundation.RpcMock
    |> expect(:call, fn ^node,
                        :release_handler,
                        :make_permanent,
                        [^to_version],
                        @expected_timeout ->
      :ok
    end)

    assert :ok =
             UpgradeApp.permfy(%Execute{
               node: node,
               name: app_name,
               language: "elixir",
               new_path: new_path,
               to_version: to_version
             })
  end

  @tag :capture_log
  test "permfy/1 Elixir error", %{
    node: node,
    app_name: app_name,
    current_path: current_path,
    to_version: to_version
  } do
    Foundation.RpcMock
    |> expect(:call, fn ^node,
                        :release_handler,
                        :make_permanent,
                        [^to_version],
                        @expected_timeout ->
      :badrpc
    end)

    assert capture_log(fn ->
             assert {:error, :badrpc} =
                      UpgradeApp.permfy(%Execute{
                        node: node,
                        name: app_name,
                        language: "elixir",
                        current_path: current_path,
                        to_version: to_version
                      })
           end) =~
             "Error while trying to set a permanent version for #{to_version}, reason: :badrpc"
  end

  @tag :capture_log
  test "permfy/1 Erlang success", %{
    node: node,
    app_name: app_name,
    current_path: current_path,
    to_version: to_version
  } do
    current_bin_path = "#{current_path}/bin"

    File.mkdir_p!(current_bin_path)

    File.write("#{current_bin_path}/#{app_name}-#{to_version}", to_version)
    File.rm("#{current_bin_path}/#{app_name}")

    Foundation.RpcMock
    |> expect(:call, fn ^node,
                        :release_handler,
                        :make_permanent,
                        [^to_version],
                        @expected_timeout ->
      :ok
    end)

    assert :ok =
             UpgradeApp.permfy(%Execute{
               node: node,
               name: app_name,
               language: "erlang",
               current_path: current_path,
               to_version: to_version
             })

    assert File.exists?("#{current_bin_path}/#{app_name}")
  end

  @tag :capture_log
  test "permfy/1 Deployex skip execution" do
    assert :ok = UpgradeApp.permfy(%Execute{make_permanent_async: true})
  end

  test "resolve_runtime_config/1 Elixir success", %{
    node: node,
    current_path: current_path,
    to_version: to_version
  } do
    current_releases_version_path = "#{current_path}/releases/#{to_version}"
    sys_config_path = "#{current_releases_version_path}/sys.config"

    File.mkdir_p!(current_releases_version_path)
    File.cp!("./test/support/files/sys.config", sys_config_path)
    write_relup!("#{current_releases_version_path}/relup")
    original_sys_config = File.read!(sys_config_path)

    Foundation.RpcMock
    |> stub(:call, fn ^node, _module, :load, [cfg, _arg], @expected_timeout ->
      Keyword.put(cfg, :from_runtime_exs, answer: 42)
    end)

    assert {:ok, config} =
             UpgradeApp.resolve_runtime_config(%Execute{
               node: node,
               language: "elixir",
               current_path: current_path,
               to_version: to_version
             })

    assert config[:from_runtime_exs] == [answer: 42]
    assert config[:logger][:level] == :info

    # sys.config is only read now, the release directory must come out untouched
    assert File.read!(sys_config_path) == original_sys_config
    refute File.exists?("#{current_releases_version_path}/original.sys.config")
  end

  test "resolve_runtime_config/1 Elixir carries values sys.config could never hold", %{
    node: node,
    current_path: current_path,
    to_version: to_version
  } do
    current_releases_version_path = "#{current_path}/releases/#{to_version}"

    File.mkdir_p!(current_releases_version_path)
    File.cp!("./test/support/files/sys.config", "#{current_releases_version_path}/sys.config")
    write_relup!("#{current_releases_version_path}/relup")

    # The exact value an Ecto Repo gets for a verify_peer TLS connection. Written to
    # sys.config it prints as #Fun<...> and the file stops parsing
    match_fun = :public_key.pkix_verify_hostname_match_fun(:https)

    repo_config = [
      url: "postgres://user:pass@host:5432/db",
      ssl_opts: [verify: :verify_peer, customize_hostname_check: [match_fun: match_fun]]
    ]

    Foundation.RpcMock
    |> stub(:call, fn ^node, _module, :load, [cfg, _arg], @expected_timeout ->
      Keyword.update!(cfg, :testapp, &Keyword.put(&1, Testapp.Repo, repo_config))
    end)

    assert {:ok, config} =
             UpgradeApp.resolve_runtime_config(%Execute{
               node: node,
               language: "elixir",
               current_path: current_path,
               to_version: to_version
             })

    fun = config[:testapp][Testapp.Repo][:ssl_opts][:customize_hostname_check][:match_fun]
    assert fun.({:dns_id, ~c"a.example.com"}, {:dNSName, ~c"*.example.com"})
  end

  @tag :capture_log
  test "resolve_runtime_config/1 Elixir fails when sys.config cannot be read", %{
    node: node,
    current_path: current_path,
    to_version: to_version
  } do
    File.mkdir_p!("#{current_path}/releases/#{to_version}")

    assert capture_log(fn ->
             assert {:error, {:unreadable_sys_config, _reason}} =
                      UpgradeApp.resolve_runtime_config(%Execute{
                        node: node,
                        language: "elixir",
                        current_path: current_path,
                        to_version: to_version
                      })
           end) =~ "Error while reading"
  end

  @tag :capture_log
  test "resolve_runtime_config/1 Elixir fails when a config provider crashes",
       %{
         node: node,
         current_path: current_path,
         to_version: to_version
       } do
    current_releases_version_path = "#{current_path}/releases/#{to_version}"
    sys_config_path = "#{current_releases_version_path}/sys.config"

    File.mkdir_p!(current_releases_version_path)
    File.cp!("./test/support/files/sys.config", sys_config_path)
    write_relup!("#{current_releases_version_path}/relup")
    original_sys_config = File.read!(sys_config_path)

    # Providers run over RPC inside the still running old version. One that starts a process
    # the application already owns works on a cold boot and fails here
    badrpc =
      {:badrpc,
       {:EXIT,
        {{:badmatch, {:error, {:already_started, self()}}},
         [{Testapp.SecretsProvider, :load, 2, [file: ~c"lib/secrets.ex", line: 54]}]}}}

    Foundation.RpcMock
    |> stub(:call, fn ^node, _module, :load, [_cfg, _arg], @expected_timeout -> badrpc end)

    log =
      capture_log(fn ->
        assert {:error, {:config_provider_failed, _mod, ^badrpc}} =
                 UpgradeApp.resolve_runtime_config(%Execute{
                   node: node,
                   language: "elixir",
                   current_path: current_path,
                   to_version: to_version
                 })
      end)

    assert log =~ "did not return a configuration"
    assert log =~ "already_started"

    # The failure must not be carried forward and written into sys.config
    assert File.read!(sys_config_path) == original_sys_config
    refute File.exists?("#{current_releases_version_path}/original.sys.config")
  end

  test "resolve_runtime_config/1 Erlang success", %{
    node: node,
    new_path: new_path,
    to_version: to_version
  } do
    assert {:ok, []} =
             UpgradeApp.resolve_runtime_config(%Execute{
               node: node,
               language: "erlang",
               new_path: new_path,
               to_version: to_version
             })
  end

  test "install_runtime_config_hook/2 makes no rpc call when there is nothing to apply", %{
    node: node
  } do
    Foundation.RpcMock
    |> stub(:call, fn _node, _module, _function, _args, _timeout ->
      flunk("no rpc call expected")
    end)

    assert :ok = UpgradeApp.install_runtime_config_hook(%Execute{node: node}, [])
  end

  @tag :capture_log
  test "install_runtime_config_hook/2 stashes the config and heads the relup script", %{
    node: node,
    current_path: current_path,
    to_version: to_version
  } do
    current_releases_version_path = "#{current_path}/releases/#{to_version}"
    relup_path = "#{current_releases_version_path}/relup"

    File.mkdir_p!(current_releases_version_path)

    original_script = [
      {:load_object_code, {:testapp, ~c"0.2.0", [:test_app_sm]}},
      {:suspend, [:test_app_sm]},
      {:code_change, :up, [{:test_app_sm, []}]},
      {:resume, [:test_app_sm]}
    ]

    File.write!(
      relup_path,
      :io_lib.format(~c"~tp.~n", [{~c"0.2.0", [{~c"0.1.0", ~c"", original_script}], []}])
    )

    match_fun = :public_key.pkix_verify_hostname_match_fun(:https)
    runtime_config = [testapp: [{Testapp.Repo, [ssl_opts: [match_fun: match_fun]]}]]
    test_pid = self()

    Foundation.RpcMock
    |> stub(:call, fn ^node, :persistent_term, :put, args, @expected_timeout ->
      send(test_pid, {:stashed, args})
      :ok
    end)

    assert :ok =
             UpgradeApp.install_runtime_config_hook(
               %Execute{node: node, current_path: current_path, to_version: to_version},
               runtime_config
             )

    # The configuration itself cannot travel in the relup, it goes over RPC
    assert_receive {:stashed, [{:deployex, :runtime_config}, ^runtime_config]}

    # release_handler reads the relup with :file.consult/1 too, so the patched file must parse
    assert {:ok, [{~c"0.2.0", [{~c"0.1.0", ~c"", script}], []}]} = :file.consult(relup_path)

    # Heading the script puts it after change_appl_data/3 and before suspend/code_change
    assert [{:apply, {:erl_eval, :exprs, [forms, []]}} | ^original_script] = script

    # The forms must evaluate to the set_env call, with no module loaded into the target
    :persistent_term.put({:deployex, :runtime_config}, runtime_config)
    on_exit(fn -> :persistent_term.erase({:deployex, :runtime_config}) end)
    on_exit(fn -> Application.delete_env(:testapp, Testapp.Repo) end)

    assert {:value, _last, _bindings} = :erl_eval.exprs(forms, [])
    assert Application.get_env(:testapp, Testapp.Repo)[:ssl_opts][:match_fun] == match_fun

    # The stash holds whatever the Config Providers produced, secrets included, so the hook
    # must erase it rather than leave it on the node
    assert :persistent_term.get({:deployex, :runtime_config}, :erased) == :erased
  end

  @tag :capture_log
  test "install_runtime_config_hook/2 restores every application of an umbrella in one call", %{
    node: node,
    current_path: current_path,
    to_version: to_version
  } do
    current_releases_version_path = "#{current_path}/releases/#{to_version}"
    relup_path = "#{current_releases_version_path}/relup"

    File.mkdir_p!(current_releases_version_path)
    write_relup!(relup_path)

    # An umbrella release is still one OTP release with one sys.config and one relup, it just
    # holds several applications. change_appl_data/3 resets all of them, so the hook has to
    # bring all of them back
    runtime_config = [
      core: [{Core.Repo, [url: "postgres://host/db"]}],
      worker: [poll_ms: 5_000],
      web: [{Web.Endpoint, [secret_key_base: "s3cret"]}]
    ]

    Foundation.RpcMock
    |> stub(:call, fn ^node, :persistent_term, :put, _args, @expected_timeout -> :ok end)

    assert :ok =
             UpgradeApp.install_runtime_config_hook(
               %Execute{node: node, current_path: current_path, to_version: to_version},
               runtime_config
             )

    assert {:ok, [{_to, [{_from, _descr, script}], _}]} = :file.consult(relup_path)
    assert [{:apply, {:erl_eval, :exprs, [forms, []]}} | _] = script

    :persistent_term.put({:deployex, :runtime_config}, runtime_config)
    on_exit(fn -> :persistent_term.erase({:deployex, :runtime_config}) end)

    on_exit(fn ->
      Application.delete_env(:core, Core.Repo)
      Application.delete_env(:worker, :poll_ms)
      Application.delete_env(:web, Web.Endpoint)
    end)

    assert {:value, _last, _bindings} = :erl_eval.exprs(forms, [])

    assert Application.get_env(:core, Core.Repo) == [url: "postgres://host/db"]
    assert Application.get_env(:worker, :poll_ms) == 5_000
    assert Application.get_env(:web, Web.Endpoint) == [secret_key_base: "s3cret"]
  end

  @tag :capture_log
  test "install_runtime_config_hook/2 leaves an emulator restart script untouched", %{
    node: node,
    current_path: current_path,
    to_version: to_version
  } do
    current_releases_version_path = "#{current_path}/releases/#{to_version}"
    relup_path = "#{current_releases_version_path}/relup"

    File.mkdir_p!(current_releases_version_path)

    script = [:restart_new_emulator, {:load_object_code, {:testapp, ~c"0.2.0", [:test_app_sm]}}]

    File.write!(
      relup_path,
      :io_lib.format(~c"~tp.~n", [{~c"0.2.0", [{~c"0.1.0", ~c"", script}], []}])
    )

    Foundation.RpcMock
    |> stub(:call, fn ^node, :persistent_term, :put, _args, @expected_timeout -> :ok end)

    assert :ok =
             UpgradeApp.install_runtime_config_hook(
               %Execute{node: node, current_path: current_path, to_version: to_version},
               testapp: [{Testapp.Repo, []}]
             )

    # The VM restarts and Config.Provider resolves the configuration again on boot
    assert {:ok, [{_to, [{_from, _descr, ^script}], _}]} = :file.consult(relup_path)
  end

  @tag :capture_log
  test "install_runtime_config_hook/2 fails the upgrade when the relup cannot be read", %{
    node: node,
    current_path: current_path,
    to_version: to_version
  } do
    test_pid = self()

    Foundation.RpcMock
    |> stub(:call, fn
      ^node, :persistent_term, :put, _args, @expected_timeout ->
        :ok

      ^node, :persistent_term, :erase, args, @expected_timeout ->
        send(test_pid, {:erased, args})
        true
    end)

    # Installing without the hook would reset every application, so this must not be silent
    assert capture_log(fn ->
             assert {:error, {:unreadable_relup, _reason}} =
                      UpgradeApp.install_runtime_config_hook(
                        %Execute{node: node, current_path: current_path, to_version: to_version},
                        testapp: [{Testapp.Repo, []}]
                      )
           end) =~ "Error while adding the runtime config hook"

    # Nothing will consume the stash now, so it must not be left on the node
    assert_receive {:erased, [{:deployex, :runtime_config}]}
  end

  @tag :capture_log
  test "execute/5 Elixir Application success", %{
    node: node,
    sname: sname,
    app_name: app_name,
    current_path: current_path,
    new_path: new_path,
    from_version: from_version,
    to_version: to_version
  } do
    current_releases_version_path = "#{current_path}/releases/#{to_version}"

    File.mkdir_p!(current_releases_version_path)
    File.cp!("./test/support/files/sys.config", "#{current_releases_version_path}/sys.config")
    write_relup!("#{current_releases_version_path}/relup")

    Foundation.RpcMock
    |> stub(:call, fn
      ^node, :release_handler, :unpack_release, _params, @expected_timeout ->
        {:ok, to_version}

      ^node, :release_handler, :which_releases, [], @expected_timeout ->
        []

      ^node, :code, :root_dir, [], @expected_timeout ->
        ~c"/tmp/deployex/varlib/service/#{app_name}/1/current"

      ^node, :systools, :make_relup, _params, @expected_timeout ->
        {:ok, :relup, :systools_relup, []}

      ^node, :release_handler, :check_install_release, _params, @expected_timeout ->
        {:ok, :any, :any}

      ^node, _module, :load, [cfg, _arg], @expected_timeout ->
        cfg

      ^node, :persistent_term, :put, _params, @expected_timeout ->
        :ok

      ^node, :release_handler, :install_release, _params, @expected_timeout ->
        {:ok, :any, :any}

      ^node, :release_handler, :make_permanent, _params, @expected_timeout ->
        :ok
    end)

    with_mock Node, [:passthrough], connect: fn ^node -> true end do
      assert :ok =
               UpgradeApp.execute(%Execute{
                 node: node,
                 sname: sname,
                 name: app_name,
                 language: "elixir",
                 current_path: current_path,
                 new_path: new_path,
                 from_version: from_version,
                 to_version: to_version
               })
    end
  end

  @tag :capture_log
  test "execute/5 Elixir aborts before installing when a config provider fails", %{
    node: node,
    sname: sname,
    app_name: app_name,
    current_path: current_path,
    new_path: new_path,
    from_version: from_version,
    to_version: to_version
  } do
    current_releases_version_path = "#{current_path}/releases/#{to_version}"
    sys_config_path = "#{current_releases_version_path}/sys.config"

    File.mkdir_p!(current_releases_version_path)
    File.cp!("./test/support/files/sys.config", sys_config_path)
    write_relup!("#{current_releases_version_path}/relup")
    original_sys_config = File.read!(sys_config_path)

    Foundation.RpcMock
    |> stub(:call, fn
      ^node, :release_handler, :unpack_release, _params, @expected_timeout ->
        {:ok, to_version}

      ^node, :release_handler, :which_releases, [], @expected_timeout ->
        []

      ^node, :code, :root_dir, [], @expected_timeout ->
        ~c"/tmp/deployex/varlib/service/#{app_name}/1/current"

      ^node, :systools, :make_relup, _params, @expected_timeout ->
        {:ok, :relup, :systools_relup, []}

      ^node, :release_handler, :check_install_release, _params, @expected_timeout ->
        {:ok, :any, :any}

      ^node, _module, :load, [_cfg, _arg], @expected_timeout ->
        {:badrpc, {:EXIT, {{:badmatch, {:error, {:already_started, self()}}}, []}}}

      ^node, :release_handler, :install_release, _params, @expected_timeout ->
        flunk("install_release must not run once the configuration cannot be resolved")

      ^node, :release_handler, :make_permanent, _params, @expected_timeout ->
        flunk("make_permanent must not run once the configuration cannot be resolved")
    end)

    with_mock Node, [:passthrough], connect: fn ^node -> true end do
      assert {:error, {:config_provider_failed, _mod, _reason}} =
               UpgradeApp.execute(%Execute{
                 node: node,
                 sname: sname,
                 name: app_name,
                 language: "elixir",
                 current_path: current_path,
                 new_path: new_path,
                 from_version: from_version,
                 to_version: to_version
               })
    end

    # Nothing was installed and nothing was rewritten, so the running node keeps the
    # configuration it already had and the engine falls back to a full deployment
    assert File.read!(sys_config_path) == original_sys_config
    refute File.exists?("#{current_releases_version_path}/original.sys.config")
  end

  test "execute/5 Elixir Application error", %{
    app_name: app_name,
    sname: sname,
    current_path: current_path,
    new_path: new_path
  } do
    assert {:error, :invalid_version} =
             UpgradeApp.execute(%Execute{
               sname: sname,
               name: app_name,
               language: "elixir",
               current_path: current_path,
               new_path: new_path
             })
  end

  @tag :capture_log
  test "execute/5 Elixir Deployex success sync operation, make_permanent_async=true", %{
    current_path: current_path,
    new_path: new_path,
    from_version: from_version,
    to_version: to_version
  } do
    node = Node.self()
    sname = "deployex"
    current_releases_version_path = "#{current_path}/releases/#{to_version}"

    File.mkdir_p!(current_releases_version_path)
    File.cp!("./test/support/files/sys.config", "#{current_releases_version_path}/sys.config")
    write_relup!("#{current_releases_version_path}/relup")

    Foundation.RpcMock
    |> stub(:call, fn
      ^node, :release_handler, :unpack_release, _params, @expected_timeout ->
        {:ok, to_version}

      ^node, :release_handler, :which_releases, [], @expected_timeout ->
        []

      ^node, :code, :root_dir, [], @expected_timeout ->
        ~c"/tmp/deployex/varlib/service/deployex"

      ^node, :systools, :make_relup, _params, @expected_timeout ->
        {:ok, :relup, :systools_relup, []}

      ^node, :release_handler, :check_install_release, _params, @expected_timeout ->
        {:ok, :any, :any}

      ^node, _module, :load, [cfg, _arg], @expected_timeout ->
        cfg

      ^node, :persistent_term, :put, _params, @expected_timeout ->
        :ok

      ^node, :release_handler, :install_release, _params, @expected_timeout ->
        {:ok, :any, :any}

      ^node, :release_handler, :make_permanent, _params, @expected_timeout ->
        :ok
    end)

    with_mock Node, [:passthrough], connect: fn ^node -> true end do
      UpgradeApp.subscribe_events()
      ref = make_ref()
      test_pid = self()

      after_async_make_permanent = fn ->
        send(test_pid, {:handle_ref_event, ref})
      end

      assert :ok =
               UpgradeApp.execute(%Execute{
                 node: node,
                 sname: sname,
                 name: sname,
                 language: "elixir",
                 current_path: current_path,
                 new_path: new_path,
                 from_version: from_version,
                 to_version: to_version,
                 make_permanent_async: true,
                 sync_execution: true,
                 after_async_make_permanent: after_async_make_permanent
               })

      assert_receive {:hot_upgrade_progress, ^node, ^sname, "Starting upgrade for deployex..."},
                     1_000

      assert_receive {:hot_upgrade_progress, ^node, ^sname, "Unpacking release"},
                     1_000

      assert_receive {:hot_upgrade_progress, ^node, ^sname, "Creating relup file"},
                     1_000

      assert_receive {:hot_upgrade_progress, ^node, ^sname, "Checking release can be installed"},
                     1_000

      assert_receive {:hot_upgrade_progress, ^node, ^sname,
                      "Resolving the runtime configuration"},
                     1_000

      assert_receive {:hot_upgrade_progress, ^node, ^sname, "Installing release"},
                     1_000

      assert_receive {:hot_upgrade_progress, ^node, ^sname,
                      "Adding the runtime configuration to the relup"},
                     1_000

      assert_receive {:hot_upgrade_complete, ^node, ^sname, :ok,
                      "Hot upgrade applied successfully!"},
                     1_000

      assert_receive {:handle_ref_event, ^ref}, 1_000
    end
  end

  @tag :capture_log
  test "execute/5 Elixir Deployex success sync operation, make_permanent_async=false", %{
    current_path: current_path,
    new_path: new_path,
    from_version: from_version,
    to_version: to_version
  } do
    node = Node.self()
    sname = "deployex"
    current_releases_version_path = "#{current_path}/releases/#{to_version}"

    File.mkdir_p!(current_releases_version_path)
    File.cp!("./test/support/files/sys.config", "#{current_releases_version_path}/sys.config")
    write_relup!("#{current_releases_version_path}/relup")

    Foundation.RpcMock
    |> stub(:call, fn
      ^node, :release_handler, :unpack_release, _params, @expected_timeout ->
        {:ok, to_version}

      ^node, :release_handler, :which_releases, [], @expected_timeout ->
        []

      ^node, :code, :root_dir, [], @expected_timeout ->
        ~c"/tmp/deployex/varlib/service/deployex"

      ^node, :systools, :make_relup, _params, @expected_timeout ->
        {:ok, :relup, :systools_relup, []}

      ^node, :release_handler, :check_install_release, _params, @expected_timeout ->
        {:ok, :any, :any}

      ^node, _module, :load, [cfg, _arg], @expected_timeout ->
        cfg

      ^node, :persistent_term, :put, _params, @expected_timeout ->
        :ok

      ^node, :release_handler, :install_release, _params, @expected_timeout ->
        {:ok, :any, :any}

      ^node, :release_handler, :make_permanent, _params, @expected_timeout ->
        :ok
    end)

    with_mock Node, [:passthrough], connect: fn ^node -> true end do
      UpgradeApp.subscribe_events()

      assert :ok =
               UpgradeApp.execute(%Execute{
                 node: node,
                 sname: sname,
                 name: sname,
                 language: "elixir",
                 current_path: current_path,
                 new_path: new_path,
                 from_version: from_version,
                 to_version: to_version,
                 make_permanent_async: false,
                 sync_execution: true
               })

      assert_receive {:hot_upgrade_progress, ^node, ^sname, "Starting upgrade for deployex..."},
                     1_000

      assert_receive {:hot_upgrade_progress, ^node, ^sname, "Unpacking release"},
                     1_000

      assert_receive {:hot_upgrade_progress, ^node, ^sname, "Creating relup file"},
                     1_000

      assert_receive {:hot_upgrade_progress, ^node, ^sname, "Checking release can be installed"},
                     1_000

      assert_receive {:hot_upgrade_progress, ^node, ^sname,
                      "Resolving the runtime configuration"},
                     1_000

      assert_receive {:hot_upgrade_progress, ^node, ^sname, "Installing release"},
                     1_000

      assert_receive {:hot_upgrade_progress, ^node, ^sname,
                      "Adding the runtime configuration to the relup"},
                     1_000

      assert_receive {:hot_upgrade_progress, ^node, ^sname, "Making release 0.2.0 permanent"},
                     1_000

      assert_receive {:hot_upgrade_complete, ^node, ^sname, :ok,
                      "Hot upgrade applied successfully!"},
                     1_000
    end
  end

  @tag :capture_log
  test "execute/5 Elixir Deployex success async operation, make_permanent_async=false", %{
    current_path: current_path,
    new_path: new_path,
    from_version: from_version,
    to_version: to_version
  } do
    node = Node.self()
    sname = "deployex"
    current_releases_version_path = "#{current_path}/releases/#{to_version}"

    File.mkdir_p!(current_releases_version_path)
    File.cp!("./test/support/files/sys.config", "#{current_releases_version_path}/sys.config")
    write_relup!("#{current_releases_version_path}/relup")

    Foundation.RpcMock
    |> stub(:call, fn
      ^node, :release_handler, :unpack_release, _params, @expected_timeout ->
        {:ok, to_version}

      ^node, :release_handler, :which_releases, [], @expected_timeout ->
        []

      ^node, :code, :root_dir, [], @expected_timeout ->
        ~c"/tmp/deployex/varlib/service/deployex"

      ^node, :systools, :make_relup, _params, @expected_timeout ->
        {:ok, :relup, :systools_relup, []}

      ^node, :release_handler, :check_install_release, _params, @expected_timeout ->
        {:ok, :any, :any}

      ^node, _module, :load, [cfg, _arg], @expected_timeout ->
        cfg

      ^node, :persistent_term, :put, _params, @expected_timeout ->
        :ok

      ^node, :release_handler, :install_release, _params, @expected_timeout ->
        {:ok, :any, :any}

      ^node, :release_handler, :make_permanent, _params, @expected_timeout ->
        :ok
    end)

    with_mock Node, [:passthrough], connect: fn ^node -> true end do
      UpgradeApp.subscribe_events()

      assert :ok =
               UpgradeApp.execute(%Execute{
                 node: node,
                 sname: sname,
                 name: sname,
                 language: "elixir",
                 current_path: current_path,
                 new_path: new_path,
                 from_version: from_version,
                 to_version: to_version,
                 make_permanent_async: false,
                 sync_execution: false
               })

      assert_receive {:hot_upgrade_progress, ^node, ^sname, "Starting upgrade for deployex..."},
                     1_000

      assert_receive {:hot_upgrade_progress, ^node, ^sname, "Unpacking release"},
                     1_000

      assert_receive {:hot_upgrade_progress, ^node, ^sname, "Creating relup file"},
                     1_000

      assert_receive {:hot_upgrade_progress, ^node, ^sname, "Checking release can be installed"},
                     1_000

      assert_receive {:hot_upgrade_progress, ^node, ^sname,
                      "Resolving the runtime configuration"},
                     1_000

      assert_receive {:hot_upgrade_progress, ^node, ^sname, "Installing release"},
                     1_000

      assert_receive {:hot_upgrade_progress, ^node, ^sname,
                      "Adding the runtime configuration to the relup"},
                     1_000

      assert_receive {:hot_upgrade_progress, ^node, ^sname, "Making release 0.2.0 permanent"},
                     1_000

      assert_receive {:hot_upgrade_complete, ^node, ^sname, :ok,
                      "Hot upgrade applied successfully!"},
                     1_000
    end
  end

  @tag :capture_log
  test "execute/5 Elixir Deployex error async operation, make_permanent_async=false", %{
    current_path: current_path,
    new_path: new_path,
    from_version: from_version,
    to_version: to_version
  } do
    node = Node.self()
    sname = "deployex"
    current_releases_version_path = "#{current_path}/releases/#{to_version}"

    File.mkdir_p!(current_releases_version_path)
    File.cp!("./test/support/files/sys.config", "#{current_releases_version_path}/sys.config")
    write_relup!("#{current_releases_version_path}/relup")

    Foundation.RpcMock
    |> stub(:call, fn
      ^node, :release_handler, :unpack_release, _params, @expected_timeout ->
        {:ok, to_version}

      ^node, :release_handler, :which_releases, [], @expected_timeout ->
        []

      ^node, :code, :root_dir, [], @expected_timeout ->
        ~c"/tmp/deployex/varlib/service/deployex"

      ^node, :systools, :make_relup, _params, @expected_timeout ->
        {:ok, :relup, :systools_relup, []}

      ^node, :release_handler, :check_install_release, _params, @expected_timeout ->
        {:ok, :any, :any}

      ^node, _module, :load, [cfg, _arg], @expected_timeout ->
        cfg

      ^node, :persistent_term, :put, _params, @expected_timeout ->
        :ok

      ^node, :release_handler, :install_release, _params, @expected_timeout ->
        {:ok, :any, :any}

      ^node, :release_handler, :make_permanent, _params, @expected_timeout ->
        {:error, :no_match_versions}
    end)

    with_mock Node, [:passthrough], connect: fn ^node -> true end do
      assert capture_log(fn ->
               UpgradeApp.subscribe_events()

               assert :ok =
                        UpgradeApp.execute(%Execute{
                          node: node,
                          sname: sname,
                          name: sname,
                          language: "elixir",
                          current_path: current_path,
                          new_path: new_path,
                          from_version: from_version,
                          to_version: to_version,
                          make_permanent_async: false,
                          sync_execution: false
                        })

               assert_receive {:hot_upgrade_progress, ^node, ^sname,
                               "Starting upgrade for deployex..."},
                              1_000

               assert_receive {:hot_upgrade_progress, ^node, ^sname, "Unpacking release"},
                              1_000

               assert_receive {:hot_upgrade_progress, ^node, ^sname, "Creating relup file"},
                              1_000

               assert_receive {:hot_upgrade_progress, ^node, ^sname,
                               "Checking release can be installed"},
                              1_000

               assert_receive {:hot_upgrade_progress, ^node, ^sname,
                               "Resolving the runtime configuration"},
                              1_000

               assert_receive {:hot_upgrade_progress, ^node, ^sname, "Installing release"},
                              1_000

               assert_receive {:hot_upgrade_progress, ^node, ^sname,
                               "Adding the runtime configuration to the relup"},
                              1_000

               assert_receive {:hot_upgrade_progress, ^node, ^sname,
                               "Making release 0.2.0 permanent"},
                              1_000

               assert_receive {:hot_upgrade_complete, ^node, ^sname, :error,
                               "Upgrade failed: {:error, {:error, :no_match_versions}}"},
                              1_000
             end) =~
               "Error while trying to set a permanent version for 0.2.0, reason: {:error, :no_match_versions}"
    end
  end

  @tag :capture_log
  test "execute/5 Elixir Deployex error async operation, make_permanent_async=true", %{
    current_path: current_path,
    new_path: new_path,
    from_version: from_version,
    to_version: to_version
  } do
    node = Node.self()
    sname = "deployex"
    current_releases_version_path = "#{current_path}/releases/#{to_version}"

    File.mkdir_p!(current_releases_version_path)
    File.cp!("./test/support/files/sys.config", "#{current_releases_version_path}/sys.config")
    write_relup!("#{current_releases_version_path}/relup")

    Foundation.RpcMock
    |> stub(:call, fn
      ^node, :release_handler, :unpack_release, _params, @expected_timeout ->
        {:ok, to_version}

      ^node, :release_handler, :which_releases, [], @expected_timeout ->
        []

      ^node, :code, :root_dir, [], @expected_timeout ->
        ~c"/tmp/deployex/varlib/service/deployex"

      ^node, :systools, :make_relup, _params, @expected_timeout ->
        {:ok, :relup, :systools_relup, []}

      ^node, :release_handler, :check_install_release, _params, @expected_timeout ->
        {:ok, :any, :any}

      ^node, _module, :load, [cfg, _arg], @expected_timeout ->
        cfg

      ^node, :persistent_term, :put, _params, @expected_timeout ->
        :ok

      ^node, :release_handler, :install_release, _params, @expected_timeout ->
        {:ok, :any, :any}

      ^node, :release_handler, :make_permanent, _params, @expected_timeout ->
        {:error, :no_match_versions}
    end)

    with_mock Node, [:passthrough], connect: fn ^node -> true end do
      ref = make_ref()
      test_pid = self()

      after_async_make_permanent = fn ->
        send(test_pid, {:handle_ref_event, ref})
      end

      assert capture_log(fn ->
               UpgradeApp.subscribe_events()

               assert :ok =
                        UpgradeApp.execute(%Execute{
                          node: node,
                          sname: sname,
                          name: sname,
                          language: "elixir",
                          current_path: current_path,
                          new_path: new_path,
                          from_version: from_version,
                          to_version: to_version,
                          make_permanent_async: true,
                          sync_execution: false,
                          after_async_make_permanent: after_async_make_permanent
                        })

               assert_receive {:hot_upgrade_progress, ^node, ^sname,
                               "Starting upgrade for deployex..."},
                              1_000

               assert_receive {:hot_upgrade_progress, ^node, ^sname, "Unpacking release"},
                              1_000

               assert_receive {:hot_upgrade_progress, ^node, ^sname, "Creating relup file"},
                              1_000

               assert_receive {:hot_upgrade_progress, ^node, ^sname,
                               "Checking release can be installed"},
                              1_000

               assert_receive {:hot_upgrade_progress, ^node, ^sname,
                               "Resolving the runtime configuration"},
                              1_000

               assert_receive {:hot_upgrade_progress, ^node, ^sname, "Installing release"},
                              1_000

               assert_receive {:hot_upgrade_progress, ^node, ^sname,
                               "Adding the runtime configuration to the relup"},
                              1_000

               assert_receive {:hot_upgrade_complete, ^node, ^sname, :error,
                               "Upgrade failed: {:error, {:error, :no_match_versions}}"},
                              1_000
             end) =~
               "Error while trying to set a permanent version for 0.2.0, reason: {:error, :no_match_versions}"
    end
  end

  describe "remove_unpacked_release/1" do
    @tag :capture_log
    test "removes a release that was unpacked but never installed", %{node: node} do
      test_pid = self()

      Foundation.RpcMock
      |> stub(:call, fn
        ^node, :release_handler, :which_releases, [], @expected_timeout ->
          [{~c"testapp", ~c"0.2.0", [], :unpacked}, {~c"testapp", ~c"0.1.0", [], :permanent}]

        ^node, :release_handler, :remove_release, [version], @expected_timeout ->
          send(test_pid, {:removed, version})
          :ok
      end)

      assert :ok =
               UpgradeApp.remove_unpacked_release(%Execute{node: node, to_version: "0.2.0"})

      assert_receive {:removed, ~c"0.2.0"}
    end

    @tag :capture_log
    test "leaves an installed release alone", %{node: node} do
      Foundation.RpcMock
      |> stub(:call, fn
        ^node, :release_handler, :which_releases, [], @expected_timeout ->
          # already in use, removing it would pull the running code away
          [{~c"testapp", ~c"0.2.0", [], :current}]

        ^node, :release_handler, :remove_release, _args, @expected_timeout ->
          flunk("must not remove a release that is in use")
      end)

      assert :ok =
               UpgradeApp.remove_unpacked_release(%Execute{node: node, to_version: "0.2.0"})
    end

    @tag :capture_log
    test "does nothing when the release was never unpacked", %{node: node} do
      Foundation.RpcMock
      |> stub(:call, fn
        ^node, :release_handler, :which_releases, [], @expected_timeout ->
          [{~c"testapp", ~c"0.1.0", [], :permanent}]

        ^node, :release_handler, :remove_release, _args, @expected_timeout ->
          flunk("nothing to remove")
      end)

      assert :ok =
               UpgradeApp.remove_unpacked_release(%Execute{node: node, to_version: "0.2.0"})
    end

    @tag :capture_log
    test "reports a removal failure without raising", %{node: node} do
      Foundation.RpcMock
      |> stub(:call, fn
        ^node, :release_handler, :which_releases, [], @expected_timeout ->
          [{~c"testapp", ~c"0.2.0", [], :unpacked}]

        ^node, :release_handler, :remove_release, _args, @expected_timeout ->
          {:error, :enoent}
      end)

      assert capture_log(fn ->
               assert :ok =
                        UpgradeApp.remove_unpacked_release(%Execute{
                          node: node,
                          to_version: "0.2.0"
                        })
             end) =~ "Error while removing the unpacked release"
    end
  end
end
