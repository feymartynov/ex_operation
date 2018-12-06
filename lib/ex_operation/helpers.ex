defmodule ExOperation.Helpers do
  @moduledoc false

  @ecto_path Mix.Project.deps_paths().ecto
  @ecto_version Mix.Project.in_project(:ecto, @ecto_path, & &1.project()[:version])

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

  @doc """
  Builds an `Ecto.Multi.run/2` callback.

  `Ecto.Multi.run/2` in Ecto 3 gets a callback with two arguments
  while in Ecto 2 it gets a callback with one argument.
  """
  if @ecto_version |> Version.parse!() |> Version.match?(">= 3.0.0") do
    def build_multi_run_fun(fun), do: fn _repo, txn -> fun.(txn) end
  else
    def build_multi_run_fun(fun), do: fun
  end
end
