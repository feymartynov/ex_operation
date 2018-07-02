defmodule ExOperation.DSL do
  @moduledoc false

  alias ExOperation.{Operation, Builder}

  @type name :: any()
  @type txn :: [{name(), any()}]

  @spec step(
          operation :: Operation.t(),
          name :: name(),
          callback :: (txn :: txn() -> {:ok | :error, any()})
        ) :: Operation.t()
  def step(operation, name, callback) do
    %{operation | multi: operation.multi |> Ecto.Multi.run(name, callback)}
  end

  @spec find(operation :: Operation.t(), name :: name(), opts :: keyword()) :: Operation.t()
  def find(operation, name, opts) do
    step(operation, name, fn _ ->
      id_param_path = opts |> Keyword.get(:id_path, [:id]) |> List.wrap()
      preloads = opts |> Keyword.get(:preloads, [])

      with {:ok, id} when not is_nil(id) <- get_entity_id(operation.params, id_param_path, opts),
           {:ok, entity} <- get_entity(opts[:schema], id, opts) do
        {:ok, entity |> preload(preloads)}
      end
    end)
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

  @spec suboperation(
          operation :: Operation.t(),
          module :: Module.t(),
          params_or_fun :: map() | (txn :: txn() -> map())
        ) :: Operation.t()
  def suboperation(operation, module, params_or_fun) do
    multi =
      Ecto.Multi.merge(operation.multi, fn txn ->
        params = suboperation_params(params_or_fun, txn)
        {:ok, suboperation} = Builder.build(module, operation.context, params)
        suboperation.multi
      end)

    %{operation | multi: multi}
  end

  defp suboperation_params(map, _txn) when is_map(map), do: map
  defp suboperation_params(fun, txn) when is_function(fun), do: fun.(txn)

  @spec after_commit(operation :: Operation.t(), callback :: (map() -> any())) :: Operation.t()
  def after_commit(operation, callback) do
    %{operation | after_commit_callbacks: operation.after_commit_callbacks ++ [callback]}
  end
end
