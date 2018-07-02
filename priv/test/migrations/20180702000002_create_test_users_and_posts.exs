defmodule ExOperation.Test.Repo.Migrations.CreateTestUsersAndPosts do
  use Ecto.Migration

  def up do
    create table(:users) do
    end

    create table(:posts) do
      add(:author_id, references(:users, on_delete: :delete_all), null: false)
    end
  end

  def down do
    drop(table(:posts))
    drop(table(:users))
  end
end
