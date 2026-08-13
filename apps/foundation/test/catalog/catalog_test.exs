defmodule Foundation.CatalogTest do
  # NOTE: The setup wipes var_path, a directory the whole suite shares, so this module cannot run
  #       next to the async ones. Removing it while Foundation.CatalogExDocTest walks the same
  #       tree makes its mkdir_p fail with :enotdir
  use ExUnit.Case, async: false

  alias Foundation.Accounts.UserToken
  alias Foundation.Catalog

  setup do
    Application.get_env(:foundation, :var_path) |> File.rm_rf()

    name =
      Application.get_env(:foundation, :applications)
      |> Enum.at(0)
      |> Map.get(:name)

    Catalog.setup_all_apps()
    %{name: name}
  end

  test "versions/2", %{name: name} do
    assert Catalog.versions(name, []) == []
  end

  test "add_version/1", %{name: name} do
    version = %Catalog.Version{version: "0.0.0", name: name}
    assert :ok = Catalog.add_version(version)
    assert [^version] = Catalog.versions(name, [])
  end

  test "ghosted_versions/0", %{name: name} do
    assert [] == Catalog.ghosted_versions(name)
  end

  test "add_ghosted_version/1", %{name: name} do
    version = %Catalog.Version{version: "0.0.0", name: name}
    assert {:ok, [^version]} = Catalog.add_ghosted_version(version)
    assert [^version] = Catalog.ghosted_versions(name)
  end

  test "remove_ghosted_version/2", %{name: name} do
    keep = %Catalog.Version{version: "1.0.0", name: name}
    remove = %Catalog.Version{version: "2.0.0", name: name}

    assert {:ok, _} = Catalog.add_ghosted_version(keep)
    assert {:ok, _} = Catalog.add_ghosted_version(remove)

    assert {:ok, [^keep]} = Catalog.remove_ghosted_version(name, "2.0.0")
    assert [^keep] = Catalog.ghosted_versions(name)
  end

  test "remove_ghosted_version/2 with a version that is not ghosted", %{name: name} do
    version = %Catalog.Version{version: "1.0.0", name: name}
    assert {:ok, _} = Catalog.add_ghosted_version(version)

    # removing something that was never ghosted leaves the list as it is
    assert {:ok, [^version]} = Catalog.remove_ghosted_version(name, "9.9.9")
  end

  test "remove_ghosted_version/2 allows the version to be ghosted again", %{name: name} do
    version = %Catalog.Version{version: "1.0.0", name: name}

    assert {:ok, _} = Catalog.add_ghosted_version(version)
    assert {:ok, []} = Catalog.remove_ghosted_version(name, "1.0.0")
    assert {:ok, [^version]} = Catalog.add_ghosted_version(version)
  end

  test "clear_ghosted_versions/1", %{name: name} do
    assert {:ok, _} = Catalog.add_ghosted_version(%Catalog.Version{version: "1.0.0", name: name})
    assert {:ok, _} = Catalog.add_ghosted_version(%Catalog.Version{version: "2.0.0", name: name})

    assert {:ok, []} = Catalog.clear_ghosted_versions(name)
    assert [] == Catalog.ghosted_versions(name)
  end

  test "clear_ghosted_versions/1 with an empty list", %{name: name} do
    assert {:ok, []} = Catalog.clear_ghosted_versions(name)
  end

  test "add_user_session_token/1" do
    user_session = %UserToken{token: "123456789"}
    assert :ok = Catalog.add_user_session_token(user_session)
    assert user_session == Catalog.get_user_session_token_by_token(user_session.token)
  end

  test "config/1", %{name: name} do
    assert %Catalog.Config{mode: :automatic, manual_version: nil} = Catalog.config(name)
  end

  test "config_update/1", %{name: name} do
    expected_config = %Catalog.Config{mode: :manual, manual_version: nil}
    config = Catalog.config(name)
    assert {:ok, ^expected_config} = Catalog.config_update(name, %{config | mode: :manual})
    assert ^expected_config = Catalog.config(name)
  end
end
