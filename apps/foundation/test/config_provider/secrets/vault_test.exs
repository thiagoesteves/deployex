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
      System.put_env("VAULTX_URL", "https://vault.test:8200")
      System.put_env("VAULTX_TOKEN", "test-token")

      assert [
               {:foundation,
                [
                  {Manager, [adapter: Vault, path: "any-env-path"]},
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
                     {Manager, adapter: Vault, path: "any-env-path"},
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
      System.put_env("VAULTX_URL", "https://vault.test:8200")
      System.put_env("VAULTX_TOKEN", "test-token")

      assert_raise RuntimeError, fn ->
        Manager.load(
          [
            foundation: [
              {Manager, adapter: Vault, path: "any-env-path"},
              {:env, "prod"}
            ]
          ],
          []
        )
      end
    end
  end
end
