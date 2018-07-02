defmodule ExOperationTest do
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
    assert FailingOperation |> ExOperation.run(%{}, %{}) == {:error, :result, :failed, %{}}
  end

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
    assert FinderOperation |> ExOperation.run(%{}, params) == {:error, :post, :not_found, %{}}
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

  defmodule SubOperation do
    use ExOperation.Operation, params: %{message!: :string}

    def call(operation) do
      operation |> step(:result, fn _ -> {:ok, operation.params.message} end)
    end
  end

  defmodule StaticWrapperOperation do
    use ExOperation.Operation, params: %{greeting!: :string}

    def call(operation) do
      operation |> suboperation(SubOperation, %{message: operation.params.greeting})
    end
  end

  test "suboperation with static params" do
    assert {:ok, txn} = StaticWrapperOperation |> ExOperation.run(%{}, %{"greeting" => "hello"})
    assert txn.result == "hello"
  end

  defmodule DynamicWrapperOperation do
    use ExOperation.Operation, params: %{greeting!: :string}

    def call(operation) do
      operation
      |> step(:object, fn _ -> {:ok, "world"} end)
      |> suboperation(SubOperation, &%{message: operation.params.greeting <> " " <> &1.object})
    end
  end

  test "suboperation with dynamic params" do
    assert {:ok, txn} = DynamicWrapperOperation |> ExOperation.run(%{}, %{"greeting" => "hello"})
    assert txn.result == "hello world"
  end

  defmodule AfterCommitOperation do
    use ExOperation.Operation

    def call(operation) do
      operation
      |> step(:user, fn _ -> %ExOperation.Test.User{} |> ExOperation.Test.Repo.insert() end)
      |> after_commit(&(operation.context.pid |> send(&1.user)))
    end
  end

  test "call after commit hook" do
    assert {:ok, _txn} = AfterCommitOperation |> ExOperation.run(%{pid: self()}, %{})
    assert_receive %ExOperation.Test.User{id: id}
    assert id
  end

  test "return the configured repo" do
    assert ExOperation.repo() == ExOperation.Test.Repo
  end
end
