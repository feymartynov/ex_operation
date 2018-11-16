defmodule ExOperation.Test.Post do
  @moduledoc false

  use Ecto.Schema

  schema "posts" do
    belongs_to(:author, ExOperation.Test.User)
  end
end
