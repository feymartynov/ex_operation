defmodule ExOperation.Test.Factory do
  def build(:user) do
    %ExOperation.Test.User{}
  end

  def build(:post) do
    %ExOperation.Test.Post{author: build(:user)}
  end

  def build(factory_name, attributes) do
    factory_name |> build() |> struct(attributes)
  end

  def insert!(factory_name, attributes \\ []) do
    factory_name |> build(attributes) |> ExOperation.Test.Repo.insert!()
  end
end
