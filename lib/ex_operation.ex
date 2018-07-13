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
      |> step(:result, &do_update(operation.context, &1))
      |> after_commit(:notification, &send_notifcation(&1.result))
    end

    defp do_update(context, txn) do
      txn.book
      |> Ecto.Changeset.cast(params, [:title])
      |> Ecto.Changeset.put_assoc(:author, txn.author)
      |> Ecto.Changeset.put_assoc(:updated_by, context.current_user)
      |> MyApp.Repo.update()
    end

    defp send_notification(updated_book) do
      # …
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
  @spec run(module :: Module.t(), context :: map(), raw_params :: map()) ::
          {:ok, map()}
          | {:error, Ecto.Changeset.t()}
          | {:error, step_name :: any(), reason :: any(), txn :: map()}
  def run(module, context \\ %{}, raw_params \\ %{}) do
    with {:ok, operation} <- ExOperation.Builder.build(module, context, raw_params),
         {:ok, txn} <- operation.multi |> repo().transaction() do
      for callback <- operation.after_commit_callbacks, do: callback.(txn)
      {:ok, txn}
    end
  end

  @doc false
  @spec repo :: Ecto.Repo.t()
  def repo do
    Application.get_env(:ex_operation, :repo) || raise "`:repo` config option not specified"
  end
end
