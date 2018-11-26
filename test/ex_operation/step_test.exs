defmodule ExOperation.StepTest do
  use ExOperation.TestCase, async: true

  defmodule DummyOperation do
    use ExOperation.Operation, params: %{message!: :string}
    import Ecto.Changeset

    def call(operation) do
      operation
      |> step(:get_context, fn _ -> {:ok, operation.context.message} end)
      |> step(:get_param, fn _ -> {:ok, operation.params.message} end)
    end

    def validate_params(changeset) do
      changeset
      |> validate_length(:message, min: 6)
    end
  end

  test "run an operation" do
    context = %{message: "hello context"}
    params = %{"message" => "hello params"}

    assert {:ok, txn} = DummyOperation |> ExOperation.run(context, params)
    assert txn.get_context == context.message
    assert txn.get_param == params["message"]
  end

  test "fail on missing required params" do
    assert {:error, changeset} = DummyOperation |> ExOperation.run(%{}, %{})
    assert {"can't be blank", _} = changeset.errors[:message]
  end

  test "fail on invalid params" do
    assert {:error, changeset} = DummyOperation |> ExOperation.run(%{}, %{"message" => "short"})
    assert {"should be at least %{count} character(s)", _} = changeset.errors[:message]
  end

  defmodule FailingOperation do
    use ExOperation.Operation

    def call(operation) do
      operation
      |> step(:result, fn _ -> {:error, :failed} end)
      |> step(:unreachable, fn _ -> raise "This shouldn't be called" end)
    end
  end

  test "fail on failed step" do
    result = FailingOperation |> ExOperation.run(%{}, %{})
    assert result == {:error, {:main, :result}, :failed, %{}}
  end

  defmodule StepWithBadReturnOperation do
    use ExOperation.Operation

    def call(operation) do
      operation
      |> step(:result, fn _ -> :wrong end)
    end
  end

  @error_regex ~r/Error in `ExOperation.StepTest.StepWithBadReturnOperation` in step `:result`:\n\(Elixir.ExOperation.AssertionError\) Expected `{:ok, result}` or {:error, reason}`. Got `:wrong`./

  test "raise on bad return from step" do
    assert_raise ExOperation.StepError, @error_regex, fn ->
      StepWithBadReturnOperation |> ExOperation.run(%{}, %{})
    end
  end

  defmodule RaisingStepOperation do
    use ExOperation.Operation

    def call(operation) do
      operation
      |> step(:result, fn _ -> raise "It failed" end)
    end
  end

  @error_regex ~r/Error in `ExOperation.StepTest.RaisingStepOperation` in step `:result`:\n\(Elixir.RuntimeError\) It failed/

  test "raise inside step" do
    assert_raise ExOperation.StepError, @error_regex, fn ->
      RaisingStepOperation |> ExOperation.run(%{}, %{})
    end
  end
end
