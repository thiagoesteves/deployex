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
end
