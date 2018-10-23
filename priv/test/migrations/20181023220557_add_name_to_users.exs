defmodule ExOperation.Test.Repo.Migrations.AddNameToUsers do
  use Ecto.Migration

  def up do
    alter table(:users) do
      add(:name, :string)
    end
  end

  def down do
    alter table(:users) do
      remove(:name)
    end
  end
end
