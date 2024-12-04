defmodule Deployex.Tracer do
  @moduledoc """
  This module provides Tracing context
  """

  require Logger

  alias Deployex.Rpc
  alias Deployex.Tracer.Server, as: TracerServer

  @default_session_timeout_ms 30_000
  @default_max_msg 5

  @type t :: %__MODULE__{
          status: :idle | :running,
          session_id: binary() | nil,
          max_messages: non_neg_integer(),
          session_timeout_ms: non_neg_integer(),
          functions_by_node: map(),
          request_pid: pid() | nil
        }

  defstruct status: :idle,
            session_id: nil,
            max_messages: @default_max_msg,
            session_timeout_ms: @default_session_timeout_ms,
            functions_by_node: %{},
            request_pid: nil

  ### ==========================================================================
  ### Public APIs
  ### ==========================================================================

  @doc """
  This function retrieves all modules within the passed node
  """
  @spec get_modules(node :: atom()) :: list()
  def get_modules(node \\ Node.self()) do
    Rpc.call(node, :code, :all_loaded, [], :infinity)
    |> Enum.map(fn
      {module, _} ->
        module

      # coveralls-ignore-start
      module ->
        module

        # coveralls-ignore-stop
    end)
  end

  @doc """
  This function retrieves all functions within the passed node and module
  """
  @spec get_module_functions_info(node :: atom(), module :: atom()) :: %{
          functions: map(),
          module: atom(),
          node: atom()
        }
  def get_module_functions_info(node \\ Node.self(), module) do
    functions = Rpc.call(node, module, :module_info, [:functions], :infinity)
    externals = Rpc.call(node, module, :module_info, [:exports], :infinity)

    all_functions =
      (functions ++ externals)
      |> Enum.reduce(%{}, fn {name, arity}, acc ->
        full_name = "#{name}/#{arity}"

        if :erl_internal.guard_bif(name, arity) == false and
             regular_functions?(full_name) == false do
          Map.put(acc, full_name, %{name: name, arity: arity})
        else
          acc
        end
      end)

    %{node: node, module: module, functions: all_functions}
  end

  @doc """
  This function retrieves all match specs available
  """
  @spec get_default_functions_matchspecs :: map()
  def get_default_functions_matchspecs do
    %{
      return_trace: %{
        pattern: [{:_, [], [{:return_trace}]}],
        name: "Return Trace",
        fun: "fun(_) -> return_trace() end"
      },
      exception_trace: %{
        pattern: [{:_, [], [{:exception_trace}]}],
        name: "Exception Trace",
        fun: "fun(_) -> exception_trace() end"
      },
      caller: %{
        pattern: [{:_, [], [{:message, {:caller}}]}],
        name: "Message Caller",
        fun: "fun(_) -> message(caller()) end"
      },
      process_dump: %{
        pattern: [{:_, [], [{:message, {:process_dump}}]}],
        name: "Message Dump",
        fun: "fun(_) -> message(process_dump()) end"
      }
    }
  end

  @doc """
  This function starts the trace for the passed module/functions
  """
  @spec start_trace(functions :: list(), attrs :: map()) ::
          {:ok, t()} | {:error, :already_started}
  def start_trace(functions, attrs \\ %{}) do
    TracerServer.start_trace(functions, attrs)
  end

  @doc """
  This function stops the trace for the passed session ID
  """
  @spec stop_trace(binary()) :: :ok
  def stop_trace(session_id) do
    TracerServer.stop_trace(session_id)
  end

  @doc """
  This function returns the current trace server state
  """
  @spec state :: map()
  def state do
    TracerServer.state()
  end

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================
  # coveralls-ignore-start
  defp regular_functions?(function) do
    String.contains?(function, "-anonymous-") or
      String.contains?(function, "-fun-") or
      String.contains?(function, "-inlined-") or
      String.contains?(function, "-lists^") or
      String.contains?(function, "-lc") or
      String.contains?(function, "-lbc")
  end

  # coveralls-ignore-stop
end
