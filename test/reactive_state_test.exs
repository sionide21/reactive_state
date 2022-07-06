defmodule ReactiveStateTest do
  use ExUnit.Case, async: true
  doctest ReactiveState

  describe "define inputs" do
    defmodule DefineInputsTest do
      use ReactiveState

      input :x
      input :y, default: 7
    end

    test "adds to a struct" do
      assert %{x: _, y: _} = %DefineInputsTest{}
    end

    test "can define defaults" do
      struct = %DefineInputsTest{}
      assert struct.x == nil
      assert struct.y == 7
    end
  end

  describe "define computed" do
    defmodule DefineComputedTest do
      use ReactiveState

      input :x
      input :y

      defcomputed sum(x, y) do
        x + y
      end

      defcomputedp internal(x) do
        x + 4
      end
    end

    test "computed fields are part of the struct" do
      struct = %DefineComputedTest{}
      assert %{sum: _} = struct
    end

    test "private computed fields are not part of struct" do
      struct = %DefineComputedTest{}
      refute Map.has_key?(struct, :internal)
    end

    test "detects cycles at compile time" do
      code =
        quote do
          defmodule ComputedLoopTest do
            use ReactiveState
            input :a

            defcomputed b(a, d), do: a + d
            defcomputed c(b), do: b
            defcomputed d(c), do: c
          end
        end

      assert_raise CompileError, fn ->
        Code.compile_quoted(code)
      end
    end
  end

  describe "assign/2" do
    defmodule AssignTest do
      use ReactiveState

      input :page_number, default: 1
      input :page_size, default: 3
      input :all, default: []
      input :pretty_mode, default: :raw

      defcomputed items(all, page_number, page_size) do
        send(self(), :items_computed)

        all
        |> Enum.drop((page_number - 1) * page_size)
        |> Enum.take(page_size)
      end

      defcomputedp count(items) do
        Enum.count(items)
      end

      defcomputed sum(items) do
        Enum.sum(items)
      end

      defcomputed average(count, sum) do
        sum / count
      end

      defcomputed pretty_count(count, pretty_mode) do
        case pretty_mode do
          :raw ->
            count

          :pretty ->
            "#{count} items"
        end
      end
    end

    test "sets the correct values" do
      struct = %AssignTest{}

      {struct, _} = ReactiveState.assign(struct, all: [1, 2, 3, 4, 5])
      assert %{sum: 6, average: 2.0, items: [1, 2, 3]} = struct

      {struct, _} = ReactiveState.assign(struct, page_number: 2)
      assert %{sum: 9, average: 4.5, items: [4, 5]} = struct
    end

    test "recalculates private computed values when needed" do
      struct = %AssignTest{}

      {struct, _} = ReactiveState.assign(struct, all: [4, 5])

      {struct, _} = ReactiveState.assign(struct, pretty_mode: :pretty)
      assert %{pretty_count: "2 items"} = struct
    end

    test "doesn't include private computed fields" do
      struct = %AssignTest{}

      {struct, _} = ReactiveState.assign(struct, all: [4, 5])
      refute Map.has_key?(struct, :count)
    end

    test "Only recalculates a field once" do
      %AssignTest{}
      |> ReactiveState.assign(
        page_number: 4,
        page_size: 1,
        all: [1, 2, 3, 4],
        pretty_mode: :pretty
      )

      assert_received :items_computed
      refute_receive :items_computed
    end

    test "Doesn't recalculate un-affected fields" do
      struct = %AssignTest{}

      {struct, _} = ReactiveState.assign(struct, all: [4, 5])
      assert_received :items_computed

      ReactiveState.assign(struct, pretty_mode: :pretty)

      refute_receive :items_computed
    end

    test "Doesn't accept writes to computed fields" do
      assert_raise KeyError, fn ->
        %AssignTest{}
        |> ReactiveState.assign(average: 93)
      end
    end

    test "reports changes" do
      struct = %AssignTest{}

      {_, changes} = ReactiveState.assign(struct, all: [1])
      assert [all: [1], average: 1.0, items: [1], pretty_count: 1, sum: 1] = Enum.sort(changes)
    end

    test "excludes private changes" do
      struct = %AssignTest{}

      {_, changes} = ReactiveState.assign(struct, all: [1])
      refute Keyword.has_key?(changes, :count)
    end
  end
end
