defmodule SwaggerPlugLoadSchemaTest do
  use ExUnit.Case, async: true
  use Plug.Test

  alias Swagger.Schema
  alias Swagger.Schema.{Endpoint, Operation}

  @with_opts Swagger.Plug.LoadSchema.init(schema_key: "__schema", operation_key: "__operation")
  @without_opts Swagger.Plug.LoadSchema.init(schema_key: "__schema")
  @parser_opts Plug.Parsers.init([parsers: [:json], pass: ["*/*"], json_decoder: Poison])

  describe "when providing an operation key" do
    test "a schema, endpoint, and operation are successfully bound" do
      body = %{__schema: "db.yaml", __operation: "listUsers", solution_id: "foobar"}
      conn = conn(:post, "/users", Poison.encode!(body))
            |> put_req_header("content-type", "application/json")

      conn = Plug.Parsers.call(conn, @parser_opts)
      conn = Swagger.Plug.LoadSchema.call(conn, @with_opts)

      refute conn.state == :sent
      assert %Schema{} = conn.private[:libswagger_schema]
      assert %Endpoint{name: "/{solution_id}/users"} = conn.private[:libswagger_endpoint]
      assert %Operation{id: "listUsers"} = conn.private[:libswagger_operation]
    end

    test "a missing schema key will produce a 400 error" do
      conn = conn(:post, "/users", "")
      |> put_req_header("content-type", "application/json")

      conn = Plug.Parsers.call(conn, @parser_opts)
      conn = Swagger.Plug.LoadSchema.call(conn, @with_opts)

      assert conn.state == :sent
      assert conn.status == 400
      assert String.contains?(conn.resp_body, "missing required parameter '__schema'")
    end

    test "a missing schema will produce a 400 error" do
      body = %{__schema: "notfound.yaml", __operation: "listUsers"}
      conn = conn(:post, "/users", Poison.encode!(body))
      |> put_req_header("content-type", "application/json")

      conn = Plug.Parsers.call(conn, @parser_opts)
      conn = Swagger.Plug.LoadSchema.call(conn, @with_opts)

      assert conn.state == :sent
      assert conn.status == 400
      assert String.contains?(conn.resp_body, "unable to load schema 'notfound.yaml': doesn't exist")
    end

    test "a missing operation key will produce a 400 error" do
      body = %{__schema: "db.yaml"}
      conn = conn(:post, "/users", Poison.encode!(body))
      |> put_req_header("content-type", "application/json")

      conn = Plug.Parsers.call(conn, @parser_opts)
      conn = Swagger.Plug.LoadSchema.call(conn, @with_opts)

      assert conn.state == :sent
      assert conn.status == 400
      assert String.contains?(conn.resp_body, "missing required parameter '__operation'")
    end

    test "a missing operation will produce a 400 error" do
      body = %{__schema: "db.yaml", __operation: "notFound"}
      conn = conn(:post, "/users", Poison.encode!(body))
      |> put_req_header("content-type", "application/json")

      conn = Plug.Parsers.call(conn, @parser_opts)
      conn = Swagger.Plug.LoadSchema.call(conn, @with_opts)

      assert conn.state == :sent
      assert conn.status == 400
      assert String.contains?(conn.resp_body, "operation not found: 'notFound'")
    end
  end

  describe "when inferring an operation based on request method and path" do
    test "a schema, endpoint, and operation are successfully bound" do
      conn = conn(:get, "/foobar/users?__schema=db.yaml")

      conn = Plug.Parsers.call(conn, @parser_opts)
      conn = Swagger.Plug.LoadSchema.call(conn, @without_opts)

      refute conn.state == :sent
      assert %Schema{} = conn.private[:libswagger_schema]
      assert %Endpoint{name: "/{solution_id}/users"} = conn.private[:libswagger_endpoint]
      assert %Operation{id: "listUsers"} = conn.private[:libswagger_operation]
    end

    test "a missing endpoint will produce a 400 error" do
      conn = conn(:post, "/users?__schema=db.yaml", "")
      |> put_req_header("content-type", "application/json")

      conn = Plug.Parsers.call(conn, @parser_opts)
      conn = Swagger.Plug.LoadSchema.call(conn, @without_opts)

      assert conn.state == :sent
      assert conn.status == 400
      assert String.contains?(conn.resp_body, "no operation found which matches `POST /users`")
    end

    test "a missing operation will produce a 400 error" do
      conn = conn(:delete, "/foobar/users?__schema=db.yaml", "")
      |> put_req_header("content-type", "application/json")

      conn = Plug.Parsers.call(conn, @parser_opts)
      conn = Swagger.Plug.LoadSchema.call(conn, @without_opts)

      assert conn.state == :sent
      assert conn.status == 400
      assert String.contains?(conn.resp_body, "no DELETE operation available at /foobar/users")
    end
  end
end
