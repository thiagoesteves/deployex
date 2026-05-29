defmodule Foundation.CertificateTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  import Mock

  alias Foundation.Certificate
  alias Foundation.Certificates.Manager.Supervisor

  # ---------------------------------------------------------------------------
  # init/1
  # ---------------------------------------------------------------------------

  describe "init/1" do
    @tag :capture_log
    test "logs initialization message" do
      log =
        capture_log(fn ->
          {:ok, pid} = GenServer.start_link(Certificate, [])
          # Give the continue a moment to fire before we stop.
          Process.sleep(50)
          GenServer.stop(pid)
        end)

      assert log =~ "Initializing Certificate Server"
    end

    @tag :capture_log
    test "returns initial state as empty map" do
      # We inspect via :sys.get_state; the continue callback runs first but
      # does not modify the state, so it stays %{}.
      {:ok, pid} = GenServer.start_link(Certificate, [])
      Process.sleep(50)
      assert :sys.get_state(pid) == %{}
      GenServer.stop(pid)
    end
  end

  # ---------------------------------------------------------------------------
  # handle_continue :start_certificate_manager (test env)
  # ---------------------------------------------------------------------------

  describe "handle_continue :start_certificate_manager (test environment)" do
    @tag :capture_log
    test "does not call Supervisor.start_certificate_manager in test env" do
      # In test mode Foundation.Certificate uses the no-op initialize_certificate_manager/0,
      # so the supervisor must never be contacted.
      with_mock Supervisor, start_certificate_manager: fn _name, _cert -> {:ok, self()} end do
        {:ok, pid} = GenServer.start_link(Certificate, [])
        Process.sleep(50)
        refute called(Supervisor.start_certificate_manager(:_, :_))
        GenServer.stop(pid)
      end
    end
  end

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
end
