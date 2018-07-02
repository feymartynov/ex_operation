alias ExOperation.Test.Repo

Mix.Task.run("ecto.drop", ~w(--quiet))
Mix.Task.run("ecto.create", ~w(--quiet))
Mix.Task.run("ecto.migrate", ~w(--quiet))

Mix.start()
Mix.shell(Mix.Shell.Process)
Logger.configure(level: :info)

ExUnit.start()

{:ok, _pid} = Repo.start_link()

Ecto.Adapters.SQL.Sandbox.mode(Repo, :manual)
