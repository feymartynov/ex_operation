defmodule ExOperation.Test.Repo do
  use Ecto.Repo,
    otp_app: :ex_operation,
    adapter: Ecto.Adapters.Postgres
end
