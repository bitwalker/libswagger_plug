defmodule Swagger.Plug.Serializer do
  @moduledoc false

  defmacro __using__(_) do
    quote do
      @behaviour Swagger.Plug.Serializer
    end
  end

  @callback serialize(body :: Map.t) :: {:ok, binary} | {:error, term}

  @default_serializers %{
    "application/json" => Swagger.Plug.Serializers.JSON,
    "application/x-www-form-urlencoded" => Swagger.Plug.Serializers.UrlEncoded,
  }

  def serialize(content_type, body) do
    serializers = Application.get_env(:libswagger_plug, :serializers, @default_serializers)
    case get_in(serializers, [content_type]) do
      nil ->
        {:error, {:unsupported_content_type, content_type, "unable to encode body", body}}
      serializer when is_atom(serializer) ->
        serializer.serialize(body)
    end
  end
end
