use Mix.Config

config :logger, level: :warn

config :ex_operation,
  repo: ExOperation.Test.Repo

config :ex_operation, ecto_repos: [ExOperation.Test.Repo]

config :ex_operation, ExOperation.Test.Repo,
  adapter: Ecto.Adapters.Postgres,
  database: "ex_operation_test",
  pool: Ecto.Adapters.SQL.Sandbox,
  priv: "priv/test"
