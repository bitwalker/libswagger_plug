defmodule SwaggerPlug.Mixfile do
  use Mix.Project

  def project do
    [app: :libswagger_plug,
     version: "0.1.0",
     elixir: "~> 1.3",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     elixirc_paths: elixirc_paths(Mix.env),
     deps: deps(),
	 test_coverage: [tool: Coverex.Task, coveralls: true,
       ignore_modules: [Swagger.Test.Handlers.UsersHandler]]]
  end

  def application do
    [applications: [:logger, :poison, :plug, :maxwell],
     mod: {Swagger.Plug.App, []}]
  end

  defp deps do
    [{:libswagger, github: "bitwalker/libswagger"},
     {:poison, "~> 3.0", override: true},
     {:maxwell, github: "zhongwencool/maxwell"},
     {:plug, "~> 1.3"},
     {:cowboy, "~> 1.0", only: [:dev, :test]},
     {:coverex, "~> 1.4", only: [:test]}]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_),     do: ["lib"]
end
