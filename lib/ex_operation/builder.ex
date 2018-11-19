defmodule ExOperation.Builder do
  @moduledoc false

  alias ExOperation.Operation

  @spec build(module :: atom(), context :: map(), raw_params :: map()) ::
          {:ok | Operation.t()} | {:error, any()}
  def build(module, context \\ %{}, raw_params \\ %{}, opts \\ []) do
    with {:ok, changeset} <- build_changeset(module, raw_params) do
      build_operation(module, context, Params.to_map(changeset), opts)
    end
  end

  defp build_changeset(module, raw_params) do
    changeset = [module, OperationParams] |> Module.concat() |> apply(:from, [raw_params])
    changeset = module |> validate_params(changeset)

    if changeset.valid? do
      {:ok, changeset}
    else
      {:error, changeset}
    end
  end

  defp validate_params(module, changeset) do
    if module |> function_exported?(:validate_params, 1) do
      module |> apply(:validate_params, [changeset])
    else
      changeset
    end
  end

  defp build_operation(module, context, params, opts) do
    parent_ids = opts[:parent_ids] || []
    id = opts[:id] || make_ref()

    operation = %Operation{
      module: module,
      multi: Ecto.Multi.new(),
      ids: parent_ids ++ [id],
      context: context,
      params: params
    }

    case module |> apply(:call, [operation]) do
      %Operation{} = operation -> {:ok, operation}
      _ -> raise "`call/1` function must return an `ExOperation.Operation` struct"
    end
  end
end
