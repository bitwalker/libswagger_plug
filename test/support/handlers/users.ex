defmodule Swagger.Test.Handlers.UsersHandler do

  def init(_transport, req, opts) do
    {:ok, req, opts}
  end

  def handle(req, state) do
    {method, req} = :cowboy_req.method(req)
    {bindings, req} = :cowboy_req.bindings(req)
    handler = route(method, bindings)
    {:ok, req} = handler.(req)
    {:ok, req, state}
  end

  def terminate(_reason, _, _) do
    :ok
  end

  ## Private functions

  defp route("POST", [solution_id: _sid]),                     do: &create_user/1
  defp route("POST", [{:security_type, "basic"} | _]),         do: basic_auth(&create_user/1)
  defp route("POST", [{:security_type, "apikey-header"} | _]), do: apikey_header_auth(&create_user/1)
  defp route("POST", [{:security_type, "apikey-query"} | _]),  do: apikey_query_auth(&create_user/1)
  defp route("POST", [email: email, solution_id: _sid]),        do: &update_user(email, &1, :json)
  defp route("PUT",  [email: email, solution_id: _sid]),        do: &update_user(email, &1, :urlencoded)
  defp route("GET",  [solution_id: _sid]),                      do: &list_users/1
  defp route("GET",  [email: email, solution_id: _sid]),        do: &get_user(email, &1)
  defp route(method, bindings) do
    IO.inspect {:route, method, bindings}
    &(:cowboy_req.reply(404, [{"content-type", "text/plain"}], "not found", &1))
  end

  # Wrap another handler with basic auth
  defp basic_auth(callback) do
    fn req ->
      case :cowboy_req.parse_header("authorization", req) do
        {:ok, {"basic", {"user", "pass"}}, req} ->
          callback.(req)
        {:ok, _other, req} ->
          not_authorized(req)
      end
    end
  end
  # Wrap another handler with api key auth (in header)
  defp apikey_header_auth(callback) do
    fn req ->
      case :cowboy_req.header("authorization", req) do
        {"letmein", req} ->
          callback.(req)
        {_other, req} ->
          not_authorized(req)
      end
    end
  end
  # Wrap another handler with api key auth (in query)
  defp apikey_query_auth(callback) do
    fn req ->
      case :cowboy_req.qs_val("api-key", req) do
        {"letmein", req} ->
          callback.(req)
        {_, req} ->
          not_authorized(req)
      end
    end
  end

  defp create_user(req) do
    {:ok, body, req} = :cowboy_req.body(req)
    params = Poison.decode!(body)
    :ets.insert(:libswagger_plug_users, {params["email"], params})
    :cowboy_req.reply(200, [{"content-type", "application/json"}], Poison.encode!(params), req)
  end

  defp update_user(_email, req, :json) do
    {:ok, body, req} = :cowboy_req.body(req)
    user = Poison.decode!(body)
    :cowboy_req.reply(200, [{"content-type", "application/json"}], Poison.encode!(user), req)
  end
  defp update_user(_email, req, :urlencoded) do
    {:ok, body, req} = :cowboy_req.body(req)
    user = URI.decode_query(body)
    :cowboy_req.reply(200, [{"content-type", "application/json"}], Poison.encode!(user), req)
  end

  defp list_users(req) do
    users = Enum.map(:ets.tab2list(:libswagger_plug_users), fn {_k, u} -> u end)
    :cowboy_req.reply(200, [{"content-type", "application/json"}], Poison.encode!(users), req)
  end

  defp get_user(email, req) do
    case :ets.lookup(:libswagger_plug_users, email) do
      [] ->
        :cowboy_req.reply(404, [{"content-type", "application/json"}], "null", req)
      [{_, u}] ->
        :cowboy_req.reply(200, [{"content-type", "application/json"}], Poison.encode!(u), req)
    end
  end

  defp not_authorized(req) do
    :cowboy_req.reply(401, [{"content-type", "text/plain"}], "unauthorized!", req)
  end
end
