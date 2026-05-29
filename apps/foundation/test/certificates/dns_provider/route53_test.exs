defmodule Foundation.Certificates.DNSProvider.Route53Test do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  import Mock

  alias Foundation.Certificates.DNSProvider.Route53

  @name "_acme-challenge.example.com."
  @txt_value "some-acme-challenge-token"
  @options %{ttl: 60, zone: "HOSTED_ZONE_ID"}

  describe "upsert_txt_record/3" do
    @tag :capture_log
    test "returns :ok and logs success when ExAws request succeeds" do
      with_mocks([
        {ExAws.Route53, [],
         [
           change_record_sets: fn _zone, _opts -> %ExAws.Operation.Query{} end
         ]},
        {ExAws, [],
         [
           request: fn _op, _opts -> {:ok, %{}} end
         ]}
      ]) do
        log =
          capture_log(fn ->
            assert :ok = Route53.upsert_txt_record(@name, @txt_value, @options)
          end)

        assert log =~ "Successfully created/updated Route53 TXT record"
        assert log =~ @txt_value
        assert log =~ @name
      end
    end

    @tag :capture_log
    test "returns {:error, {:route53_error, reason}} and logs error when ExAws request fails" do
      with_mocks([
        {ExAws.Route53, [],
         [
           change_record_sets: fn _zone, _opts -> %ExAws.Operation.Query{} end
         ]},
        {ExAws, [],
         [
           request: fn _op, _opts -> {:error, {:http_error, 500, "Internal Server Error"}} end
         ]}
      ]) do
        log =
          capture_log(fn ->
            assert {:error, {:route53_error, {:http_error, 500, "Internal Server Error"}}} =
                     Route53.upsert_txt_record(@name, @txt_value, @options)
          end)

        assert log =~ "Failed to create Route53 TXT record"
      end
    end

    @tag :capture_log
    test "wraps the txt_value in double quotes in the DNS record" do
      with_mocks([
        {ExAws.Route53, [],
         [
           change_record_sets: fn _zone, opts ->
             records = opts[:records]
             assert records == ["\"#{@txt_value}\""]
             %ExAws.Operation.Query{}
           end
         ]},
        {ExAws, [],
         [
           request: fn _op, _opts -> {:ok, %{}} end
         ]}
      ]) do
        assert :ok = Route53.upsert_txt_record(@name, @txt_value, @options)
      end
    end

    @tag :capture_log
    test "passes ttl and zone from options to Route53 change_record_sets" do
      with_mocks([
        {ExAws.Route53, [],
         [
           change_record_sets: fn zone, opts ->
             assert zone == "HOSTED_ZONE_ID"
             assert opts[:ttl] == 60
             %ExAws.Operation.Query{}
           end
         ]},
        {ExAws, [],
         [
           request: fn _op, _opts -> {:ok, %{}} end
         ]}
      ]) do
        assert :ok = Route53.upsert_txt_record(@name, @txt_value, @options)
      end
    end

    @tag :capture_log
    test "always targets us-east-1 region when making the AWS request" do
      with_mocks([
        {ExAws.Route53, [],
         [
           change_record_sets: fn _zone, _opts -> %ExAws.Operation.Query{} end
         ]},
        {ExAws, [],
         [
           request: fn _op, region_opts ->
             assert region_opts == %{region: "us-east-1"}
             {:ok, %{}}
           end
         ]}
      ]) do
        assert :ok = Route53.upsert_txt_record(@name, @txt_value, @options)
      end
    end

    @tag :capture_log
    test "uses upsert action in the Route53 change request" do
      with_mocks([
        {ExAws.Route53, [],
         [
           change_record_sets: fn _zone, opts ->
             assert opts[:action] == :upsert
             %ExAws.Operation.Query{}
           end
         ]},
        {ExAws, [],
         [
           request: fn _op, _opts -> {:ok, %{}} end
         ]}
      ]) do
        assert :ok = Route53.upsert_txt_record(@name, @txt_value, @options)
      end
    end

    @tag :capture_log
    test "sets the record type to TXT" do
      with_mocks([
        {ExAws.Route53, [],
         [
           change_record_sets: fn _zone, opts ->
             assert opts[:type] == "TXT"
             %ExAws.Operation.Query{}
           end
         ]},
        {ExAws, [],
         [
           request: fn _op, _opts -> {:ok, %{}} end
         ]}
      ]) do
        assert :ok = Route53.upsert_txt_record(@name, @txt_value, @options)
      end
    end

    @tag :capture_log
    test "returns error tuple preserving the original reason from ExAws" do
      reason = {:service_error, "NoSuchHostedZone", "No hosted zone found"}

      with_mocks([
        {ExAws.Route53, [],
         [
           change_record_sets: fn _zone, _opts -> %ExAws.Operation.Query{} end
         ]},
        {ExAws, [],
         [
           request: fn _op, _opts -> {:error, reason} end
         ]}
      ]) do
        assert {:error, {:route53_error, ^reason}} =
                 Route53.upsert_txt_record(@name, @txt_value, @options)
      end
    end
  end
end
