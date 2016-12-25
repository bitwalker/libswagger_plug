defmodule SwaggerPlug.Mixfile do
  use Mix.Project

  def project do
    [app: :libswagger_plug,
     version: "0.1.0",
     elixir: "~> 1.3",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps()]
  end

  def application do
    [applications: [:logger, :poison, :plug, :fuse, :tesla],
     mod: {Swagger.Plug.App, []}]
  end

  defp deps do
    [{:libswagger, path: "../libswagger"},
     {:poison, "~> 3.0"},
     {:fuse, "~> 2.4"},
     {:tesla, "~> 0.5.2"},
     {:hackney, "~> 1.6", optional: true},
     {:plug, "~> 1.3"},
     {:cowboy, "~> 1.0", only: [:dev, :test]}]
  end
end
