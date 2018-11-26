defmodule ExOperation.DeferTest do
  use ExOperation.TestCase, async: true

  defmodule DeferOperation do
    use ExOperation.Operation

    def call(operation) do
      operation
      |> step(:some_key, fn _ -> {:ok, :some_value} end)
      |> defer(fn
        op, %{some_key: :some_value} -> op |> step(:result, fn _ -> {:ok, :correct} end)
        op, _ -> op
      end)
    end
  end

  test "defer" do
    assert {:ok, %{result: :correct}} = DeferOperation |> ExOperation.run(%{}, %{})
  end

  defmodule DeferWithBadReturnOperation do
    use ExOperation.Operation

    def call(operation) do
      operation
      |> defer(fn _, _ -> :wrong end)
    end
  end

  @error_regex ~r/Error in `ExOperation.DeferTest.DeferWithBadReturnOperation` in defer callback:\n\(Elixir.ExOperation.AssertionError\) Expected `%ExOperation.Operation{}`. Got `:wrong`./

  test "raise on bad return from defer callback" do
    assert_raise ExOperation.DeferError, @error_regex, fn ->
      DeferWithBadReturnOperation |> ExOperation.run(%{}, %{})
    end
  end

  defmodule RaisingDeferOperation do
    use ExOperation.Operation

    def call(operation) do
      operation
      |> defer(fn _, _ -> raise "It failed" end)
    end
  end

  @error_regex ~r/Error in `ExOperation.DeferTest.RaisingDeferOperation` in defer callback:\n\(Elixir.RuntimeError\) It failed/

  test "raise inside defer callback" do
    assert_raise ExOperation.DeferError, @error_regex, fn ->
      RaisingDeferOperation |> ExOperation.run(%{}, %{})
    end
  end
end
