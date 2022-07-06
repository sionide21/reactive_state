defmodule ReactiveState.Evaluator do
  alias ReactiveState.Node

  defstruct [:order, :triggers, :private_inputs, :valid_inputs, :private_fields]

  def new(nodes) do
    with {:ok, order} <- eval_order(nodes),
         triggers = triggers(nodes),
         private_inputs = private_inputs(nodes),
         valid_inputs = valid_inputs(nodes),
         private_fields = private_fields(nodes) do
      {:ok,
       %__MODULE__{
         order: order,
         triggers: triggers,
         private_inputs: private_inputs,
         valid_inputs: valid_inputs,
         private_fields: private_fields
       }}
    end
  end

  def assign(evaluator, module, struct, assigns) do
    keys = Keyword.keys(assigns)
    assert_valid_inputs(evaluator, keys, struct)

    state = %{
      to_check: Map.new(keys, &{&1, true}),
      changes: [],
      struct: struct
    }

    %{changes: changes, struct: updated} =
      evaluator.order
      |> Enum.reduce(state, fn field, state = %{changes: changes, struct: struct} ->
        if state.to_check[field] do
          new_struct = do_update(struct, field, assigns, module)

          if new_struct != struct do
            state = include_related_fields(evaluator, field, state)
            %{state | changes: [field | changes], struct: new_struct}
          else
            state
          end
        else
          state
        end
      end)

    updated =
      updated
      |> Map.drop(evaluator.private_fields)

    changes =
      changes
      |> Enum.reject(&Enum.member?(evaluator.private_fields, &1))
      |> Enum.map(&{&1, Map.get(updated, &1)})

    {updated, changes}
  end

  defp include_related_fields(evaluator, field, state) do
    triggers = related_fields(evaluator.triggers, field)

    private_inputs =
      triggers
      |> Enum.flat_map(&related_fields(evaluator.private_inputs, &1))

    to_check =
      state.to_check
      |> Map.merge(to_set(triggers))
      |> Map.merge(to_set(private_inputs))

    %{state | to_check: to_check}
  end

  defp do_update(struct, field, assigns, module) do
    case Keyword.get(assigns, field) do
      nil ->
        apply(module, field, [struct])

      value ->
        struct!(struct, [{field, value}])
    end
  end

  defp to_set(list) do
    Map.new(list, &{&1, true})
  end

  defp related_fields(category, field) do
    Map.get(category, field, [])
  end

  def assert_valid_inputs(evaluator, keys, struct) do
    Enum.each(keys, fn key ->
      unless evaluator.valid_inputs[key] do
        raise(KeyError, key: key, term: struct)
      end
    end)
  end

  defp private_fields(nodes) do
    nodes
    |> Enum.reject(&Node.public?/1)
    |> Enum.map(& &1.name)
  end

  defp valid_inputs(nodes) do
    nodes
    |> Enum.reject(&Node.computed?/1)
    |> Map.new(&{&1.name, true})
  end

  defp eval_order(nodes) do
    edges =
      nodes
      |> Enum.flat_map(fn node ->
        Enum.map(node.inputs, &{&1, node.name})
      end)

    {inputs, remaining} =
      nodes
      |> Enum.map(fn node ->
        %{
          needed: Enum.count(node.inputs),
          node: node.name
        }
      end)
      |> Enum.split_with(&(&1.needed == 0))

    compute_eval_order(inputs, remaining, edges, [])
  end

  defp compute_eval_order([], _remaining, [], sorted) do
    {:ok, Enum.reverse(sorted)}
  end

  defp compute_eval_order([], _remaining, edges, _sorted) do
    {:error, {:cycle, edges}}
  end

  defp compute_eval_order([attr | inputs], remaining, edges, sorted) do
    {resolved, edges} = Enum.split_with(edges, fn {x, _} -> x == attr.node end)
    resolved = Map.new(resolved, fn {_, node} -> {node, true} end)

    {new_inputs, remaining} =
      remaining
      |> Enum.map(fn attr ->
        if resolved[attr.node] do
          Map.update!(attr, :needed, &(&1 - 1))
        else
          attr
        end
      end)
      |> Enum.split_with(&(&1.needed == 0))

    compute_eval_order(inputs ++ new_inputs, remaining, edges, [attr.node | sorted])
  end

  defp triggers(nodes) do
    Enum.reduce(nodes, %{}, fn node, triggers ->
      Enum.reduce(node.inputs, triggers, fn input, triggers ->
        Map.update(triggers, input, [node.name], &[node.name | &1])
      end)
    end)
  end

  defp private_inputs(nodes) do
    index = Map.new(nodes, &{&1.name, &1})

    Map.new(nodes, fn node ->
      {node.name, Enum.reject(node.inputs, &Node.public?(index[&1]))}
    end)
  end
end
