defmodule ExOperation.SuboperationTest do
  use ExOperation.TestCase, async: true

  defmodule SubOperation do
    use ExOperation.Operation, params: %{message!: :string}

    def call(operation) do
      operation |> step(:result, fn _ -> {:ok, operation.params.message} end)
    end
  end

  defmodule StaticWrapperOperation do
    use ExOperation.Operation, params: %{greeting!: :string}

    def call(operation) do
      operation |> suboperation(SubOperation, %{message: operation.params.greeting}, id: :sub)
    end
  end

  test "suboperation with static params" do
    assert {:ok, txn} = StaticWrapperOperation |> ExOperation.run(%{}, %{"greeting" => "hello"})
    assert txn.sub.result == "hello"
  end

  defmodule DynamicWrapperOperation do
    use ExOperation.Operation, params: %{greeting!: :string}

    def call(operation) do
      operation
      |> step(:object, fn _ -> {:ok, "world"} end)
      |> suboperation(
        SubOperation,
        &%{message: operation.params.greeting <> " " <> &1.object},
        id: :sub
      )
    end
  end

  test "suboperation with dynamic params" do
    assert {:ok, txn} = DynamicWrapperOperation |> ExOperation.run(%{}, %{"greeting" => "hello"})
    assert txn.sub.result == "hello world"
  end

  defmodule InterferingOperation do
    use ExOperation.Operation

    def call(operation) do
      operation
      |> suboperation(SubOperation, %{message: "one"}, id: :one)
      |> suboperation(SubOperation, %{message: "two"}, id: :two)
    end
  end

  test "suboperations with interfering step names" do
    assert {:ok, txn} = InterferingOperation |> ExOperation.run(%{}, %{})
    assert txn.one.result == "one"
    assert txn.two.result == "two"
  end

  defmodule WrapperOperation do
    use ExOperation.Operation, params: %{greeting!: :string}

    def call(operation) do
      operation
      |> suboperation(SubOperation, %{message: operation.params.greeting}, id: :sub1)
    end
  end

  defmodule DoubleWrapperOperation do
    use ExOperation.Operation, params: %{greeting!: :string}

    def call(operation) do
      operation
      |> suboperation(WrapperOperation, %{greeting: operation.params.greeting}, id: :sub2)
    end
  end

  test "nested suboperations" do
    assert {:ok, txn} = DoubleWrapperOperation |> ExOperation.run(%{}, %{"greeting" => "hello"})
    assert txn.sub2.sub1.result == "hello"
  end

  defmodule ContextOverrideSubOperation do
    use ExOperation.Operation, params: %{id: :integer}

    def call(operation) do
      operation
      |> find(:user,
        schema: ExOperation.Test.User,
        context_getter: fn
          %{user: %ExOperation.Test.User{} = user} -> {:ok, user}
          _ -> :not_found
        end
      )
      |> step(:passed_value, fn _ -> {:ok, operation.context[:foo]} end)
    end
  end

  defmodule ContextOverrideOperation do
    use ExOperation.Operation, params: %{}

    def call(operation) do
      operation
      |> suboperation(ContextOverrideSubOperation, %{},
        id: :sub,
        context: %{user: %ExOperation.Test.User{name: "John Doe"}, foo: :baz}
      )
    end
  end

  test "override suboperation context" do
    assert {:ok, txn} = ContextOverrideOperation |> ExOperation.run(%{foo: :bar}, %{})
    assert txn.sub.user.name == "John Doe"
    assert txn.sub.passed_value == :baz
  end

  defmodule ContextGetterOperation do
    use ExOperation.Operation, params: %{}

    def call(operation) do
      operation
      |> step(:build_user, fn _ -> {:ok, %ExOperation.Test.User{name: "John Doe"}} end)
      |> suboperation(ContextOverrideSubOperation, %{},
        id: :sub,
        context: &Map.put(operation.context, :user, &1.build_user)
      )
    end
  end

  test "pass schema and plain value to suboperation through context" do
    assert {:ok, txn} = ContextGetterOperation |> ExOperation.run(%{foo: :bar}, %{})
    assert txn.sub.user.name == "John Doe"
    assert txn.sub.passed_value == :bar
  end
end
