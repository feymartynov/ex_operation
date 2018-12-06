defmodule ExOperation.BeforeTransactionTest do
  use ExOperation.TestCase, async: true

  defmodule BeforeTransactionOperation do
    use ExOperation.Operation

    def call(operation) do
      operation
      |> before_transaction(fn _ -> {:ok, %{foo: 1}} end)
      |> before_transaction(&{:ok, %{foo: &1.foo + 1}})
      |> step(:bar, &{:ok, &1.foo + 1})
    end
  end

  test "call before transaction hooks" do
    assert {:ok, txn} = BeforeTransactionOperation |> ExOperation.run(%{}, %{})
    assert txn.foo == 2
    assert txn.bar == 3
  end

  defmodule BeforeTransactionWithBadReturnOperation do
    use ExOperation.Operation

    def call(operation) do
      operation
      |> before_transaction(fn _ -> {:ok, :wrong} end)
    end
  end

  @error_regex ~r/Error in `ExOperation.BeforeTransactionTest.BeforeTransactionWithBadReturnOperation` in callback:\n\(Elixir.ExOperation.AssertionError\) Expected `{:ok, %{}}` or {:error, reason}`. Got `{:ok, :wrong}`./

  test "raise on bad return from before transaction callback" do
    assert_raise ExOperation.CallbackError, @error_regex, fn ->
      BeforeTransactionWithBadReturnOperation |> ExOperation.run(%{}, %{})
    end
  end

  defmodule RaisingBeforeTransactionOperation do
    use ExOperation.Operation

    def call(operation) do
      operation
      |> before_transaction(fn _ -> raise "It failed" end)
    end
  end

  @error_regex ~r/Error in `ExOperation.BeforeTransactionTest.RaisingBeforeTransactionOperation` in callback:\n\(Elixir.RuntimeError\) It failed/

  test "raise inside before transaction callback" do
    assert_raise ExOperation.CallbackError, @error_regex, fn ->
      RaisingBeforeTransactionOperation |> ExOperation.run(%{}, %{})
    end
  end

  defmodule BeforeTransactionInSuboperationSuboperation do
    use ExOperation.Operation

    def call(operation) do
      operation
      |> before_transaction(fn _ -> {:ok, %{foo: :bar}} end)
    end
  end

  defmodule BeforeTransactionInSuboperationOperation do
    use ExOperation.Operation

    def call(operation) do
      operation
      |> suboperation(BeforeTransactionInSuboperationSuboperation, %{}, id: :sub)
    end
  end

  @error_regex ~r/Before transaction callbacks are not allowed in defers or suboperations./

  test "raise on before transaction callback defined in suboperation" do
    assert_raise ExOperation.AssertionError, @error_regex, fn ->
      BeforeTransactionInSuboperationOperation |> ExOperation.run(%{}, %{})
    end
  end

  defmodule BeforeTransactionInDeferOperation do
    use ExOperation.Operation

    def call(operation) do
      operation
      |> defer(fn op, _ ->
        op |> before_transaction(fn _ -> {:ok, %{foo: :bar}} end)
      end)
    end
  end

  @error_regex ~r/Before transaction callbacks are not allowed in defers or suboperations./

  test "raise on before transaction callback defined in defer" do
    assert_raise ExOperation.AssertionError, @error_regex, fn ->
      BeforeTransactionInDeferOperation |> ExOperation.run(%{}, %{})
    end
  end
end
