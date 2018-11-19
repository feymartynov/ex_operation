defmodule ExOperationTest do
  use ExOperation.TestCase, async: true

  ########
  # Step #
  ########

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

  @error_regex ~r/Error in `ExOperationTest.StepWithBadReturnOperation` in step `:result`:\n\(Elixir.ExOperation.AssertionError\) Expected `{:ok, result}` or {:error, reason}`. Got `:wrong`./

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

  @error_regex ~r/Error in `ExOperationTest.RaisingStepOperation` in step `:result`:\n\(Elixir.RuntimeError\) It failed/

  test "raise inside step" do
    assert_raise ExOperation.StepError, @error_regex, fn ->
      RaisingStepOperation |> ExOperation.run(%{}, %{})
    end
  end

  ########
  # Find #
  ########

  defmodule FinderOperation do
    use ExOperation.Operation, params: %{id!: :integer}

    def call(operation) do
      operation
      |> find(:post, schema: ExOperation.Test.Post, preloads: [:author])
      |> step(:author, &{:ok, &1.post.author})
    end
  end

  test "find an entity and access its preloaded association" do
    post = insert!(:post)
    assert {:ok, txn} = FinderOperation |> ExOperation.run(%{}, %{"id" => post.id})
    assert txn.post.id == post.id
    assert txn.author.id == post.author.id
  end

  test "fail on not found entity" do
    params = %{"id" => "1234567"}
    result = FinderOperation |> ExOperation.run(%{}, params)
    assert result == {:error, {:main, :post}, :not_found, %{}}
  end

  defmodule DeepFinderOperation do
    use ExOperation.Operation, params: %{deep: %{user_id: :integer}}

    def call(operation) do
      operation
      |> find(
        :user,
        schema: ExOperation.Test.User,
        id_path: [:deep, :user_id],
        optional: true,
        skip_missing: true
      )
    end
  end

  test "find an entity by id path" do
    user = insert!(:user)
    params = %{"deep" => %{"user_id" => user.id}}
    assert {:ok, txn} = DeepFinderOperation |> ExOperation.run(%{}, params)
    assert txn.user.id == user.id
  end

  test "skip optional finding when id param is not given" do
    assert {:ok, txn} = DeepFinderOperation |> ExOperation.run(%{}, %{})
    assert txn.user |> is_nil()
  end

  test "skip missing entity" do
    params = %{"deep" => %{"user_id" => "1234567"}}
    assert {:ok, txn} = DeepFinderOperation |> ExOperation.run(%{}, params)
    assert txn.user |> is_nil()
  end

  ################
  # Suboperation #
  ################

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

  ######################################
  # Suboperation with context override #
  ######################################

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

  #########
  # Defer #
  #########

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

  @error_regex ~r/Error in `ExOperationTest.DeferWithBadReturnOperation` in defer callback:\n\(Elixir.ExOperation.AssertionError\) Expected `%ExOperation.Operation{}`. Got `:wrong`./

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

  @error_regex ~r/Error in `ExOperationTest.RaisingDeferOperation` in defer callback:\n\(Elixir.RuntimeError\) It failed/

  test "raise inside defer callback" do
    assert_raise ExOperation.DeferError, @error_regex, fn ->
      RaisingDeferOperation |> ExOperation.run(%{}, %{})
    end
  end

  ######################
  # After commit hooks #
  ######################

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

  @error_regex ~r/Error in `ExOperationTest.AfterCommitWithBadReturnOperation` in after commit callback:\n\(Elixir.ExOperation.AssertionError\) Expected `{:ok, result}` or {:error, reason}`. Got `:wrong`./

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

  @error_regex ~r/Error in `ExOperationTest.RaisingAfterCommitOperation` in after commit callback:\n\(Elixir.RuntimeError\) It failed/

  test "raise inside after commit callback" do
    assert_raise ExOperation.AfterCommitError, @error_regex, fn ->
      RaisingAfterCommitOperation |> ExOperation.run(%{}, %{})
    end
  end

  ########
  # Repo #
  ########

  test "return the configured repo" do
    assert ExOperation.repo() == ExOperation.Test.Repo
  end
end
