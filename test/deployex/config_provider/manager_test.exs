defmodule Deployex.ConfigProvider.ManagerTest do
  use ExUnit.Case, async: false

  import Mock
  import Mox

  setup :set_mox_global
  setup :verify_on_exit!

  alias Deployex.ConfigProvider.Secrets.Manager
  alias Deployex.ConfigProvider.SecretsMock

  test "init/1 with success" do
    assert Manager.init(:any) == []
  end

  test "load/2 with non-local config and non setting cookie" do
    SecretsMock
    |> stub(:secrets, fn _config, _path, _options ->
      %{
        "DEPLOYEX_ADMIN_HASHED_PASSWORD" =>
          "$2b$12$nqB622nfq7KOWYS97xDrP.8DNToPxf4zHZFXeVOPc7GnlJbZ7.Dyq",
        "DEPLOYEX_ERLANG_COOKIE" => "my-cookie",
        "DEPLOYEX_SECRET_KEY_BASE" =>
          "RsE6okQAKEfugxTRy5AGrQSZxnywA95AR/PRKGQNoemjg7w+Zgb8wp+UexIkgwsM"
      }
    end)

    assert [
             {:deployex,
              [
                {Deployex.ConfigProvider.Secrets.Manager,
                 [adapter: SecretsMock, path: "any-env-path"]},
                {:env, "prod"},
                {DeployexWeb.Endpoint,
                 [
                   secret_key_base:
                     "RsE6okQAKEfugxTRy5AGrQSZxnywA95AR/PRKGQNoemjg7w+Zgb8wp+UexIkgwsM"
                 ]},
                {Deployex.Accounts,
                 [
                   admin_hashed_password:
                     "$2b$12$nqB622nfq7KOWYS97xDrP.8DNToPxf4zHZFXeVOPc7GnlJbZ7.Dyq"
                 ]}
              ]}
           ] =
             Manager.load(
               [
                 deployex: [
                   {Deployex.ConfigProvider.Secrets.Manager,
                    adapter: SecretsMock, path: "any-env-path"},
                   {:env, "prod"}
                 ]
               ],
               []
             )
  end

  test "load/2 with non-local config and set cookie" do
    SecretsMock
    |> stub(:secrets, fn _config, _path, _options ->
      %{
        "DEPLOYEX_ADMIN_HASHED_PASSWORD" =>
          "$2b$12$nqB622nfq7KOWYS97xDrP.8DNToPxf4zHZFXeVOPc7GnlJbZ7.Dyq",
        "DEPLOYEX_ERLANG_COOKIE" => "my-cookie",
        "DEPLOYEX_SECRET_KEY_BASE" =>
          "RsE6okQAKEfugxTRy5AGrQSZxnywA95AR/PRKGQNoemjg7w+Zgb8wp+UexIkgwsM"
      }
    end)

    with_mock Node,
      self: fn -> :app@hostname end,
      set_cookie: fn _node, :"my-cookie" -> :ok end do
      assert [
               {:deployex,
                [
                  {Deployex.ConfigProvider.Secrets.Manager,
                   [adapter: SecretsMock, path: "any-env-path"]},
                  {:env, "prod"},
                  {DeployexWeb.Endpoint,
                   [
                     secret_key_base:
                       "RsE6okQAKEfugxTRy5AGrQSZxnywA95AR/PRKGQNoemjg7w+Zgb8wp+UexIkgwsM"
                   ]},
                  {Deployex.Accounts,
                   [
                     admin_hashed_password:
                       "$2b$12$nqB622nfq7KOWYS97xDrP.8DNToPxf4zHZFXeVOPc7GnlJbZ7.Dyq"
                   ]}
                ]}
             ] =
               Manager.load(
                 [
                   deployex: [
                     {Deployex.ConfigProvider.Secrets.Manager,
                      adapter: SecretsMock, path: "any-env-path"},
                     {:env, "prod"}
                   ]
                 ],
                 []
               )
    end
  end

  test "load/2 with local config" do
    assert [
             {:deployex,
              [
                {Deployex.ConfigProvider.Secrets.Manager,
                 [adapter: Deployex.ConfigProvider.SecretsMock, path: "any-env-path"]},
                {:env, "local"}
              ]}
           ] =
             Manager.load(
               [
                 deployex: [
                   {Deployex.ConfigProvider.Secrets.Manager,
                    adapter: SecretsMock, path: "any-env-path"},
                   {:env, "local"}
                 ]
               ],
               []
             )
  end
end
