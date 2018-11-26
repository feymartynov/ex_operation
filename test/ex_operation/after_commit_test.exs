defmodule ExOperation.AfterCommitTest do
  use ExOperation.TestCase, async: true

  defmodule AfterCommitOperation do
    use ExOperation.Operation

    def call(operation) do
      operation
      |> step(:some_step, fn _ -> {:ok, :some_result} end)
      |> after_commit(&{:ok, &1 |> Map.put(:first_callback, true)})
      |> after_commit(fn
        %{first_callback: true} = txn -> {:ok, txn |> Map.put(:second_callback, true)}
        _ -> raise "No first callback"
      end)
    end
  end

  test "call after commit hook" do
    assert {:ok, txn} = AfterCommitOperation |> ExOperation.run(%{}, %{})
    assert txn[:some_step]
    assert txn[:first_callback]
    assert txn[:second_callback]
  end

  defmodule AfterCommitWithBadReturnOperation do
    use ExOperation.Operation

    def call(operation) do
      operation
      |> after_commit(fn _ -> :wrong end)
    end
  end

  @error_regex ~r/Error in `ExOperation.AfterCommitTest.AfterCommitWithBadReturnOperation` in after commit callback:\n\(Elixir.ExOperation.AssertionError\) Expected `{:ok, result}` or {:error, reason}`. Got `:wrong`./

  test "raise on bad return from after commit callback" do
    assert_raise ExOperation.AfterCommitError, @error_regex, fn ->
      AfterCommitWithBadReturnOperation |> ExOperation.run(%{}, %{})
    end
  end

  defmodule RaisingAfterCommitOperation do
    use ExOperation.Operation

    def call(operation) do
      operation
      |> after_commit(fn _ -> raise "It failed" end)
    end
  end

  @error_regex ~r/Error in `ExOperation.AfterCommitTest.RaisingAfterCommitOperation` in after commit callback:\n\(Elixir.RuntimeError\) It failed/

  test "raise inside after commit callback" do
    assert_raise ExOperation.AfterCommitError, @error_regex, fn ->
      RaisingAfterCommitOperation |> ExOperation.run(%{}, %{})
    end
  end

  defmodule AfterCommitInSuboperationSuboperation do
    use ExOperation.Operation

    def call(operation) do
      operation
      |> after_commit(fn txn -> {:ok, Map.put(txn, :foo, :bar)} end)
    end
  end

  defmodule AfterCommitInSuboperationOperation do
    use ExOperation.Operation

    def call(operation) do
      operation
      |> suboperation(AfterCommitInSuboperationSuboperation, %{})
    end
  end

  test "call after commit callback defined in suboperation" do
    assert {:ok, txn} = AfterCommitInSuboperationOperation |> ExOperation.run(%{}, %{})
    assert %{foo: :bar} = txn
  end

  defmodule AfterCommitInDeferOperation do
    use ExOperation.Operation

    def call(operation) do
      operation
      |> defer(fn op, _txn ->
        op |> after_commit(fn txn -> {:ok, Map.put(txn, :foo, :bar)} end)
      end)
    end
  end

  test "call after commit callback defined in defer" do
    assert {:ok, txn} = AfterCommitInDeferOperation |> ExOperation.run(%{}, %{})
    assert %{foo: :bar} = txn
  end
end
