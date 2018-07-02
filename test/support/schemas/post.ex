defmodule ExOperation.Test.Post do
  use Ecto.Schema

  schema "posts" do
    belongs_to(:author, ExOperation.Test.User)
  end
end
