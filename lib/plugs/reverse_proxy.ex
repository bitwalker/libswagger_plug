defmodule Swagger.Plug.ReverseProxy do
  @moduledoc """
  This plug is responsible for executing an HTTP request to another
  service based on an incoming request. It needs a Swagger schema, loaded
  by the LoadSchema plug, as well as parameters to fulfill those required
  for the remote service call based on the path and operation selected in
  the incoming request, these parameters are loaded by the ExtractParams plug.

  LoadSchema sets `libswagger_schema`, `libswagger_endpoint`, and `libswagger_operation`
  properties in the connection's private state. These are used to identify the specific
  operation the inbound request is attempting to execute. ExtractParams will in turn
  determine what parameters are required to execute the remote call for that operation,
  and attempt to locate them in the inbound request, either in the path, query string,
  headers, or body (if the body has already been parsed). If the parameters cannot be
  bound, ExtractParams will reject the request. Once we reach this plug, the actual request
  will be constructed based on this information, and the response directly proxied back
  to the client
  """
  import Plug.Conn
  require Logger
  alias Swagger.Schema.Parameter

  def init(options) do
    options
  end

  def call(conn, opts) do
    schema = conn.private[:libswagger_schema]
    unless schema do
      raise "the ReverseProxy plug requires that the LoadSchema plug comes before it"
    end
    endpoint  = conn.private[:libswagger_endpoint]
    operation = conn.private[:libswagger_operation]
    case extract_parameters(endpoint, operation, conn) do
      {:error, {:missing_required_parameter, param}} ->
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(400, "missing required parameter '#{param}'")
        |> halt()
      {:error, {:mismatched_parameter_type, name, val, type}} ->
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(400, "wrong type for parameter '#{name}', expected '#{type}', got '#{inspect val}'")
        |> halt()
      {:error, reason} ->
        raise "error occurred when extracting parameters for reverse proxy: #{inspect reason}"
      extracted when is_map(extracted) ->
        execute_request(conn, schema, endpoint, operation, extracted, opts)
    end
  end

  defp execute_request(conn, schema, endpoint, operation, params, options) do
    case Swagger.Client.request(conn, schema, endpoint, operation, params, options) do
      {:error, conn, {:client_error, reason}} ->
        Logger.error "[libswagger_plug] client error: #{reason}"
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(500, "server error")
        |> halt()
      {:error, conn, {:remote_request_error, _}} ->
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(500, "server error")
        |> halt()
      {:error, conn, reason} ->
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(400, "schema violation: #{inspect reason}")
        |> halt()
      {:ok, %{state: state} = conn, _req} when state == :sent ->
        halt(conn)
      {:ok, conn, %{response: resp} = req} ->
        conn
        |> put_resp_content_type(req.content_type)
        |> send_resp(resp.status, resp.body)
    end
  end

  defp extract_parameters(endpoint, operation, conn) do
    with {:ok, ep} <- do_extract_parameters(endpoint.parameters, conn.params),
         {:ok, op} <- do_extract_parameters(operation.parameters, conn.params),
      do: Map.merge(%{extra: conn.params}, merge_parameters(ep, op))
  end

  defp do_extract_parameters(parameters, values) do
    default = %{header: %{}, query: %{}, path: %{}, formdata: %{}, body: nil}
    Enum.reduce(parameters, {:ok, default}, fn
      _, {:error, _} = err ->
        err
      {_name, %Parameter.BodyParam{schema: %{"properties" => props}}}, {:ok, acc} ->
        body = Enum.reduce(props, %{}, fn {name, _}, acc -> Map.put(acc, name, Map.get(values, name)) end)
        {:ok, put_in(acc, [:body], body)}
      {name, %{__struct__: type, required?: required?} = p}, {:ok, acc} ->
        case Map.get(values, name) do
          nil when required? -> {:error, {:missing_required_parameter, name}}
          nil -> {:ok, acc}
          val ->
            shorttype = get_shorttype(type)
            case Map.get(p, :spec) do
              nil ->
                {:ok, put_in(acc, [shorttype, name], val)}
              %{type: type} ->
                {:ok, put_in(acc, [shorttype, name], convert_val(val, type))}
            end
        end
    end)
  end

  defp merge_parameters(a, b) when is_map(a) and is_map(b) do
    Map.merge(a, b, fn _k, v1, v2 ->
      merge_parameters(v1, v2)
    end)
  end
  defp merge_parameters(_a, b), do: b

  defp get_shorttype(Parameter.HeaderParam),   do: :header
  defp get_shorttype(Parameter.QueryParam),    do: :query
  defp get_shorttype(Parameter.PathParam),     do: :path
  defp get_shorttype(Parameter.FormDataParam), do: :formdata
  defp get_shorttype(Parameter.BodyParam),     do: :body


  defp convert_val(val, :string) when is_binary(val),   do: val
  defp convert_val(val, :number) when is_integer(val),  do: Integer.to_string(val)
  defp convert_val(val, :number) when is_float(val),    do: Float.to_string(val)
  defp convert_val(val, :integer) when is_integer(val), do: Integer.to_string(val)
  defp convert_val(val, :boolean) when is_boolean(val), do: to_string(val)
  defp convert_val(_val, type), do: raise("encoding of '#{type}' values is not yet supported!")

end
