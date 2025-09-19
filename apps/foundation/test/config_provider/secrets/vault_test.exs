defmodule Foundation.ConfigProvider.Secrets.VaultTest do
  use ExUnit.Case, async: false

  import Mock

  alias Foundation.ConfigProvider.Secrets.Manager
  alias Foundation.ConfigProvider.Secrets.Vault

  test "secrets/3 with success with default mount_path" do
    with_mocks([
      {Vaultx.Secrets.KV, [],
       [
         read: fn "any-env-path", [mount_path: "secret", cache: false] ->
           {:ok,
            %{
              data: %{
                "DEPLOYEX_ADMIN_HASHED_PASSWORD" =>
                  "$2b$12$nqB622nfq7KOWYS97xDrP.8DNToPxf4zHZFXeVOPc7GnlJbZ7.Dyq",
                "DEPLOYEX_ERLANG_COOKIE" => "my-cookie",
                "DEPLOYEX_SECRET_KEY_BASE" =>
                  "RsE6okQAKEfugxTRy5AGrQSZxnywA95AR/PRKGQNoemjg7w+Zgb8wp+UexIkgwsM"
              }
            }}
         end
       ]}
    ]) do
      assert [
               {:vaultx,
                [
                  {:config, %{url: "https://vault.test:8200", token: "test-token"}}
                ]},
               {:foundation,
                [
                  {Manager,
                   [
                     adapter: Vault,
                     path: "any-env-path"
                   ]},
                  {:env, "prod"},
                  {Foundation.Accounts,
                   [
                     admin_hashed_password:
                       "$2b$12$nqB622nfq7KOWYS97xDrP.8DNToPxf4zHZFXeVOPc7GnlJbZ7.Dyq"
                   ]}
                ]},
               {:deployex_web,
                [
                  {DeployexWeb.Endpoint,
                   [
                     secret_key_base:
                       "RsE6okQAKEfugxTRy5AGrQSZxnywA95AR/PRKGQNoemjg7w+Zgb8wp+UexIkgwsM"
                   ]}
                ]}
             ] =
               Manager.load(
                 [
                   foundation: [
                     {Manager,
                      [
                        adapter: Vault,
                        path: "any-env-path"
                      ]},
                     {:env, "prod"}
                   ],
                   vaultx: [
                     config: %{url: "https://vault.test:8200", token: "test-token"}
                   ]
                 ],
                 []
               )
    end
  end

  test "secrets/3 with custom vault_mount_path" do
    with_mocks([
      {Vaultx.Secrets.KV, [],
       [
         read: fn "deployex/prod/secrets", [mount_path: "custom-kv", cache: false] ->
           {:ok,
            %{
              data: %{
                "DEPLOYEX_ADMIN_HASHED_PASSWORD" =>
                  "$2b$12$nqB622nfq7KOWYS97xDrP.8DNToPxf4zHZFXeVOPc7GnlJbZ7.Dyq",
                "DEPLOYEX_ERLANG_COOKIE" => "my-cookie",
                "DEPLOYEX_SECRET_KEY_BASE" =>
                  "RsE6okQAKEfugxTRy5AGrQSZxnywA95AR/PRKGQNoemjg7w+Zgb8wp+UexIkgwsM"
              }
            }}
         end
       ]}
    ]) do
      assert [
               {:vaultx,
                [
                  {:config, %{url: "https://vault.test:8200", token: "test-token"}},
                  {:mount_path, "custom-kv"}
                ]},
               {:foundation,
                [
                  {Manager,
                   [
                     adapter: Vault,
                     path: "deployex/prod/secrets",
                     vault_mount_path: "custom-kv"
                   ]},
                  {:env, "prod"},
                  {Foundation.Accounts,
                   [
                     admin_hashed_password:
                       "$2b$12$nqB622nfq7KOWYS97xDrP.8DNToPxf4zHZFXeVOPc7GnlJbZ7.Dyq"
                   ]}
                ]},
               {:deployex_web,
                [
                  {DeployexWeb.Endpoint,
                   [
                     secret_key_base:
                       "RsE6okQAKEfugxTRy5AGrQSZxnywA95AR/PRKGQNoemjg7w+Zgb8wp+UexIkgwsM"
                   ]}
                ]}
             ] =
               Manager.load(
                 [
                   foundation: [
                     {Manager,
                      [
                        adapter: Vault,
                        path: "deployex/prod/secrets",
                        vault_mount_path: "custom-kv"
                      ]},
                     {:env, "prod"}
                   ],
                   vaultx: [
                     config: %{url: "https://vault.test:8200", token: "test-token"},
                     mount_path: "custom-kv"
                   ]
                 ],
                 []
               )
    end
  end

  test "secrets/3 with connection error" do
    with_mocks([
      {Vaultx.Secrets.KV, [],
       [
         read: fn _path, _opts ->
           {:error, %Vaultx.Base.Error{type: :connection_error, message: "Connection refused"}}
         end
       ]}
    ]) do
      assert_raise RuntimeError, fn ->
        Manager.load(
          [
            foundation: [
              {Manager,
               [
                 adapter: Vault,
                 path: "any-env-path"
               ]},
              {:env, "prod"}
            ],
            vaultx: [
              config: %{url: "https://vault.test:8200", token: "test-token"},
              mount_path: "custom-kv"
            ]
          ],
          []
        )
      end
    end
  end
end
