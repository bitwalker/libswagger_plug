defmodule Swagger.Client do
  require Logger
  alias Plug.Conn
  import Plug.Conn

  alias Swagger.Client.HTTP
  alias Swagger.Schema
  alias Swagger.Schema.{Endpoint, Operation, Security}

  def request(%Conn{} = conn, %Schema{} = schema, %Endpoint{} = endpoint, %Operation{} = operation, params) do
    [content_type] = get_req_header(conn, "content-type")

    with {:ok, security}     <- get_security(conn, schema, operation, params),
         {:ok, content_type} <- clean_content_type(content_type),
         {:ok, target_content_type} <- get_content_type_for_op(schema, operation, content_type),
         {:ok, path}         <- build_path(schema.schemes, operation.schemes, schema.host <> schema.base_path, endpoint.name, params),
         {:ok, headers}      <- build_headers(conn.req_headers, security.headers, content_type, params),
         {:ok, query}        <- build_query(security.query, params),
         {:ok, body, _conn}  <- build_body(conn, schema, operation, content_type, target_content_type, params) do
      dispatch(%{
        endpoint: endpoint,
        operation: operation,
        method: String.to_atom(String.downcase(operation.name)),
        path: path,
        content_type: target_content_type,
        headers: headers,
        query: query,
        body: body})
    end
  end

  defp dispatch(%{body: body, content_type: content_type} = req) do
    client = Swagger.Client.HTTP.create()
    client_opts = [
      method: req.method,
      url: req.path,
      query: req.query,
      headers: req.headers,
      body: body
    ]
    try do
      response = Swagger.Client.HTTP.request(client, client_opts)
      req = Map.put(req, :response, response)
      case content_type do
        "application/json" ->
          response_schema = Map.get(req.operation.responses, response.status, Map.get(req.operation.responses, :default))
          case response_schema do
            nil -> req
            _ ->
              valid? = ExJsonSchema.Validator.validate(response_schema, Poison.decode!(response.body))
              unless valid? == :ok do
                Logger.warn "[libswagger] response received for #{req.method} #{req.path} " <>
                  "is not valid according to the defined schema!\n" <>
                  "   #{inspect valid?}"
              end
              req
          end
        _ ->
          req
      end
    rescue
      e in [Tesla.Error] ->
        {:error, {:remote_request_error, e.message}}
    end
  end

  defp get_security(conn, %Schema{security_definitions: defs, security: global}, %Operation{security: local}, params) do
    global_reqs = Enum.into(global, %{})
    local_reqs  = Enum.into(local, %{})
    merged_reqs = Map.merge(global_reqs, local_reqs)
    Enum.reduce(merged_reqs, {:ok, %{headers: [], query: []}}, fn
      _, {:error, _} = err ->
        err
      {name, scopes}, {:ok, acc} ->
        case Map.get(defs, name) do
          nil -> {:error, {:missing_security_definition, name}}
          sec ->
            case build_security(conn, sec, scopes, params) do
              {:error, _} = err ->
                err
              {:ok, %{headers: headers, query: query}} ->
                {:ok, %{headers: Enum.concat(acc[:headers], headers), query: Enum.concat(acc[:query], query)}}
            end
        end
    end)
  end

  defp get_param_val(params, name) do
    res = params
      |> Enum.flat_map(fn {_type, vals} -> Enum.into(vals, []) end)
      |> Enum.find(fn {^name, _val} -> true; _ -> false end)
    case res do
      nil -> :error
      {_k, val} -> {:ok, val}
    end
  end

  defp build_security(_conn, %Security.None{}, _scopes, _params) do
    {:ok, %{headers: [], query: []}}
  end
  defp build_security(conn, %Security.Basic{properties: props}, _scopes, params) do
    case get_req_header(conn, "authorization") do
      ["Basic " <> basic] ->
        {:ok, %{headers: [{"authorization", "Basic " <> basic}], query: []}}
      [] ->
        with {:ok, user_key} <- Map.fetch(props, "x-user-field"),
             {:ok, pass_key} <- Map.fetch(props, "x-secret-field"),
             {:ok, username} <- get_param_val(params, user_key),
             {:ok, password} <- get_param_val(params, pass_key) do
            basic = "Basic " <> Base.encode64(username <> ":" <> password)
            {:ok, %{headers: [{"authorization", basic}], query: []}}
         else
           :error ->
            {:error, {:missing_security_header, "Authorization"}}
        end
    end
  end
  defp build_security(conn, %Security.ApiKey{in: :header, name: header_name}, _scopes, params) do
    case get_req_header(conn, String.downcase(header_name)) do
      [val] ->
        {:ok, %{headers: [{String.downcase(header_name), val}], query: []}}
      [] ->
        case get_param_val(params, header_name) do
          :error     -> {:error, {:missing_security_header, header_name}}
          {:ok, val} -> {:ok, %{headers: [{String.downcase(header_name), val}], query: []}}
        end
    end
  end
  defp build_security(conn, %Security.ApiKey{in: :query, name: query_name}, _scopes, params) do
    case get_param_val(params, query_name) do
      :error ->
        case Map.get(conn.params, query_name) do
          nil ->
            {:error, {:missing_security_query_param, query_name}}
          val ->
            {:ok, %{query: [{String.downcase(query_name), val}], headers: []}}
        end
      {:ok, val} ->
        {:ok, %{query: [{String.downcase(query_name), val}], headers: []}}
    end
  end
  defp build_security(_conn, %Security.OAuth2Implicit{id: id}, _scopes, _params),
    do: {:error, {:unsupported_security, id}}
  defp build_security(_conn, %Security.OAuth2Password{id: id}, _scopes, _params),
    do: {:error, {:unsupported_security, id}}
  defp build_security(_conn, %Security.OAuth2Application{id: id}, _scopes, _params),
    do: {:error, {:unsupported_security, id}}
  defp build_security(_conn, %Security.OAuth2AccessCode{id: id}, _scopes, _params),
    do: {:error, {:unsupported_security, id}}

  defp build_path(global_schemes, operation_schemes, base_url, path, params) do
    reified_path = params
      |> Enum.flat_map(fn {_type, vals} -> Enum.into(vals, []) end)
      |> Enum.reduce(base_url <> path, fn
        _, {:error, _} = err ->
          err
        {pname, nil}, acc ->
          replace_path_param(acc, pname, "")
        {_, val}, acc when is_map(val)->
          acc
        {_, val}, acc when is_list(val)->
          acc
        {pname, val}, acc ->
          replace_path_param(acc, pname, val)
      end)
    case reified_path do
      {:error, _} = err ->
        err
      _ ->
        case get_scheme(global_schemes, operation_schemes) do
          {:error, _} = err ->
            err
          scheme ->
            {:ok, scheme <> reified_path}
        end
    end
  end

  defp get_scheme([], []), do: "http://"
  defp get_scheme(global, []) do
    cond do
      "https" in global -> "https://"
      "http"  in global -> "http://"
      :else -> {:error, {:unsupported_scheme, global}}
    end
  end
  defp get_scheme(_, local) do
    cond do
      "https" in local -> "https://"
      "http" in local -> "http://"
      :else -> {:error, {:unsupported_scheme, local}}
    end
  end

  defp build_headers(_request_headers, security_headers, content_type, params) do
    default_headers = [{"content-type", content_type}]
    params.header
    |> Enum.reduce([], fn
      _, {:error, _} = err ->
        err
      {_pname, nil}, acc ->
        acc
      {pname, val}, acc ->
        [{pname, val} | acc]
    end) |> case do
      {:error, _} = err ->
        err
      new_headers ->
        {:ok, Enum.concat(default_headers, Enum.concat(new_headers, security_headers))}
    end
  end

  defp build_query(security_query, params) do
    params.query
    |> Enum.reduce(security_query, fn
      _, {:error, _} = err ->
        err
      {_pname, nil}, acc ->
        acc
      {pname, val}, acc ->
        [{pname, val} | acc]
    end) |> case do
      {:error, _} = err -> err
      new_query -> {:ok, new_query}
    end
  end

  defp build_body(conn, %Schema{} = schema, %Operation{} = op, content_type, target_content_type, params, acc \\ "") do
    case read_body(conn) do
      {:ok, body, conn}   -> do_build_body(conn, schema, op, content_type, target_content_type, params, acc <> body)
      {:more, body, conn} -> build_body(conn, schema, op, content_type, target_content_type, params, acc <> body)
      {:error, _reason} ->
        do_build_body(conn, schema, op, content_type, target_content_type, params, nil)
    end
  end
  defp do_build_body(conn, _schema, _operation, _content_type, target_content_type, params, body) when body in [nil, ""] do
    # body has already been read
    body = params
      |> Enum.filter(fn {type, _} -> type in [:body, :formdata] end)
      |> Enum.flat_map(fn {_type, vals} -> Enum.into(vals, []) end)
      |> Enum.into(%{})
    case serialize(target_content_type, body) do
      {:ok, serialized} -> {:ok, serialized, conn}
      {:error, _} = err -> err
    end
  end
  defp do_build_body(conn, _schema, _operation, _content_type, _target_content_type, _params, body) when is_binary(body) do
    {:ok, body, conn}
  end

  defp clean_content_type(content_type) do
    {:ok, content_type
      |> String.split(";")
      |> List.first()
      |> String.downcase()}
  end

  defp get_content_type_for_op(%Schema{consumes: []}, %Operation{consumes: []}, provided_content_type) do
    {:ok, provided_content_type}
  end
  defp get_content_type_for_op(%Schema{consumes: sc}, %Operation{consumes: []}, provided_content_type) do
    cond do
      provided_content_type in sc ->
        {:ok, provided_content_type}
      :else ->
        {:ok, List.first(sc)}
    end
  end
  defp get_content_type_for_op(%Schema{}, %Operation{consumes: oc}, provided_content_type) do
    cond do
      provided_content_type in oc ->
        {:ok, provided_content_type}
      :else ->
        {:ok, List.first(oc)}
    end
  end

  defp serialize(content_type, body) do
    Swagger.Plug.Serializer.serialize(content_type, body)
  end

  defp replace_path_param(path, key, value) do
    Regex.replace(~r/\{#{key}\}/, path, "#{value}")
  end
end
