defmodule Foundation.ConfigProvider.Secrets.VaultTest do
  use ExUnit.Case, async: false

  import Mock

  alias Foundation.ConfigProvider.Secrets.Vault
  alias Foundation.ConfigProvider.Secrets.Manager

  test "secrets/3 with success" do
    with_mocks([
      {Vaultx.Secrets.KV.V2, [],
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
               {:foundation,
                [
                  {Manager,
                   [
                     adapter: Vault,
                     path: "any-env-path",
                     vault_url: "https://vault.test:8200",
                     vault_token: "test-token"
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
                        path: "any-env-path",
                        vault_url: "https://vault.test:8200",
                        vault_token: "test-token"
                      ]},
                     {:env, "prod"}
                   ]
                 ],
                 []
               )
    end
  end

  test "secrets/3 with custom vault_mount_path" do
    with_mocks([
      {Vaultx.Secrets.KV.V2, [],
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
               {:foundation,
                [
                  {Manager,
                   [
                     adapter: Vault,
                     path: "deployex/prod/secrets",
                     vault_mount_path: "custom-kv",
                     vault_url: "https://vault.test:8200",
                     vault_token: "test-token"
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
                        vault_mount_path: "custom-kv",
                        vault_url: "https://vault.test:8200",
                        vault_token: "test-token"
                      ]},
                     {:env, "prod"}
                   ]
                 ],
                 []
               )
    end
  end

  test "secrets/3 with connection error" do
    with_mocks([
      {Vaultx.Secrets.KV.V2, [],
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
                 path: "any-env-path",
                 vault_url: "https://vault.test:8200",
                 vault_token: "test-token"
               ]},
              {:env, "prod"}
            ]
          ],
          []
        )
      end
    end
  end

  test "secrets/3 fails when vault_url is not defined" do
    assert_raise RuntimeError, ~r/vault_url is required in configuration/, fn ->
      Manager.load(
        [
          foundation: [
            {Manager, [adapter: Vault, path: "any-env-path", vault_token: "test-token"]},
            {:env, "prod"}
          ]
        ],
        []
      )
    end
  end

  test "secrets/3 fails when vault_token is not defined" do
    assert_raise RuntimeError, ~r/vault_token is required in configuration/, fn ->
      Manager.load(
        [
          foundation: [
            {Manager,
             [adapter: Vault, path: "any-env-path", vault_url: "https://vault.test:8200"]},
            {:env, "prod"}
          ]
        ],
        []
      )
    end
  end

  test "secrets/3 fails when both vault_url and vault_token are not defined" do
    assert_raise RuntimeError, ~r/vault_url is required in configuration/, fn ->
      Manager.load(
        [
          foundation: [
            {Manager, [adapter: Vault, path: "any-env-path"]},
            {:env, "prod"}
          ]
        ],
        []
      )
    end
  end

  test "secrets/3 fails when vault_url is empty string" do
    assert_raise RuntimeError, ~r/vault_url is required in configuration/, fn ->
      Manager.load(
        [
          foundation: [
            {Manager,
             [adapter: Vault, path: "any-env-path", vault_url: "", vault_token: "test-token"]},
            {:env, "prod"}
          ]
        ],
        []
      )
    end
  end

  test "secrets/3 fails when vault_token is empty string" do
    assert_raise RuntimeError, ~r/vault_token is required in configuration/, fn ->
      Manager.load(
        [
          foundation: [
            {Manager,
             [
               adapter: Vault,
               path: "any-env-path",
               vault_url: "https://vault.test:8200",
               vault_token: ""
             ]},
            {:env, "prod"}
          ]
        ],
        []
      )
    end
  end
end
