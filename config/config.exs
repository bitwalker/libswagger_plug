use Mix.Config

config :libswagger_plug, Swagger.Schema.Loader.FileLoader,
  root_dir: Path.join([__DIR__, "..", "test", "schemas"])

config :logger,
  level: :warn,
  handle_otp_reports: true,
  handle_sasl_reports: true

config :sasl,
  errlog_type: :error

config :yamerl,
  node_mods: []
