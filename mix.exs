defmodule ExOperation.MixProject do
  use Mix.Project

  @version "0.4.0"

  def project do
    [
      app: :ex_operation,
      version: @version,
      elixir: "~> 1.6",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      preferred_cli_env: [credo: :test, ex_doc: :test],
      description: "A library for making domain operations",
      package: package(),
      name: "ExOperation",
      docs: [
        source_ref: "v#{@version}",
        main: "ExOperation",
        canonical: "http://hexdocs.pm/ex_operation",
        source_url: "https://github.com/feymartynov/ex_operation",
        extras: ~w(README.md)
      ]
    ]
  end

  def application do
    [extra_applications: extra_applications(Mix.env())]
  end

  defp extra_applications(:test), do: [:postgrex, :ecto, :logger]
  defp extra_applications(_), do: [:logger]

  defp elixirc_paths(:test), do: ~w(lib test/support)
  defp elixirc_paths(_), do: ~w(lib)

  defp deps do
    [
      {:ecto, "~> 2.0 or ~> 3.0"},
      {:params, "~> 2.1"},
      {:postgrex, "~> 0.13", optional: true},
      {:ecto_sql, "~> 3.0", only: [:test]},
      {:credo, "~> 0.9", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.18", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      maintainers: ["Fey Martynov"],
      licenses: ~w(MIT),
      links: %{github: "https://github.com/feymartynov/ex_operation"},
      files: ~w(lib mix.exs LICENSE README.md)
    ]
  end
end
