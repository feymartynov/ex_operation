defmodule ExOperation.DSL do
  @moduledoc """
  Functions that help defining operations.
  """

  alias ExOperation.{Operation, Builder, Helpers}

  @type name :: any()
  @type txn :: [{name(), any()}]

  @doc """
  Adds an arbitrary step to the operation pipeline.

  `callback` is a function that accepts a map of changes so far where keys are names of previous
  steps and values are their return values.
  It must return either `{:ok, result}` or `{:error, reason}` tuple.
  """
  @spec step(
          operation :: Operation.t(),
          name :: name(),
          callback :: (txn :: txn() -> {:ok | :error, any()})
        ) :: Operation.t()
  def step(operation, name, callback) do
    [operation_id | wrapper_ids] = Enum.reverse(operation.ids)
    step_key = wrapper_ids |> Enum.reduce({operation_id, name}, fn id, acc -> {id, acc} end)

    fun = fn txn -> txn |> Helpers.transform_txn(operation) |> callback.() end

    %{operation | multi: operation.multi |> Ecto.Multi.run(step_key, fun)}
  end

  @doc """
  A conveniece step for fetching entities from the database.
  It wraps `Ecto.Repo.get/2` under the hood.

  ## Options
    * `:schema` – an Ecto.Schema module name to find for. This options is required.
    * `:id_path` – param name or path list for deeply nested id key. Defaults to `[:id]`.
    * `:preloads` – a list of association preloading in the format of `Ecto.Repo.preload/3`.
    Doesn't preload any associations by default.
    * `:optional` – when enabled doesn't return error but `nil` if `:id_path` is missing
    in the given params. Defaults to `false`.
    * `:skip_missing` – when enabled doesn't return error but `nil` if the entity is missing
    in the database. Defaults to `false`.
    * `:context_getter` – an optional function that gets the context and returns
    `{:ok, schema}`, `:not_found`, or `{:error, reason}`. If `:not_found` is returned then
    it tries to find the schema in the database as usual.
  """
  @spec find(operation :: Operation.t(), name :: name(), opts :: keyword()) :: Operation.t()
  def find(operation, name, opts) do
    step(operation, name, fn _ ->
      case find_in_context(opts[:context_getter], operation.context) do
        {:ok, schema} -> {:ok, schema}
        :not_found -> find_in_db(operation, opts)
        {:error, reason} -> {:error, reason}
      end
    end)
  end

  defp find_in_context(nil, _context), do: :not_found
  defp find_in_context(getter, context) when is_function(getter, 1), do: getter.(context)

  defp find_in_db(operation, opts) do
    id_param_path = opts |> Keyword.get(:id_path, [:id]) |> List.wrap()
    preloads = opts |> Keyword.get(:preloads, [])

    with {:ok, id} when not is_nil(id) <- get_entity_id(operation.params, id_param_path, opts),
         {:ok, entity} <- get_entity(opts[:schema], id, opts) do
      {:ok, entity |> preload(preloads)}
    end
  end

  defp get_entity_id(_params, [], _opts), do: raise("ID parameter path can't be blank")

  defp get_entity_id(params, id_param_path, opts) do
    case params |> get_in(id_param_path) do
      nil -> (opts[:optional] && {:ok, nil}) || {:error, :missing_id_param}
      id -> {:ok, id}
    end
  end

  defp get_entity(nil, _id, _opts), do: raise("Schema not specified")

  defp get_entity(schema, id, opts) do
    case ExOperation.repo().get(schema, id) do
      nil -> (opts[:skip_missing] && {:ok, nil}) || {:error, :not_found}
      result -> {:ok, result}
    end
  end

  defp preload(entity, []), do: entity
  defp preload(entity, preloads), do: entity |> ExOperation.repo().preload(preloads)

  @doc """
  Embeds another operation into the current one.

  `module` is the suboperation module.

  `params_or_fun` can be either a map or a callback function that gets changes so far
  and returns a map. The map will be passed to the suboperation.

  Context is passed without changes.

  ## Options
    * `:id` – unique term to identify the suboperation (optional).
    * `:context` – override context (optional). It can be a map or a function that gets current
    transaction map and returns a context map to pass into the suboperation.
  """
  @spec suboperation(
          operation :: Operation.t(),
          module :: atom(),
          params_or_fun :: map() | (txn :: txn() -> map()),
          opts :: keyword()
        ) :: Operation.t()
  def suboperation(operation, module, params_or_fun, opts \\ []) do
    multi =
      Ecto.Multi.merge(operation.multi, fn txn ->
        txn = txn |> Helpers.transform_txn(operation)
        context = suboperation_context(operation.context, txn, opts[:context])
        params = suboperation_params(params_or_fun, txn)
        opts = opts |> Keyword.put(:parent_ids, operation.ids)
        {:ok, suboperation} = Builder.build(module, context, params, opts)
        suboperation.multi
      end)

    %{operation | multi: multi}
  end

  defp suboperation_context(_, _, %{} = overriden_context), do: overriden_context
  defp suboperation_context(_, txn, fun) when is_function(fun, 1), do: fun.(txn)
  defp suboperation_context(context, _, _), do: context

  defp suboperation_params(map, _txn) when is_map(map), do: map
  defp suboperation_params(fun, txn) when is_function(fun, 1), do: fun.(txn)

  @doc """
  Changes `operation`'s scenario depending on results of previous steps using `callback`.

  The `callback` receives the `operation` and results of previous steps.
  It must return a new `operation`.
  """
  @spec defer(
          operation :: Operation.t(),
          callback :: (Operation.t(), txn() -> Operation.t())
        ) :: Operation.t()
  def defer(operation, callback) when is_function(callback, 2) do
    multi =
      Ecto.Multi.merge(operation.multi, fn txn ->
        txn = txn |> Helpers.transform_txn(operation)

        %Operation{multi: multi} =
          operation
          |> Map.put(:multi, Ecto.Multi.new())
          |> callback.(txn)

        multi
      end)

    %{operation | multi: multi}
  end

  @doc """
  Schedules a `callback` function to run after successful database transaction commit.

  The `callback` receives the transaction map and must return `{:ok, txn}` or `{:error, reason}`
  like `step/2`'s callback does.

  All hooks are being applied in the same order they were added.
  """
  @spec after_commit(
          operation :: Operation.t(),
          callback :: (txn() -> {:ok, txn()} | {:error, term()})
        ) :: Operation.t()
  def after_commit(operation, callback) when is_function(callback, 1) do
    %{operation | after_commit_callbacks: operation.after_commit_callbacks ++ [callback]}
  end
end
