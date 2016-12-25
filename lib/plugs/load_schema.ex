defmodule Swagger.Plug.LoadSchema do
  @moduledoc """
  This plug is responsible for loading a schema based on an incoming request.
  Intended for use with the ReverseProxy plug.
  """
  alias Plug.Conn
  import Plug.Conn

  alias Swagger.Schema
  alias Swagger.Schema.{Endpoint, Operation}

  def init(options) do
    key = Keyword.fetch!(options, :schema_key)
    loader = Keyword.get(options, :schema_loader, Swagger.Schema.Loader)
    operation_key = Keyword.get(options, :operation_key)
    %{schema_key: key, schema_loader: loader, operation_key: operation_key}
  end

  def call(%Conn{params: %Plug.Conn.Unfetched{}} = conn, options) do
    call(fetch_query_params(conn), options)
  end
  def call(conn, %{schema_key: key, schema_loader: loader, operation_key: operation_key}) do
    with conn              <- fetch_query_params(conn),
         {:ok, conn}       <- extract_schema(conn, key, loader),
         {:ok, conn}       <- extract_operation(conn, operation_key),
      do: conn
  end

  defp extract_schema(conn, key, loader) do
    case conn.params[key] do
      nil ->
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(400, "missing required parameter '#{key}'")
        |> halt()
      loader_key ->
        case loader.load(loader_key) do
          {:error, reason} when is_binary(reason) ->
            conn
            |> put_resp_content_type("text/plain")
            |> send_resp(400, "unable to load schema '#{loader_key}': #{reason}")
            |> halt()
          {:error, reason} ->
            conn
            |> put_resp_content_type("text/plain")
            |> send_resp(400, "unable to load schema '#{loader_key}': #{inspect reason}")
            |> halt()
          {:ok, %Schema{} = schema} ->
            conn = put_private(conn, :libswagger_schema_key, loader_key)
            conn = put_private(conn, :libswagger_schema, schema)
            {:ok, conn}
        end
    end
  end

  defp extract_operation(%Conn{method: method} = conn, nil) do
    method = String.to_atom(String.downcase(method))
    # Extract operation based on current request's path and HTTP method
    schema = conn.private[:libswagger_schema]
    endpoint = Enum.find(schema.paths, fn {_, e} -> Regex.match?(e.route_pattern, conn.request_path) end)
    case endpoint do
      nil ->
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(400, "no operation found which matches `#{String.upcase(~s(#{method}))} #{conn.request_path}`")
        |> halt()
      {_, %Endpoint{operations: %{^method => op}} = e} ->
        conn = put_private(conn, :libswagger_endpoint, e)
        conn = put_private(conn, :libswagger_operation, op)
        {:ok, conn}
      {_, %Endpoint{}} ->
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(400, "no #{String.upcase(~s(#{method}))} operation available at #{conn.request_path}")
        |> halt()
    end
  end
  defp extract_operation(%Conn{params: params} = conn, operation_key) do
    # Extract operation based on selected operation id
    schema = conn.private[:libswagger_schema]
    case get_in(params, [operation_key]) do
      nil ->
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(400, "missing required parameter '#{operation_key}'")
        |> halt()
      val ->
        ops = schema.paths
        |> Enum.flat_map(fn {_, e} -> Enum.map(e.operations, fn {_, op} -> {op.id, {e, op}} end) end)
        |> Enum.into(%{})
        case Map.get(ops, val) do
          nil ->
            conn
            |> put_resp_content_type("text/plain")
            |> send_resp(400, "operation not found: '#{val}'")
            |> halt()
          {%Endpoint{} = e, %Operation{} = op} ->
            conn = put_private(conn, :libswagger_endpoint, e)
            conn = put_private(conn, :libswagger_operation, op)
            {:ok, conn}
        end
    end
  end
end
