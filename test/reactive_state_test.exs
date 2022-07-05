defmodule ReactiveStateTest do
  use ExUnit.Case
  doctest ReactiveState

  test "greets the world" do
    assert ReactiveState.hello() == :world
  end
end
