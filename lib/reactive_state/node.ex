defmodule ReactiveState.Node do
  defstruct [:name, :type, :default, :inputs, :visibility, :expression, :quoted_inputs]

  def input(name, default) do
    %__MODULE__{
      name: name,
      type: :input,
      default: default,
      inputs: [],
      quoted_inputs: [],
      visibility: :public
    }
  end

  def computed(name, quoted_inputs, expression, opts \\ []) do
    visibility = Keyword.get(opts, :visibility, :public)
    inputs = arg_names(quoted_inputs)

    %__MODULE__{
      name: name,
      type: :computed,
      inputs: inputs,
      quoted_inputs: quoted_inputs,
      visibility: visibility,
      expression: expression
    }
  end

  def public?(%{visibility: visibility}), do: visibility == :public

  def computed?(%{type: type}), do: type == :computed

  def definition(node = %{type: :computed}) do
    args = Enum.map(node.quoted_inputs, fn arg = {input, _, _} -> {input, arg} end)

    quote do
      def unquote(node.name)(me = %{unquote_splicing(args)}) do
        result = unquote(node.expression)
        Map.put(me, unquote(node.name), result)
      end
    end
  end

  defp arg_names(args) do
    Enum.map(args, fn {name, _, _} -> name end)
  end
end
