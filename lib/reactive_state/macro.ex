defmodule ReactiveState.Macro do
  defmacro __using__(_opts) do
    quote do
      import unquote(__MODULE__), only: [input: 1, input: 2, defcomputed: 2, defcomputedp: 2]
      @before_compile unquote(__MODULE__)
      Module.register_attribute(__MODULE__, unquote(__MODULE__).Nodes, accumulate: true)
    end
  end

  defmacro input(name, opts \\ []) do
    quote do
      default = Keyword.get(unquote(opts), :default, nil)
      input = ReactiveState.Node.input(unquote(name), default)
      Module.put_attribute(__MODULE__, unquote(__MODULE__).Nodes, input)
    end
  end

  defmacro defcomputed({name, _, args}, do: expr) do
    do_defcomputed(name, args, expr, :public)
  end

  defmacro defcomputedp({name, _, args}, do: expr) do
    do_defcomputed(name, args, expr, :private)
  end

  def do_defcomputed(name, args, expr, visibility) do
    expr = Macro.escape(expr)
    args = Macro.escape(args)

    quote do
      node =
        ReactiveState.Node.computed(unquote(name), unquote(args), unquote(expr),
          visibility: unquote(visibility)
        )

      Module.put_attribute(__MODULE__, unquote(__MODULE__).Nodes, node)
    end
  end

  def define_assign_impl(nodes) do
    with {:ok, evaluator} <- ReactiveState.Evaluator.new(nodes) do
      evaluator = Macro.escape(evaluator)

      ast =
        quote do
          def assign(me, assigns) do
            unquote(evaluator)
            |> ReactiveState.Evaluator.assign(__MODULE__, me, assigns)
          end
        end

      {:ok, ast}
    end
  end

  defmacro __before_compile__(env) do
    rs_module = Module.concat(env.module, ReactiveState)

    quote location: :keep do
      nodes = Module.get_attribute(__MODULE__, unquote(__MODULE__).Nodes, [])

      struct =
        nodes
        |> Enum.filter(&ReactiveState.Node.public?/1)
        |> Enum.map(fn node -> {node.name, node.default} end)
        |> defstruct()

      definitions =
        nodes
        |> Enum.filter(&ReactiveState.Node.computed?/1)
        |> Enum.map(&ReactiveState.Node.definition/1)

      with {:ok, assign} <- unquote(__MODULE__).define_assign_impl(nodes) do
        Module.create(unquote(rs_module), definitions ++ [assign], Macro.Env.location(__ENV__))
      else
        {:error, {:cycle, cycle}} ->
          raise CompileError, description: "Circular dependency in #{inspect(__MODULE__)}"
      end

      defimpl ReactiveState.Assign do
        def assign(me, assigns) do
          unquote(rs_module).assign(me, assigns)
        end
      end
    end
  end
end
