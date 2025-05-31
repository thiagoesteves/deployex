defmodule Foundation.CatalogTest do
  use ExUnit.Case, async: true

  alias Foundation.Accounts.UserToken
  alias Foundation.Catalog

  setup do
    Application.get_env(:foundation, :base_path) |> File.rm_rf()

    name =
      Application.get_env(:foundation, :applications)
      |> Enum.at(0)
      |> Map.get(:name)

    Catalog.setup()
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
