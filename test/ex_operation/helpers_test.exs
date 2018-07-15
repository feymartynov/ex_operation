defmodule ExOperation.HelpersTest do
  use ExOperation.TestCase, async: true

  test "transform_txn/2" do
    txn = [{{:main, {:sub2, {:sub1, :result}}}, "value1"}, {{:main, :something}, "value2"}]
    result = txn |> ExOperation.Helpers.transform_txn(%ExOperation.Operation{ids: [:main]})
    assert result == %{sub2: %{sub1: %{result: "value1"}}, something: "value2"}
  end
end
