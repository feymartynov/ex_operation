defmodule ExOperation.Helpers do
  @moduledoc false

  @doc """
  Transforms the operation result `txn` map to a convenient form for the `operation`.
  """
  def transform_txn(txn, %ExOperation.Operation{ids: ids}), do: txn |> unwrap(ids) |> mapify()

  defp unwrap(txn, []), do: txn

  defp unwrap(txn, [head | tail]) do
    unwrapped_txn = for {{^head, key}, value} <- txn, into: %{}, do: {key, value}
    unwrapped_txn |> unwrap(tail)
  end

  defp mapify(txn) do
    {acc, wrappers} =
      Enum.reduce(txn, {%{}, []}, fn
        {{wrapper, _}, _}, {acc, wrappers} -> {acc, [wrapper | wrappers]}
        {key, value}, {acc, wrappers} -> {acc |> Map.put(key, value), wrappers}
      end)

    Enum.reduce(wrappers, acc, fn wrapper, acc ->
      acc |> Map.put(wrapper, txn |> unwrap([wrapper]) |> mapify())
    end)
  end
end
