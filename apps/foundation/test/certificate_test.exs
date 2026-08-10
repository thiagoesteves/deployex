defmodule Foundation.CertificateTest do
  use ExUnit.Case, async: false

  import Mock

  alias Foundation.Certificate
  alias Foundation.Certificates.Manager.Supervisor
  # ---------------------------------------------------------------------------
  # stop_certificate_manager/1
  # ---------------------------------------------------------------------------

  describe "stop_certificate_manager/1" do
    @tag :capture_log
    test "delegates to Supervisor.stop_certificate_manager and returns :ok" do
      with_mock Supervisor, stop_certificate_manager: fn "my_app" -> :ok end do
        assert :ok = Certificate.stop_certificate_manager("my_app")
        assert called(Supervisor.stop_certificate_manager("my_app"))
      end
    end

    @tag :capture_log
    test "propagates {:error, :not_found} when supervisor says the manager is absent" do
      with_mock Supervisor,
        stop_certificate_manager: fn _name -> {:error, :not_found} end do
        assert {:error, :not_found} = Certificate.stop_certificate_manager("missing_app")
      end
    end

    @tag :capture_log
    test "passes the app_name through unchanged" do
      with_mock Supervisor,
        stop_certificate_manager: fn name ->
          assert name == "exact_app_name"
          :ok
        end do
        Certificate.stop_certificate_manager("exact_app_name")
      end
    end
  end

  # ---------------------------------------------------------------------------
  # export_to_files/3
  # ---------------------------------------------------------------------------

  describe "export_to_files/3" do
    setup do
      dir = Path.join(System.tmp_dir!(), "cert-export-#{System.unique_integer([:positive])}")
      on_exit(fn -> File.rm_rf(dir) end)
      %{dir: dir, cert_path: Path.join(dir, "host.pem"), key_path: Path.join(dir, "host-key.pem")}
    end

    @tag :capture_log
    test "writes the full chain and the private key", %{
      dir: dir,
      cert_path: cert_path,
      key_path: key_path
    } do
      stored = %Foundation.Catalog.Certificate{
        certificate_pem: "-----BEGIN CERTIFICATE-----\nLEAF\n-----END CERTIFICATE-----",
        chain_certificate_pem:
          "-----BEGIN CERTIFICATE-----\nINTERMEDIATE\n-----END CERTIFICATE-----",
        private_key_pem: "-----BEGIN PRIVATE KEY-----\nKEY\n-----END PRIVATE KEY-----"
      }

      with_mock Foundation.Catalog, [:passthrough], certificate: fn "nerveshub" -> stored end do
        assert {:ok, %{certificate_path: ^cert_path, private_key_path: ^key_path}} =
                 Certificate.export_to_files("nerveshub", cert_path, key_path)
      end

      # the parent directory is created, the caller only supplies file paths
      assert File.dir?(dir)

      chain = File.read!(cert_path)
      # leaf first, then the intermediates, which is the order a client expects
      assert chain =~ "LEAF"
      assert chain =~ "INTERMEDIATE"
      assert :binary.match(chain, "LEAF") < :binary.match(chain, "INTERMEDIATE")

      assert File.read!(key_path) =~ "KEY"

      # the private key must not be world readable
      assert %{mode: key_mode} = File.stat!(key_path)
      assert Bitwise.band(key_mode, 0o777) == 0o600
      assert %{mode: cert_mode} = File.stat!(cert_path)
      assert Bitwise.band(cert_mode, 0o777) == 0o644
    end

    @tag :capture_log
    test "writes only the leaf when there is no chain", %{
      cert_path: cert_path,
      key_path: key_path
    } do
      stored = %Foundation.Catalog.Certificate{
        certificate_pem: "LEAF",
        chain_certificate_pem: nil,
        private_key_pem: "KEY"
      }

      with_mock Foundation.Catalog, [:passthrough], certificate: fn _ -> stored end do
        assert {:ok, _} = Certificate.export_to_files("nerveshub", cert_path, key_path)
      end

      assert File.read!(cert_path) == "LEAF\n"
    end

    @tag :capture_log
    test "writes only the file whose path is given", %{dir: dir} do
      stored = %Foundation.Catalog.Certificate{
        certificate_pem: "LEAF",
        private_key_pem: "KEY"
      }

      cert_only = Path.join(dir, "cert-only.pem")
      key_only = Path.join(dir, "key-only.pem")

      with_mock Foundation.Catalog, [:passthrough], certificate: fn _ -> stored end do
        assert {:ok, _} = Certificate.export_to_files("nerveshub", cert_only, nil)
        assert {:ok, _} = Certificate.export_to_files("nerveshub", nil, key_only)
      end

      # a nil path skips that file rather than raising on Path.dirname/1
      assert File.read!(cert_only) == "LEAF\n"
      assert File.read!(key_only) == "KEY"
      refute File.exists?(Path.join(dir, "host.pem"))
    end

    @tag :capture_log
    test "returns not_found when no certificate has been issued", %{
      cert_path: cert_path,
      key_path: key_path
    } do
      with_mock Foundation.Catalog, [:passthrough],
        certificate: fn _ -> %Foundation.Catalog.Certificate{} end do
        assert {:error, :not_found} =
                 Certificate.export_to_files("nerveshub", cert_path, key_path)
      end

      refute File.exists?(cert_path)
    end

    @tag :capture_log
    test "reports the path when the destination cannot be written", %{dir: dir} do
      stored = %Foundation.Catalog.Certificate{certificate_pem: "LEAF", private_key_pem: "KEY"}

      # deployex runs unprivileged, so an unwritable target is the expected failure. A
      # regular file where a directory is needed reproduces it without mocking File, which
      # the whole test suite depends on, and without relying on the test user not being root
      File.mkdir_p!(dir)
      blocker = Path.join(dir, "blocker")
      File.write!(blocker, "")
      cert_path = Path.join(blocker, "host.pem")

      with_mock Foundation.Catalog, [:passthrough], certificate: fn _ -> stored end do
        assert {:error, {:write_failed, ^cert_path, _reason}} =
                 Certificate.export_to_files("nerveshub", cert_path, Path.join(blocker, "k.pem"))
      end
    end
  end
end
