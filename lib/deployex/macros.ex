defmodule Deployex.Macros do
  @moduledoc """
  This file contains common macros
  """

  @doc """
  Compiler macro that will only add the do block code if it is not a test build
  (prod or dev) and will run the else block of code if it is a test build

  Note:  the else block is optional

  ## Example:
  import Deployex.Macros

  if_not_test do
    @msg "I am NOT a test build"
  else
    @msg "I am a test build"
  end

  """
  @spec if_not_test([{:do, any} | {:else, any}, ...]) :: any
  defmacro if_not_test(do: tBlock, else: fBlock) do
    case Mix.env() do
      # If this is a dev block
      :test ->
        if nil != fBlock do
          quote do
            unquote(fBlock)
          end
        end

      # otherwise go with the alternative
      _ ->
        quote do
          unquote(tBlock)
        end
    end
  end

  defmacro if_not_test(do: tBlock) do
    if :test != Mix.env() do
      # If this is a dev block
      quote do
        unquote(tBlock)
      end
    end
  end
end
