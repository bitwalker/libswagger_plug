defmodule Swagger.Client.HTTP do
  use Maxwell.Builder

  @maxwell_default_adapter Application.get_env(:maxwell, :default_adapter)
  @http_adapter @maxwell_default_adapter || Application.get_env(:libswagger_plug, :http_adapter, Maxwell.Adapter.Httpc)

  middleware Maxwell.Middleware.Logger, log_level: :debug
  middleware Maxwell.Middleware.Opts, Application.get_env(:libswagger_plug, :http_adapter_opts, [])

  adapter @http_adapter

  def create(url) do
    Maxwell.Conn.new(url)
  end

  def request(method, client) when is_atom(method) do
    apply(__MODULE__, method, [client])
  end
end
