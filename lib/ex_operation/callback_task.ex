defmodule ExOperation.CallbackTask do
  @moduledoc false

  defstruct operation: nil, callback: nil

  alias ExOperation.{CallbackError, Operation}

  @doc """
  Builds a callback task.
  """
  def build(operation, callback) when is_function(callback, 1) do
    %__MODULE__{operation: operation, callback: callback}
  end

  @doc """
  Runs a callback task against `txn` preserving local operation scope.
  """
  def run(%__MODULE__{operation: operation, callback: callback}, txn) do
    case run_callback(operation, callback, get_local_txn(operation, txn)) do
      {:ok, local_txn} -> {:ok, put_local_txn(operation, txn, local_txn)}
      other -> other
    end
  end

  defp run_callback(operation, callback, txn) do
    txn |> callback.() |> assert_return_value()
  rescue
    e ->
      attrs = [operation: operation, txn: txn, exception: e]
      reraise CallbackError, attrs, System.stacktrace()
  end

  defp assert_return_value({:ok, %{}} = result), do: result
  defp assert_return_value({:error, _} = result), do: result

  defp assert_return_value(other) do
    message = "Expected `{:ok, %{}}` or {:error, reason}`. Got `#{inspect(other)}`."
    raise ExOperation.AssertionError, message
  end

  defp get_local_txn(%Operation{ids: [:main | []]}, txn), do: txn
  defp get_local_txn(%Operation{ids: [:main | path]}, txn), do: txn |> get_in(path)

  defp put_local_txn(%Operation{ids: [:main | []]}, _txn, value), do: value
  defp put_local_txn(%Operation{ids: [:main | path]}, txn, value), do: txn |> put_in(path, value)
end
