defmodule Foundation.CatalogTest do
  use ExUnit.Case, async: true

  alias Foundation.Accounts.UserToken
  alias Foundation.Catalog

  setup do
    Application.get_env(:foundation, :base_path) |> File.rm_rf()

    # Remove any current.json file
    monitored_app = Catalog.monitored_app_name()
    current_json_dir = "/tmp/#{monitored_app}/versions/#{monitored_app}/local"
    File.rm_rf(current_json_dir)

    Catalog.setup()
  end

  test "versions/0" do
    assert Catalog.versions() == []
  end

  test "versions/1" do
    assert Catalog.versions(0) == []
  end

  test "add_version/1" do
    version = %Catalog.Version{version: "0.0.0"}
    assert :ok = Catalog.add_version(version)
    assert [^version] = Catalog.versions()
  end

  test "ghosted_versions/0" do
    assert [] == Catalog.ghosted_versions()
  end

  test "add_ghosted_version/1" do
    version = %Catalog.Version{version: "0.0.0"}
    assert {:ok, [^version]} = Catalog.add_ghosted_version(version)
    assert [^version] = Catalog.ghosted_versions()
  end

  test "add_user_session_token/1" do
    user_session = %UserToken{token: "123456789"}
    assert :ok = Catalog.add_user_session_token(user_session)
    assert user_session == Catalog.get_user_session_token_by_token(user_session.token)
  end

  test "config/1" do
    assert %Catalog.Config{mode: :automatic, manual_version: nil} = Catalog.config()
  end

  test "config_update/1" do
    expected_config = %Catalog.Config{mode: :manual, manual_version: nil}
    config = Catalog.config()
    assert {:ok, ^expected_config} = Catalog.config_update(%{config | mode: :manual})
    assert ^expected_config = Catalog.config()
  end
end
