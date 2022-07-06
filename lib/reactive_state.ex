defmodule ReactiveState do
  defmacro __using__(_opts) do
    quote do
      use ReactiveState.Macro
    end
  end

  defdelegate assign(struct, attrs), to: __MODULE__.Assign
end
