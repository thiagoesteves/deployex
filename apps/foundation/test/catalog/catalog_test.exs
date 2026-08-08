defmodule Foundation.CatalogTest do
  use ExUnit.Case, async: true

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
    assert {:ok, %Catalog.Version{id: id} = stored} = Catalog.add_version(version)
    assert is_binary(id)
    assert [^stored] = Catalog.versions(name, [])
  end

  test "update_version/1 rewrites the record in place", %{name: name} do
    # A full deployment records the version before the node has started, so the outcome is
    # only known later and must not append a second entry
    {:ok, stored} =
      Catalog.add_version(%Catalog.Version{
        version: "0.0.0",
        name: name,
        outcome: :started,
        inserted_at: NaiveDateTime.utc_now()
      })

    assert {:ok, _updated} =
             Catalog.update_version(%{stored | outcome: :ok, duration_ms: 1234})

    assert [%Catalog.Version{outcome: :ok, duration_ms: 1234, id: id}] =
             Catalog.versions(name, [])

    assert id == stored.id
  end

  test "update_version/1 without a stored record", %{name: name} do
    assert {:error, :not_found} =
             Catalog.update_version(%Catalog.Version{version: "0.0.0", name: name, id: "nope"})

    assert {:error, :not_found} =
             Catalog.update_version(%Catalog.Version{version: "0.0.0", name: name})
  end

  test "versions/2 reads records written before the newer fields existed", %{name: name} do
    # DeployEx hot upgrades itself and then reads the history it wrote beforehand, so a
    # record decoded without the newer keys must not raise
    legacy = %{
      __struct__: Catalog.Version,
      version: "0.0.0",
      hash: nil,
      pre_commands: [],
      name: name,
      sname: "#{name}-abc123",
      deployment: :full_deployment,
      inserted_at: NaiveDateTime.utc_now()
    }

    path = "#{Application.get_env(:foundation, :var_path)}/storage/#{name}/deployex/history"
    File.mkdir_p!(path)
    File.write!("#{path}/legacy.term", :erlang.term_to_binary(legacy))

    assert [%Catalog.Version{} = version] = Catalog.versions(name, [])
    assert version.version == "0.0.0"
    assert version.outcome == nil
    assert version.from_version == nil
    assert version.duration_ms == nil
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
