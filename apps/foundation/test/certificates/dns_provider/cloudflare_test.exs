defmodule Foundation.Certificates.DNSProvider.CloudflareTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog
  import Mock

  alias Foundation.Certificates.DNSProvider.Cloudflare

  @name "_acme-challenge.example.com."
  @record_name "_acme-challenge.example.com"
  @txt_value "some-acme-challenge-token"
  @options [api_token: "test-api-token", zone: "test-zone-id", ttl: 60]
  @record_id "existing-record-id"

  @search_url "https://api.cloudflare.com/client/v4/zones/test-zone-id/dns_records?match=all&name=#{URI.encode(@record_name)}&type=TXT"

  describe "upsert_txt_record/3 when record does not exist" do
    @tag :capture_log
    test "creates a new record and returns :ok" do
      with_mocks([
        {Req, [],
         [
           get: fn @search_url, _opts ->
             {:ok, %{status: 200, body: Jason.encode!(%{"result" => []})}}
           end,
           post: fn _url, _opts -> {:ok, %{status: 201}} end
         ]}
      ]) do
        assert :ok = Cloudflare.upsert_txt_record(@name, @txt_value, @options)
      end
    end

    test "logs success when record is created" do
      with_mocks([
        {Req, [],
         [
           get: fn @search_url, _opts ->
             {:ok, %{status: 200, body: Jason.encode!(%{"result" => []})}}
           end,
           post: fn _url, _opts -> {:ok, %{status: 201}} end
         ]}
      ]) do
        log =
          capture_log(fn ->
            Cloudflare.upsert_txt_record(@name, @txt_value, @options)
          end)

        assert log =~ "Successfully created Cloudflare TXT record"
        assert log =~ @txt_value
        assert log =~ @record_name
      end
    end

    @tag :capture_log
    test "POSTs to the correct URL with correct body" do
      with_mocks([
        {Req, [],
         [
           get: fn @search_url, _opts ->
             {:ok, %{status: 200, body: Jason.encode!(%{"result" => []})}}
           end,
           post: fn url, opts ->
             assert url == "https://api.cloudflare.com/client/v4/zones/test-zone-id/dns_records"
             assert opts[:json][:type] == "TXT"
             assert opts[:json][:name] == @record_name
             assert opts[:json][:content] == @txt_value
             assert opts[:json][:ttl] == 60
             {:ok, %{status: 201}}
           end
         ]}
      ]) do
        assert :ok = Cloudflare.upsert_txt_record(@name, @txt_value, @options)
      end
    end

    @tag :capture_log
    test "returns {:error, {:cloudflare_error, reason}} when POST fails" do
      reason = %Req.TransportError{reason: :econnrefused}

      with_mocks([
        {Req, [],
         [
           get: fn @search_url, _opts ->
             {:ok, %{status: 200, body: Jason.encode!(%{"result" => []})}}
           end,
           post: fn _url, _opts -> {:error, reason} end
         ]}
      ]) do
        assert {:error, {:cloudflare_error, ^reason}} =
                 Cloudflare.upsert_txt_record(@name, @txt_value, @options)
      end
    end

    @tag :capture_log
    test "logs error when POST fails" do
      with_mocks([
        {Req, [],
         [
           get: fn @search_url, _opts ->
             {:ok, %{status: 200, body: Jason.encode!(%{"result" => []})}}
           end,
           post: fn _url, _opts -> {:error, %Req.TransportError{reason: :econnrefused}} end
         ]}
      ]) do
        log =
          capture_log(fn ->
            Cloudflare.upsert_txt_record(@name, @txt_value, @options)
          end)

        assert log =~ "Failed to create Cloudflare TXT record"
        assert log =~ @record_name
      end
    end
  end

  describe "upsert_txt_record/3 when record already exists" do
    @tag :capture_log
    test "updates the existing record and returns :ok" do
      with_mocks([
        {Req, [],
         [
           get: fn @search_url, _opts ->
             {:ok,
              %{
                status: 200,
                body: Jason.encode!(%{"result" => [%{"id" => @record_id}]})
              }}
           end,
           put: fn _url, _opts -> {:ok, %{status: 200}} end
         ]}
      ]) do
        assert :ok = Cloudflare.upsert_txt_record(@name, @txt_value, @options)
      end
    end

    test "logs success when record is updated" do
      with_mocks([
        {Req, [],
         [
           get: fn @search_url, _opts ->
             {:ok,
              %{
                status: 200,
                body: Jason.encode!(%{"result" => [%{"id" => @record_id}]})
              }}
           end,
           put: fn _url, _opts -> {:ok, %{status: 200}} end
         ]}
      ]) do
        log =
          capture_log(fn ->
            Cloudflare.upsert_txt_record(@name, @txt_value, @options)
          end)

        assert log =~ "Successfully updated Cloudflare TXT record"
        assert log =~ @record_name
      end
    end

    @tag :capture_log
    test "PUTs to the correct URL with the existing record id" do
      with_mocks([
        {Req, [],
         [
           get: fn @search_url, _opts ->
             {:ok,
              %{
                status: 200,
                body: Jason.encode!(%{"result" => [%{"id" => @record_id}]})
              }}
           end,
           put: fn url, opts ->
             assert url ==
                      "https://api.cloudflare.com/client/v4/zones/test-zone-id/dns_records/#{@record_id}"

             assert opts[:json][:type] == "TXT"
             assert opts[:json][:name] == @record_name
             assert opts[:json][:content] == @txt_value
             assert opts[:json][:ttl] == 60
             {:ok, %{status: 200}}
           end
         ]}
      ]) do
        assert :ok = Cloudflare.upsert_txt_record(@name, @txt_value, @options)
      end
    end

    @tag :capture_log
    test "returns {:error, {:cloudflare_error, reason}} when PUT fails" do
      reason = %Req.TransportError{reason: :econnrefused}

      with_mocks([
        {Req, [],
         [
           get: fn @search_url, _opts ->
             {:ok,
              %{
                status: 200,
                body: Jason.encode!(%{"result" => [%{"id" => @record_id}]})
              }}
           end,
           put: fn _url, _opts -> {:error, reason} end
         ]}
      ]) do
        assert {:error, {:cloudflare_error, ^reason}} =
                 Cloudflare.upsert_txt_record(@name, @txt_value, @options)
      end
    end

    test "logs error when PUT fails" do
      with_mocks([
        {Req, [],
         [
           get: fn @search_url, _opts ->
             {:ok,
              %{
                status: 200,
                body: Jason.encode!(%{"result" => [%{"id" => @record_id}]})
              }}
           end,
           put: fn _url, _opts -> {:error, %Req.TransportError{reason: :econnrefused}} end
         ]}
      ]) do
        log =
          capture_log(fn ->
            Cloudflare.upsert_txt_record(@name, @txt_value, @options)
          end)

        assert log =~ "Failed to update Cloudflare TXT record"
        assert log =~ @record_name
      end
    end
  end

  describe "upsert_txt_record/3 when search request fails" do
    @tag :capture_log
    test "returns {:error, {:cloudflare_error, reason}}" do
      reason = %Req.TransportError{reason: :econnrefused}

      with_mock Req, get: fn @search_url, _opts -> {:error, reason} end do
        assert {:error, {:cloudflare_error, ^reason}} =
                 Cloudflare.upsert_txt_record(@name, @txt_value, @options)
      end
    end

    test "logs error when search fails" do
      with_mock Req,
        get: fn @search_url, _opts ->
          {:error, %Req.TransportError{reason: :econnrefused}}
        end do
        log =
          capture_log(fn ->
            Cloudflare.upsert_txt_record(@name, @txt_value, @options)
          end)

        assert log =~ "Failed to search Cloudflare TXT records"
        assert log =~ @name
      end
    end
  end

  describe "upsert_txt_record/3 trailing dot handling" do
    @tag :capture_log
    test "strips trailing dot from name before sending to Cloudflare" do
      with_mocks([
        {Req, [],
         [
           get: fn @search_url, _opts ->
             {:ok, %{status: 200, body: Jason.encode!(%{"result" => []})}}
           end,
           post: fn _url, opts ->
             assert opts[:json][:name] == @record_name
             {:ok, %{status: 201}}
           end
         ]}
      ]) do
        assert :ok = Cloudflare.upsert_txt_record(@name, @txt_value, @options)
      end
    end
  end
end
