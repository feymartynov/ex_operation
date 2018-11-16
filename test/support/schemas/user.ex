defmodule ExOperation.Test.User do
  @moduledoc false

  use Ecto.Schema

  schema "users" do
    field(:name, :string)
  end
end
