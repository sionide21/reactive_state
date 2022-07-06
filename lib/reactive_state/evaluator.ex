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

    recompute = determine_updates(evaluator, keys)

    updated =
      recompute
      |> Enum.reduce(struct!(struct, assigns), fn fun, struct ->
        apply(module, fun, [struct])
      end)
      |> Map.drop(evaluator.private_fields)

    changes =
      (recompute ++ keys)
      |> Enum.reject(&Enum.member?(evaluator.private_fields, &1))
      |> Enum.map(&{&1, Map.get(updated, &1)})

    {updated, changes}
  end

  def determine_updates(evaluator, keys) do
    affected = determine_affected(evaluator, keys, %{})
    Enum.filter(evaluator.order, &affected[&1])
  end

  def assert_valid_inputs(evaluator, keys, struct) do
    Enum.each(keys, fn key ->
      unless evaluator.valid_inputs[key] do
        raise(KeyError, key: key, term: struct)
      end
    end)
  end

  defp determine_affected(_, [], affected) do
    affected
  end

  defp determine_affected(evaluator, [key | keys], affected) do
    triggers = evaluator.triggers[key] || []
    private = evaluator.private_inputs[key] || []

    affected = Enum.reduce(triggers ++ private, affected, &Map.put(&2, &1, true))
    determine_affected(evaluator, triggers ++ keys, affected)
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
