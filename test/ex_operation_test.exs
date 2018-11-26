defmodule ExOperationTest do
  use ExOperation.TestCase, async: true

  test "return the configured repo" do
    assert ExOperation.repo() == ExOperation.Test.Repo
  end
end
