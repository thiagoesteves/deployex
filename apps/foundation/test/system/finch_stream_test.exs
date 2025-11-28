defmodule Foundation.System.FinchStreamTest do
  use ExUnit.Case, async: false

  import Mock

  alias Foundation.System.FinchStream

  @test_url "https://example.com/file.zip"
  @test_file_path "/tmp/test_file.zip"
  @test_headers [{"authorization", "Bearer token"}]

  setup do
    # Clean up any existing test file
    File.rm(@test_file_path)
    on_exit(fn -> File.rm(@test_file_path) end)

    :ok
  end

  describe "download/4 - successful downloads" do
    test "successfully downloads a file with 200 status" do
      file_content = "test file content"

      with_mock Finch,
        build: fn :get, _url, _headers -> :mocked_request end,
        stream_while: fn _request, _finch, acc, fun ->
          {:cont, acc} = fun.({:status, 200}, acc)
          {:cont, acc} = fun.({:headers, [{"content-length", "#{byte_size(file_content)}"}]}, acc)
          {:cont, acc} = fun.({:data, file_content}, acc)
          {:ok, acc}
        end do
        assert :ok = FinchStream.download(@test_url, @test_file_path, @test_headers)
      end
    end

    test "successfully downloads a file without content-length header" do
      file_content = "test content without size"

      with_mock Finch,
        build: fn :get, _url, _headers -> :mocked_request end,
        stream_while: fn _request, _finch, acc, fun ->
          {:cont, acc} = fun.({:status, 200}, acc)
          {:cont, acc} = fun.({:headers, []}, acc)
          {:cont, acc} = fun.({:data, file_content}, acc)
          {:ok, acc}
        end do
        assert :ok = FinchStream.download(@test_url, @test_file_path, @test_headers)

        assert File.exists?(@test_file_path)
        assert File.read!(@test_file_path) == file_content
      end
    end

    test "handles multiple data chunks" do
      chunk1 = "first chunk"
      chunk2 = "second chunk"
      chunk3 = "third chunk"
      total_size = byte_size(chunk1) + byte_size(chunk2) + byte_size(chunk3)

      with_mock Finch,
        build: fn :get, _url, _headers -> :mocked_request end,
        stream_while: fn _request, _finch, acc, fun ->
          {:cont, acc} = fun.({:status, 200}, acc)
          {:cont, acc} = fun.({:headers, [{"content-length", "#{total_size}"}]}, acc)
          {:cont, acc} = fun.({:data, chunk1}, acc)
          {:cont, acc} = fun.({:data, chunk2}, acc)
          {:cont, acc} = fun.({:data, chunk3}, acc)
          {:ok, acc}
        end do
        assert :ok = FinchStream.download(@test_url, @test_file_path, @test_headers)

        assert File.read!(@test_file_path) == chunk1 <> chunk2 <> chunk3
      end
    end
  end

  describe "download/4 - redirects" do
    test "follows 302 redirect successfully" do
      redirect_location = "https://example.com/redirected/file.zip"
      file_content = "redirected content"

      with_mock Finch,
        build: fn :get, _url, _headers -> :mocked_request end,
        stream_while: fn _request, _finch, acc, fun ->
          case acc.url do
            @test_url ->
              {:cont, acc} = fun.({:status, 302}, acc)
              {:cont, acc} = fun.({:headers, [{"location", redirect_location}]}, acc)
              {:ok, acc}

            ^redirect_location ->
              {:cont, acc} = fun.({:status, 200}, acc)

              {:cont, acc} =
                fun.({:headers, [{"content-length", "#{byte_size(file_content)}"}]}, acc)

              {:cont, acc} = fun.({:data, file_content}, acc)
              {:ok, acc}
          end
        end do
        assert :ok = FinchStream.download(@test_url, @test_file_path, @test_headers)

        assert File.read!(@test_file_path) == file_content
      end
    end

    test "follows 301 redirect successfully" do
      redirect_location = "https://example.com/permanent/file.zip"
      file_content = "permanent redirect content"

      with_mock Finch,
        build: fn :get, _url, _headers -> :mocked_request end,
        stream_while: fn _request, _finch, acc, fun ->
          case acc.url do
            @test_url ->
              {:cont, acc} = fun.({:status, 301}, acc)
              {:cont, acc} = fun.({:headers, [{"location", redirect_location}]}, acc)
              {:ok, acc}

            ^redirect_location ->
              {:cont, acc} = fun.({:status, 200}, acc)

              {:cont, acc} =
                fun.({:headers, [{"content-length", "#{byte_size(file_content)}"}]}, acc)

              {:cont, acc} = fun.({:data, file_content}, acc)
              {:ok, acc}
          end
        end do
        assert :ok = FinchStream.download(@test_url, @test_file_path, @test_headers)

        assert File.read!(@test_file_path) == file_content
      end
    end

    test "handles redirect but fails on the redirected download" do
      redirect_location = "https://example.com/permanent/file.zip"

      with_mock Finch,
        build: fn :get, _url, _headers -> :mocked_request end,
        stream_while: fn _request, _finch, acc, fun ->
          case acc.url do
            @test_url ->
              {:cont, acc} = fun.({:status, 301}, acc)
              {:halt, acc} = fun.({:headers, [{"location", redirect_location}]}, acc)
              {:error, acc.error, acc}

            ^redirect_location ->
              # Simulate an error during the redirected download
              {:error, :connection_timeout, acc}
          end
        end do
        assert {:error, error_msg} =
                 FinchStream.download(@test_url, @test_file_path, @test_headers)

        assert error_msg =~ "Error downloading"
        assert error_msg =~ "connection_timeout"
      end
    end

    test "handles redirect without location header" do
      with_mock Finch,
        build: fn :get, _url, _headers -> :mocked_request end,
        stream_while: fn _request, _finch, acc, fun ->
          {:cont, acc} = fun.({:status, 302}, acc)
          {:halt, acc} = fun.({:headers, []}, acc)
          {:error, acc.error, acc}
        end do
        assert {:error, "Error during redirection"} =
                 FinchStream.download(@test_url, @test_file_path, @test_headers)
      end
    end
  end

  describe "download/4 - error handling" do
    test "returns error for non-200/redirect status codes" do
      with_mock Finch,
        build: fn :get, _url, _headers -> :mocked_request end,
        stream_while: fn _request, _finch, acc, fun ->
          {:cont, acc} = fun.({:status, 404}, acc)
          {:halt, acc} = fun.({:headers, []}, acc)
          {:error, acc.error, acc}
        end do
        assert {:error, "Bad handler status"} =
                 FinchStream.download(@test_url, @test_file_path, @test_headers)
      end
    end

    test "handles Finch stream error" do
      with_mock Finch,
        build: fn :get, _url, _headers -> :mocked_request end,
        stream_while: fn _request, _finch, acc, _fun ->
          {:error, :timeout, acc}
        end do
        assert {:error, :timeout} =
                 FinchStream.download(@test_url, @test_file_path, @test_headers)
      end
    end

    test "handles error set in accumulator during streaming" do
      test_pid = self()

      notify_callback = fn file_path, status ->
        send(test_pid, {:notify, file_path, status})
      end

      with_mock Finch,
        build: fn :get, _url, _headers -> :mocked_request end,
        stream_while: fn _request, _finch, acc, fun ->
          {:cont, acc} = fun.({:status, 200}, acc)
          {:cont, acc} = fun.({:headers, [{"content-length", "100"}]}, acc)
          # Simulate an error being set in the accumulator (e.g., from keep_downloading_callback)
          {:ok, %{acc | error: "Download was cancelled"}}
        end do
        assert {:error, "Download was cancelled"} =
                 FinchStream.download(@test_url, @test_file_path, @test_headers,
                   notify_callback: notify_callback
                 )

        assert_received {:notify, @test_file_path, {:error, "Download was cancelled"}}
      end
    end
  end

  describe "download/4 - callbacks" do
    test "calls notify_callback during download progress" do
      test_pid = self()
      file_content = "test content for progress"

      notify_callback = fn file_path, status ->
        send(test_pid, {:notify, file_path, status})
      end

      with_mock Finch,
        build: fn :get, _url, _headers -> :mocked_request end,
        stream_while: fn _request, _finch, acc, fun ->
          {:cont, acc} = fun.({:status, 200}, acc)
          {:cont, acc} = fun.({:headers, [{"content-length", "#{byte_size(file_content)}"}]}, acc)
          {:cont, acc} = fun.({:data, file_content}, acc)
          {:ok, acc}
        end do
        assert :ok =
                 FinchStream.download(@test_url, @test_file_path, @test_headers,
                   notify_callback: notify_callback
                 )

        assert_received {:notify, @test_file_path, {:downloading, 100.0}}
        assert_received {:notify, @test_file_path, :ok}
      end
    end

    test "calls notify_callback on error" do
      test_pid = self()

      notify_callback = fn file_path, status ->
        send(test_pid, {:notify, file_path, status})
      end

      with_mock Finch,
        build: fn :get, _url, _headers -> :mocked_request end,
        stream_while: fn _request, _finch, acc, _fun ->
          {:error, :connection_failed, acc}
        end do
        assert {:error, :connection_failed} =
                 FinchStream.download(@test_url, @test_file_path, @test_headers,
                   notify_callback: notify_callback
                 )

        assert_received {:notify, @test_file_path, {:error, :connection_failed}}
      end
    end

    test "respects keep_downloading_callback returning false" do
      test_pid = self()

      keep_downloading_callback = fn ->
        send(test_pid, :keep_downloading_check)
        false
      end

      with_mock Finch,
        build: fn :get, _url, _headers -> :mocked_request end,
        stream_while: fn _request, _finch, acc, fun ->
          {:cont, acc} = fun.({:status, 200}, acc)
          {:cont, acc} = fun.({:headers, [{"content-length", "100"}]}, acc)
          {:halt, acc} = fun.({:data, "test data"}, acc)
          {:error, acc.error, acc}
        end do
        assert {:error, "Download for file " <> _} =
                 FinchStream.download(@test_url, @test_file_path, @test_headers,
                   keep_downloading_callback: keep_downloading_callback
                 )

        assert_received :keep_downloading_check
      end
    end

    test "continues downloading when keep_downloading_callback returns true" do
      test_pid = self()

      keep_downloading_callback = fn ->
        send(test_pid, :keep_downloading_check)
        true
      end

      file_content = "download continues"

      with_mock Finch,
        build: fn :get, _url, _headers -> :mocked_request end,
        stream_while: fn _request, _finch, acc, fun ->
          {:cont, acc} = fun.({:status, 200}, acc)
          {:cont, acc} = fun.({:headers, [{"content-length", "#{byte_size(file_content)}"}]}, acc)
          {:cont, acc} = fun.({:data, file_content}, acc)
          {:ok, acc}
        end do
        assert :ok =
                 FinchStream.download(@test_url, @test_file_path, @test_headers,
                   keep_downloading_callback: keep_downloading_callback
                 )

        assert_received :keep_downloading_check
        assert File.read!(@test_file_path) == file_content
      end
    end

    test "calculates progress correctly with multiple chunks" do
      test_pid = self()
      chunk_size = 25

      notify_callback = fn file_path, status ->
        send(test_pid, {:notify, file_path, status})
      end

      with_mock Finch,
        build: fn :get, _url, _headers -> :mocked_request end,
        stream_while: fn _request, _finch, acc, fun ->
          {:cont, acc} = fun.({:status, 200}, acc)
          {:cont, acc} = fun.({:headers, [{"content-length", "100"}]}, acc)
          {:cont, acc} = fun.({:data, String.duplicate("a", chunk_size)}, acc)
          {:cont, acc} = fun.({:data, String.duplicate("b", chunk_size)}, acc)
          {:cont, acc} = fun.({:data, String.duplicate("c", chunk_size)}, acc)
          {:cont, acc} = fun.({:data, String.duplicate("d", chunk_size)}, acc)
          {:ok, acc}
        end do
        assert :ok =
                 FinchStream.download(@test_url, @test_file_path, @test_headers,
                   notify_callback: notify_callback
                 )

        assert_received {:notify, @test_file_path, {:downloading, 25.0}}
        assert_received {:notify, @test_file_path, {:downloading, 50.0}}
        assert_received {:notify, @test_file_path, {:downloading, 75.0}}
        assert_received {:notify, @test_file_path, {:downloading, 100.0}}
        assert_received {:notify, @test_file_path, :ok}
      end
    end
  end

  describe "download/4 - custom file_pid" do
    test "uses provided file_pid instead of opening file" do
      {:ok, custom_pid} = File.open(@test_file_path, [:write, :binary])
      file_content = "content with custom pid"

      with_mock Finch,
        build: fn :get, _url, _headers -> :mocked_request end,
        stream_while: fn _request, _finch, acc, fun ->
          {:cont, acc} = fun.({:status, 200}, acc)
          {:cont, acc} = fun.({:headers, [{"content-length", "#{byte_size(file_content)}"}]}, acc)
          {:cont, acc} = fun.({:data, file_content}, acc)
          {:ok, acc}
        end do
        assert :ok =
                 FinchStream.download(@test_url, @test_file_path, @test_headers,
                   file_pid: custom_pid
                 )

        # File should be closed by the function
        assert File.read!(@test_file_path) == file_content
      end
    end
  end
end
