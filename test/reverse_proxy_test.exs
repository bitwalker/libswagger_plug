defmodule SwaggerPlugReverseProxyTest do
  use ExUnit.Case, async: true
  use Plug.Test

  alias Swagger.Test.Handlers.UsersHandler

  @parser_opts Plug.Parsers.init([parsers: [:json], pass: ["*/*"], json_decoder: Poison])
  @load_schema_opts Swagger.Plug.LoadSchema.init(schema_key: "__schema", operation_key: "__operation")
  @proxy_opts Swagger.Plug.ReverseProxy.init([])

  setup_all do
    :ets.new(:libswagger_plug_users, [:set, :public, :named_table, keypos: 1])
    {:ok, _} = Application.ensure_all_started(:cowboy)
    {:ok, _server} = :cowboy.start_http(:http, 100, [port: 7000], [
          env: [
            dispatch: :cowboy_router.compile([
              {:'_', [
                 {'/api/v1/:solution_id/users', UsersHandler, []},
                 {'/api/v1/:solution_id/users/:email', UsersHandler, []},
                 {'/api/v1/:solution_id/secured/:security_type/users', UsersHandler, []}
                ]}
            ])
          ]
        ])
    certs = Path.join([__DIR__, "support", "certs"])
    {:ok, _server2} = :cowboy.start_https(:https, 100, [
          port: 7001,
          cacertfile: '#{Path.join(certs, "test-ca.crt")}',
          certfile: '#{Path.join(certs, "test.crt")}',
          keyfile: '#{Path.join(certs, "test.key")}',
        ], [
          env: [
            dispatch: :cowboy_router.compile([
              {:'_', [
                 {'/api/v1/:solution_id/users', UsersHandler, []},
                 {'/api/v1/:solution_id/users/:email', UsersHandler, []},
                 {'/api/v1/:solution_id/secured/:security_type/users', UsersHandler, []}
                ]}
            ])
          ]
        ])
    :ok
  end

  describe "basic tests" do
    test "can execute a simple reverse proxy (http)" do
      body = %{
        __schema: "db.yaml",
        __operation: "createUser",
        solution_id: "foobar",
        name: "Test User", 
        email: "test@example.com"
      }
      conn = conn(:post, "/users", Poison.encode!(body))
            |> put_req_header("content-type", "application/json")
      conn = Plug.Parsers.call(conn, @parser_opts)
      conn = Swagger.Plug.LoadSchema.call(conn, @load_schema_opts)
      conn = Swagger.Plug.ReverseProxy.call(conn, @proxy_opts)

      assert conn.state == :sent
      assert {conn.status, conn.resp_body} == {200, Poison.encode!(%{"name" => body.name, "email" => body.email})}
    end

    test "can execute a simple reverse proxy (https)" do
      body = %{
        __schema: "db_secure.yaml",
        __operation: "createUser",
        solution_id: "foobar",
        name: "Test User", 
        email: "test@example.com"
      }
      conn = conn(:post, "/users", Poison.encode!(body))
            |> put_req_header("content-type", "application/json")
      conn = Plug.Parsers.call(conn, @parser_opts)
      conn = Swagger.Plug.LoadSchema.call(conn, @load_schema_opts)
      conn = Swagger.Plug.ReverseProxy.call(conn, @proxy_opts)

      assert conn.state == :sent
      assert {conn.status, conn.resp_body} == {200, Poison.encode!(%{"name" => body.name, "email" => body.email})}
    end
  end


  describe "security tests" do
    test "can authenticate to a basic-auth secured endpoint" do
      body = %{
        __schema: "db.yaml",
        __operation: "createUserSecuredBasic",
        solution_id: "foobar",
        name: "Test User", 
        email: "test@example.com"
      }
      conn = conn(:post, "/users", Poison.encode!(body))
             |> put_req_header("authorization", "Basic " <> Base.encode64("user:pass"))
             |> put_req_header("content-type", "application/json")
      conn = Plug.Parsers.call(conn, @parser_opts)
      conn = Swagger.Plug.LoadSchema.call(conn, @load_schema_opts)
      conn = Swagger.Plug.ReverseProxy.call(conn, @proxy_opts)

      assert conn.state == :sent
      assert {conn.status, conn.resp_body} == {200, Poison.encode!(%{"name" => body.name, "email" => body.email})}
    end

    test "can authenticate to an api key-based auth (header) secured endpoint" do
      body = %{
        __schema: "db.yaml",
        __operation: "createUserSecuredApiKeyHeader",
        solution_id: "foobar",
        name: "Test User", 
        email: "test@example.com"
      }
      conn = conn(:post, "/users", Poison.encode!(body))
             |> put_req_header("authorization", "letmein")
             |> put_req_header("content-type", "application/json")
      conn = Plug.Parsers.call(conn, @parser_opts)
      conn = Swagger.Plug.LoadSchema.call(conn, @load_schema_opts)
      conn = Swagger.Plug.ReverseProxy.call(conn, @proxy_opts)

      assert conn.state == :sent
      assert {conn.status, conn.resp_body} == {200, Poison.encode!(%{"name" => body.name, "email" => body.email})}
    end

    test "can authenticate to an api key-based auth (query) secured endpoint" do
      body = %{
        __schema: "db.yaml",
        __operation: "createUserSecuredApiKeyQuery",
        solution_id: "foobar",
        name: "Test User", 
        email: "test@example.com"
      }
      conn = conn(:post, "/users?api-key=letmein", Poison.encode!(body))
             |> put_req_header("content-type", "application/json")
      conn = Plug.Parsers.call(conn, @parser_opts)
      conn = Swagger.Plug.LoadSchema.call(conn, @load_schema_opts)
      conn = Swagger.Plug.ReverseProxy.call(conn, @proxy_opts)

      assert conn.state == :sent
      assert {conn.status, conn.resp_body} == {200, Poison.encode!(%{"name" => body.name, "email" => body.email})}
    end
  end

  describe "serialization tests" do
    test "can submit application/x-www-form-urlencoded requests" do
      body = %{
        __schema: "db.yaml",
        __operation: "updateUser",
        solution_id: "foobar",
        name: "Updated User",
        email: "test@example.com"
      }
      conn = conn(:post, "/users", Poison.encode!(body))
      |> put_req_header("content-type", "application/json")
      conn = Plug.Parsers.call(conn, @parser_opts)
      conn = Swagger.Plug.LoadSchema.call(conn, @load_schema_opts)
      conn = Swagger.Plug.ReverseProxy.call(conn, @proxy_opts)

      assert conn.state == :sent
      updated = Poison.encode!(%{name: body.name, email: body.email})
      assert {conn.status, conn.resp_body} == {200, updated}
    end

    test "can submit application/json requests" do
      body = %{
        __schema: "db.yaml",
        __operation: "updateUserJson",
        solution_id: "foobar",
        name: "Updated User",
        email: "test@example.com"
      }
      conn = conn(:post, "/users", Poison.encode!(body))
      |> put_req_header("content-type", "application/json")
      conn = Plug.Parsers.call(conn, @parser_opts)
      conn = Swagger.Plug.LoadSchema.call(conn, @load_schema_opts)
      conn = Swagger.Plug.ReverseProxy.call(conn, @proxy_opts)

      assert conn.state == :sent
      updated = Poison.encode!(%{name: body.name, email: body.email})
      assert {conn.status, conn.resp_body} == {200, updated}
    end
  end
end
