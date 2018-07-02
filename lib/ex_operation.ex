defmodule ExOperation do
  @moduledoc false

  @spec run(module :: Module.t(), context :: map(), raw_params :: map()) :: {:ok | :error, map()}
  def run(module, context \\ %{}, raw_params \\ %{}) do
    with {:ok, operation} <- ExOperation.Builder.build(module, context, raw_params),
         {:ok, txn} <- operation.multi |> repo().transaction() do
      for callback <- operation.after_commit_callbacks, do: callback.(txn)
      {:ok, txn}
    end
  end

  @spec repo :: Ecto.Repo.t()
  def repo do
    Application.get_env(:ex_operation, :repo) || raise "`:repo` config option not specified"
  end
end
