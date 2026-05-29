defmodule Foundation.Certificates.Manager.SupervisorTest do
  use ExUnit.Case, async: false

  import Mock

  alias Foundation.Certificates.Manager
  alias Foundation.Certificates.Manager.Supervisor

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp domain_certificate(overrides \\ %{}) do
    Map.merge(
      %{
        type: :domains,
        domains: ["example.com", "www.example.com"],
        certificate_check_interval_ms: 86_400_000,
        dns_propagation_timeout_ms: 300_000,
        dns_check_interval_ms: 5_000,
        renew_before_days: 30,
        dns_provider: SomeDNSProvider,
        dns_options: %{zone: "Z123"},
        acme_provider: SomeACMEProvider,
        acme_options: %{email: "ops@example.com"},
        importer: SomeImporter,
        importer_options: %{}
      },
      overrides
    )
  end

  # ---------------------------------------------------------------------------
  # start_certificate_manager/2
  # ---------------------------------------------------------------------------

  describe "start_certificate_manager/2" do
    test "starts a Manager child for a :domains certificate" do
      with_mock DynamicSupervisor, [:passthrough],
        start_child: fn Foundation.Certificates.Manager.Supervisor, _spec -> {:ok, self()} end do
        result = Supervisor.start_certificate_manager("my_app", domain_certificate())
        assert {:ok, _pid} = result
        assert called(DynamicSupervisor.start_child(:_, :_))
      end
    end

    test "passes a child spec with :transient restart strategy" do
      with_mock DynamicSupervisor, [:passthrough],
        start_child: fn _sup, spec ->
          assert spec.restart == :transient
          {:ok, self()}
        end do
        Supervisor.start_certificate_manager("my_app", domain_certificate())
      end
    end

    test "child spec start tuple references Manager.start_link" do
      with_mock DynamicSupervisor, [:passthrough],
        start_child: fn _sup, spec ->
          {mod, fun, _args} = spec.start
          assert mod == Manager
          assert fun == :start_link
          {:ok, self()}
        end do
        Supervisor.start_certificate_manager("my_app", domain_certificate())
      end
    end

    test "builds Manager struct from the certificate fields" do
      with_mock DynamicSupervisor, [:passthrough],
        start_child: fn _sup, spec ->
          {_mod, _fun, [manager]} = spec.start
          assert %Manager{} = manager
          assert manager.app_name == "my_app"
          assert manager.domains == ["example.com", "www.example.com"]
          assert manager.dns_provider == SomeDNSProvider
          assert manager.acme_provider == SomeACMEProvider
          assert manager.importer == SomeImporter
          {:ok, self()}
        end do
        Supervisor.start_certificate_manager("my_app", domain_certificate())
      end
    end

    test "returns :ignore for a non-:domains certificate" do
      non_domain_cert = %{type: :wildcard, domains: ["*.example.com"]}
      assert :ignore = Supervisor.start_certificate_manager("my_app", non_domain_cert)
    end

    test "returns :ignore for a certificate without a type key" do
      assert :ignore = Supervisor.start_certificate_manager("my_app", %{domains: ["example.com"]})
    end
  end

  # ---------------------------------------------------------------------------
  # stop_certificate_manager/1
  # ---------------------------------------------------------------------------

  describe "stop_certificate_manager/1" do
    test "returns {:error, :not_found} when no process is registered for app_name" do
      # Use a name that is definitely not running.
      assert {:error, :not_found} = Supervisor.stop_certificate_manager("definitely_not_running")
    end

    test "terminates the child and returns :ok when the manager is running" do
      pid = self()
      server_name = Manager.server_name("running_app")

      with_mocks([
        {Process, [:passthrough], whereis: fn ^server_name -> pid end},
        {DynamicSupervisor, [:passthrough],
         terminate_child: fn Foundation.Certificates.Manager.Supervisor, ^pid -> :ok end}
      ]) do
        assert :ok = Supervisor.stop_certificate_manager("running_app")
      end
    end

    test "calls DynamicSupervisor.terminate_child with the correct pid" do
      pid = self()
      server_name = Manager.server_name("my_app")

      with_mocks([
        {Process, [:passthrough], whereis: fn ^server_name -> pid end},
        {DynamicSupervisor, [:passthrough],
         terminate_child: fn _sup, child_pid ->
           assert child_pid == pid
           :ok
         end}
      ]) do
        Supervisor.stop_certificate_manager("my_app")
      end
    end
  end
end
