defmodule ExOperation.TestCase do
  use ExUnit.CaseTemplate
  alias ExOperation.Test.Repo

  using do
    quote do
      import ExOperation.Test.Factory
    end
  end

  setup tags do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    unless tags[:async] do
      Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    end

    :ok
  end
end
