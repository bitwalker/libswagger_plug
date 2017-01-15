defmodule Swagger.Client.HTTP do
  use Maxwell.Builder

  @maxwell_default_adapter Application.get_env(:maxwell, :default_adapter)
  @http_adapter @maxwell_default_adapter || Application.get_env(:libswagger_plug, :http_adapter, Maxwell.Adapter.Httpc)

  middleware Maxwell.Middleware.Logger
  middleware Maxwell.Middleware.Opts, Application.get_env(:libswagger_plug, :http_adapter_opts, [])
  middleware Maxwell.Middleware.Retry,
    delay: Application.get_env(:libswagger_plug, :retry_delay, 1_000),
    max_retries: Application.get_env(:libswagger_plug, :max_retries, 3)

  adapter @http_adapter

  def create(req) do
    conn = new(req.path)
	|> put_req_header(req.headers)
	|> put_query_string(req.query)
	case req.method do
	  method when method in [:get, :head, :options, :trace] -> conn
	  _ -> put_req_body(conn, req.body)
	end
  end

  def request(method, conn) when is_atom(method) do
    apply(__MODULE__, method, [conn])
  end
end
