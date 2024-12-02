defmodule Deployex.TracerFixtures do
  @moduledoc """
  This module will handle the tracer fixture
  """

  def testing_fun(_arg1) do
    :ok
  end

  def testing_adding_fun(arg1, arg2) do
    arg1 + arg2
  end

  def testing_caller_fun(arg1, arg2) do
    testing_adding_fun(arg1, arg2)
  end

  def testing_exception_fun(arg) do
    1 / arg
  end
end
