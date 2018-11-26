defmodule ExOperation.FindTest do
  use ExOperation.TestCase, async: true

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
end
