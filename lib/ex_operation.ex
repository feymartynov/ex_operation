defmodule ExOperation do
  @moduledoc """
  A library for making domain operations wrapped in a single database transaction.

  ## Example

  An operation definition:

  ```elixir
  defmodule MyApp.Book.Update do
    use ExOperation, params: %{
      id!: :integer,
      title!: :string,
      author_id: :integer
    }

    def validate_params(changeset) do
      changeset
      |> Ecto.Changeset.validate_length(:title, min: 5)
    end

    def call(operation) do
      operation
      |> find(:book, schema: MyApp.Book, preload: [:author])
      |> find(:author, schema: MyApp.Author, id_path: [:author_id], optional: true)
      |> step(:result, &do_update(operation.context, &1, operation.params))
      |> after_commit(&send_notifcation(&1))
    end

    defp do_update(context, txn, params) do
      txn.book
      |> Ecto.Changeset.cast(params, [:title])
      |> Ecto.Changeset.put_assoc(:author, txn.author)
      |> Ecto.Changeset.put_assoc(:updated_by, context.current_user)
      |> MyApp.Repo.update()
    end

    defp send_notification(txn) do
      # …
      {:ok, txn}
    end
  end
  ```

  The call:

  ```elixir
  context = %{current_user: current_user}

  with {:ok, %{result: book}} <- MyApp.Book.Update |> ExOperation.run(context, params) do
    # …
  end
  ```

  ## Features

  * [Railway oriented](https://fsharpforfunandprofit.com/rop/) domain logic pipeline.
  * Running all steps in a single database transaction. It uses [Ecto.Multi](https://hexdocs.pm/ecto/Ecto.Multi.html) inside.
  * Params casting & validation with `Ecto.Changeset`. Thanks to [params](https://github.com/vic/params) library.
  * Convenient fetching of entitites from the database.
  * Context passing. Useful for passing current user, current locale etc.
  * Composable operations: one operation can call another through `suboperation/3` function.
  * After commit hooks for scheduling asynchronous things.

  ## Installation

  Add the following to your `mix.exs` and then run `mix deps.get`:

  ```elixir
  def deps do
    [
      {:ex_operation, "~> 0.1.0"}
    ]
  end
  ```

  Add to your `config/config.exs`:

  ```elixir
  config :ex_operation,
    repo: MyApp.Repo
  ```

  where `MyApp.Repo` is the name of your Ecto.Repo module.
  """

  alias ExOperation.{Builder, CallbackTask, Helpers}

  @doc """
  Call an operation from `module`.
  `module` must implement `ExOperation.Operation` behaviour.

  `context` is an arbitrary map for passing application-specific data such as current user.

  `raw_params` is a map of parameters that will be casted and validated
  according to the operation's params specification.
  Keys may be strings either atoms. Nesting is supported.

  In case when all steps return `{:ok, result}` tuple and DB transaction successfully commited
  it returns `{:ok, txn}` tuple where `txn` is a map where keys are step names
  and values are their results.

  In case of invalid `raw_params` it returns `{:error, changeset}`
  where `changeset` is an `Ecto.Chageset` struct containing validation errors.

  In case of error in one of the steps or database error it returns `{:error, name, reason, txn}`
  tuple where `name` is the failed step name, `reason` is the error and `txn` is changes so far.

  If any after commit callbacks are scheduled they get called after database transaction commit and
  before the return.
  """
  @spec run(module :: atom(), context :: map(), raw_params :: map()) ::
          {:ok, map()}
          | {:error, Ecto.Changeset.t()}
          | {:error, step_name :: any(), reason :: any(), txn :: map()}
  def run(module, context \\ %{}, raw_params \\ %{}) do
    with {:ok, operation} <- Builder.build(module, context, raw_params, id: :main),
         {:ok, txn} <- operation |> run_before_transaction_callbacks(),
         operation <- operation |> merge_txn(txn),
         {:ok, txn} <- operation.multi |> repo().transaction do
      operation |> run_after_commit_callbacks(txn)
    end
  end

  defp run_before_transaction_callbacks(operation) do
    operation.before_transaction_callbacks
    |> Enum.reverse()
    |> Enum.reduce_while({:ok, %{}}, fn callback_task, {:ok, acc} ->
      case CallbackTask.run(callback_task, acc) do
        {:ok, txn} -> {:cont, {:ok, txn}}
        other -> {:halt, other}
      end
    end)
  end

  defp merge_txn(operation, txn) do
    multi =
      Enum.reduce(txn, Ecto.Multi.new(), fn {key, value}, acc ->
        acc |> Ecto.Multi.run({:main, key}, Helpers.build_multi_run_fun(fn _ -> {:ok, value} end))
      end)

    operation.multi |> update_in(&Ecto.Multi.prepend(&1, multi))
  end

  defp run_after_commit_callbacks(operation, raw_txn) do
    txn = raw_txn |> Helpers.transform_txn(operation)

    Enum.reduce_while(raw_txn, {:ok, txn}, fn
      {{:__after_commit__, _}, callback_task}, {:ok, acc} ->
        case CallbackTask.run(callback_task, acc) do
          {:ok, txn} -> {:cont, {:ok, txn}}
          other -> {:halt, other}
        end

      _, other ->
        {:cont, other}
    end)
  end

  @doc false
  @spec repo :: Ecto.Repo.t()
  def repo do
    Application.get_env(:ex_operation, :repo) || raise "`:repo` config option not specified"
  end
end
