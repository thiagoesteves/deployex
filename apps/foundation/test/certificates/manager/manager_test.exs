defmodule Foundation.Certificates.ManagerTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  import Mock

  alias Foundation.Catalog
  alias Foundation.Catalog.Certificate
  alias Foundation.Certificates.Manager
  alias Foundation.Fixture.Stubs
  alias Foundation.Network

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp base_config(overrides \\ []) do
    struct(
      Manager,
      Keyword.merge(
        [
          app_name: "test_app",
          domains: ["example.com"],
          certificate_check_interval_ms: 100,
          dns_propagation_timeout_ms: 200,
          dns_check_interval_ms: 50,
          renew_before_days: 30,
          dns_provider: Stubs.DNSProvider,
          dns_options: %{zone: "Z123"},
          acme_provider: Stubs.ACMEProvider,
          acme_options: %{},
          importer: Stubs.Importer,
          importer_options: %{}
        ],
        overrides
      )
    )
  end

  defp valid_existing_cert do
    %Certificate{
      certificate_pem: "pem",
      chain_certificate_pem: "chain",
      domains: ["example.com"]
    }
  end

  describe "request_and_import_certificate/2" do
    @tag :capture_log
    test "skips generation when a valid certificate already exists" do
      existing = valid_existing_cert()

      with_mocks([
        {Catalog, [],
         [
           certificate: fn _app -> existing end,
           certificate_update: fn _app, c -> {:ok, c} end
         ]},
        {Catalog.Certificate, [],
         [
           valid?: fn ^existing, _threshold_days -> true end
         ]}
      ]) do
        assert {:ok, :valid, ^existing} = Manager.request_and_import_certificate(base_config())
      end
    end

    @tag :capture_log
    test "generates a new certificate when none exists (certificate_pem is nil)" do
      no_cert = %Certificate{certificate_pem: nil}

      with_mocks([
        {Catalog, [],
         [
           certificate: fn _app -> no_cert end,
           certificate_update: fn _app, c -> {:ok, c} end
         ]},
        {Catalog.Certificate, [],
         [
           new: fn _state -> no_cert end,
           metadata_from_cert_pem: fn _pem ->
             {:ok,
              %{
                issuer: "TestCA",
                valid_from: ~U[2024-01-01 00:00:00Z],
                valid_until: ~U[2025-01-01 00:00:00Z]
              }}
           end,
           split_certificate_chain: fn _pem -> {"cert_pem", "chain_pem"} end
         ]},
        {Network, [],
         [
           lookup: fn _domain_charlist, _class, _type, _options ->
             ["_acme.example.com.", "token123"]
           end
         ]}
      ]) do
        assert {:ok, :renewed, _cert} = Manager.request_and_import_certificate(base_config())
      end
    end

    @tag :capture_log
    test "generates a new certificate when force_renewal is true" do
      existing = valid_existing_cert()

      with_mocks([
        {Catalog, [],
         [
           certificate: fn _app -> existing end,
           certificate_update: fn _app, c -> {:ok, c} end
         ]},
        {Catalog.Certificate, [],
         [
           metadata_from_cert_pem: fn _pem ->
             {:ok,
              %{
                issuer: "TestCA",
                valid_from: ~U[2024-01-01 00:00:00Z],
                valid_until: ~U[2025-01-01 00:00:00Z]
              }}
           end,
           split_certificate_chain: fn _pem -> {"cert_pem", "chain_pem"} end
         ]},
        {Network, [],
         [
           lookup: fn _domain_charlist, _class, _type, _options ->
             ["_acme.example.com.", "token123"]
           end
         ]}
      ]) do
        assert {:ok, :renewed, _cert} =
                 Manager.request_and_import_certificate(base_config(), true)
      end
    end

    @tag :capture_log
    test "generates a new certificate when existing cert is invalid" do
      existing = valid_existing_cert()

      with_mocks([
        {Catalog, [],
         [
           certificate: fn _app -> existing end,
           certificate_update: fn _app, c -> {:ok, c} end
         ]},
        {Catalog.Certificate, [],
         [
           valid?: fn ^existing, _threshold_days -> false end,
           metadata_from_cert_pem: fn _pem ->
             {:ok,
              %{
                issuer: "TestCA",
                valid_from: ~U[2024-01-01 00:00:00Z],
                valid_until: ~U[2025-01-01 00:00:00Z]
              }}
           end,
           split_certificate_chain: fn _pem -> {"cert_pem", "chain_pem"} end
         ]},
        {Network, [],
         [
           lookup: fn _domain_charlist, _class, _type, _options ->
             ["_acme.example.com.", "token123"]
           end
         ]}
      ]) do
        assert {:ok, :renewed, _cert} = Manager.request_and_import_certificate(base_config())
      end
    end

    @tag :capture_log
    test "returns {:error, _} when the ACME provider fails during account setup" do
      no_cert = %Certificate{certificate_pem: nil}

      with_mocks([
        {Catalog, [],
         [
           certificate: fn _app -> no_cert end,
           certificate_update: fn _app, c -> {:ok, c} end
         ]},
        {Catalog.Certificate, [],
         [
           new: fn _state -> no_cert end
         ]}
      ]) do
        config = base_config(acme_provider: Stubs.FailingACMEProvider)

        log =
          capture_log(fn ->
            assert {:error, _} = Manager.request_and_import_certificate(config)
          end)

        assert log =~ "ACME certificate generation"
      end
    end

    @tag :capture_log
    test "returns {:error, _} when DNS record creation fails" do
      no_cert = %Certificate{certificate_pem: nil}

      with_mocks([
        {Catalog, [],
         [
           certificate: fn _app -> no_cert end,
           certificate_update: fn _app, c -> {:ok, c} end
         ]},
        {Catalog.Certificate, [],
         [
           new: fn _state -> no_cert end
         ]}
      ]) do
        config = base_config(dns_provider: Stubs.FailingDNSProvider)

        assert {:error, {:dns_record_creation_failed, :dns_failure}} =
                 Manager.request_and_import_certificate(config)
      end
    end

    @tag :capture_log
    test "logs success on valid cert reuse" do
      existing = valid_existing_cert()

      with_mocks([
        {Catalog, [],
         [
           certificate: fn _app -> existing end,
           certificate_update: fn _app, c -> {:ok, c} end
         ]},
        {Catalog.Certificate, [],
         [
           valid?: fn ^existing, _threshold_days -> true end
         ]}
      ]) do
        log =
          capture_log(fn ->
            Manager.request_and_import_certificate(base_config())
          end)

        assert log =~ "Using existing valid certificate"
      end
    end
  end

  describe "wait_for_dns_propagation (via request_and_import_certificate)" do
    @tag :capture_log
    test "times out when DNS never propagates and returns {:error, :dns_propagation_timeout}" do
      no_cert = %Certificate{certificate_pem: nil}
      challenge = %{record_name: "_acme.example.com.", record_value: "token"}

      with_mocks([
        {Catalog, [],
         [
           certificate: fn _app -> no_cert end,
           certificate_update: fn _app, c -> {:ok, c} end
         ]},
        {Catalog.Certificate, [],
         [
           new: fn _state -> no_cert end
         ]},
        # Override ACME so challenges are returned but DNS never propagates.
        {Stubs.ACMEProvider, [:passthrough],
         [
           get_dns_challenges: fn _app, _order, _key -> {:ok, [challenge]} end
         ]},
        {Network, [],
         [
           lookup: fn _domain_charlist, _class, _type, _options -> [] end
         ]}
      ]) do
        # Very short timeouts so the test is fast.
        config =
          base_config(
            dns_propagation_timeout_ms: 100,
            dns_check_interval_ms: 50
          )

        assert {:error, :dns_propagation_timeout} =
                 Manager.request_and_import_certificate(config)
      end
    end
  end

  describe "GenServer init / handle_continue" do
    @tag :capture_log
    test "starts successfully and schedules a check_and_renew timer" do
      existing = valid_existing_cert()

      with_mocks([
        {Catalog, [],
         [
           certificate: fn _app -> existing end,
           certificate_update: fn _app, c -> {:ok, c} end
         ]},
        {Catalog.Certificate, [],
         [
           valid?: fn _cert, _threshold_days -> true end
         ]}
      ]) do
        config = base_config(certificate_check_interval_ms: 60_000)
        assert {:ok, pid} = Manager.start_link(config)
        assert Process.alive?(pid)
        GenServer.stop(pid)
      end
    end

    @tag :capture_log
    test "logs initialization message on start" do
      existing = valid_existing_cert()

      with_mocks([
        {Catalog, [],
         [
           certificate: fn _app -> existing end,
           certificate_update: fn _app, c -> {:ok, c} end
         ]},
        {Catalog.Certificate, [],
         [
           valid?: fn _cert, _threshold_days -> true end
         ]}
      ]) do
        log =
          capture_log(fn ->
            {:ok, pid} = Manager.start_link(base_config())
            Process.sleep(50)
            GenServer.stop(pid)
          end)

        assert log =~ "Initializing Certificate Manager Renewal"
        assert log =~ "test_app"
      end
    end

    @tag :capture_log
    test "fires certificate_valid notification when existing cert is still valid" do
      existing = valid_existing_cert()
      test_pid = self()

      with_mocks([
        {Catalog, [],
         [
           certificate: fn _app -> existing end,
           certificate_update: fn _app, c -> {:ok, c} end
         ]},
        {Catalog.Certificate, [],
         [
           valid?: fn _cert, _threshold_days -> true end
         ]},
        {Foundation.Notifications, [:passthrough],
         [notify: fn event, _payload -> send(test_pid, {:notified, event}) end]}
      ]) do
        {:ok, pid} = Manager.start_link(base_config(certificate_check_interval_ms: 60_000))
        assert_receive {:notified, "certificate_valid"}, 500
        refute_received {:notified, "certificate_renewed"}
        GenServer.stop(pid)
      end
    end

    @tag :capture_log
    test "fires certificate_renewed notification when a new certificate is generated" do
      no_cert = %Certificate{certificate_pem: nil}
      test_pid = self()

      with_mocks([
        {Catalog, [],
         [
           certificate: fn _app -> no_cert end,
           certificate_update: fn _app, c -> {:ok, c} end
         ]},
        {Catalog.Certificate, [],
         [
           new: fn _state -> no_cert end,
           metadata_from_cert_pem: fn _pem ->
             {:ok,
              %{
                issuer: "TestCA",
                valid_from: ~U[2024-01-01 00:00:00Z],
                valid_until: ~U[2025-01-01 00:00:00Z]
              }}
           end,
           split_certificate_chain: fn _pem -> {"cert_pem", "chain_pem"} end
         ]},
        {Network, [],
         [
           lookup: fn _domain_charlist, _class, _type, _options ->
             ["_acme.example.com.", "token123"]
           end
         ]},
        {Foundation.Notifications, [:passthrough],
         [notify: fn event, _payload -> send(test_pid, {:notified, event}) end]}
      ]) do
        {:ok, pid} = Manager.start_link(base_config(certificate_check_interval_ms: 60_000))
        assert_receive {:notified, "certificate_renewed"}, 500
        refute_received {:notified, "certificate_valid"}
        GenServer.stop(pid)
      end
    end

    @tag :capture_log
    test "logs failure when certificate check errors during init" do
      with_mocks([
        {Catalog, [],
         [
           certificate: fn _app -> %Certificate{certificate_pem: nil} end
         ]},
        {Catalog.Certificate, [],
         [
           new: fn _state -> %Certificate{certificate_pem: nil} end
         ]}
      ]) do
        config = base_config(acme_provider: Stubs.FailingACMEProvider)

        log =
          capture_log(fn ->
            {:ok, pid} = Manager.start_link(config)
            Process.sleep(100)
            GenServer.stop(pid)
          end)

        assert log =~ "Certificate renewal check failed"
      end
    end
  end

  describe "server_name/1" do
    test "returns an atom prefixed with certificate_manager_" do
      name = Manager.server_name("my_app")
      assert is_atom(name)
      assert name == :certificate_manager_my_app
    end

    test "is unique per app_name" do
      refute Manager.server_name("app_a") == Manager.server_name("app_b")
    end
  end
end
