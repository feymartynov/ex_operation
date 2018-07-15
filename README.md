# ExOperation

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
    {:ex_operation, "~> 0.2.0"}
  ]
end
```

Add to your `config/config.exs`:

```elixir
config :ex_operation,
  repo: MyApp.Repo
```

where `MyApp.Repo` is the name of your Ecto.Repo module.
