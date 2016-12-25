defmodule Swagger.Plug.Serializers.UrlEncoded do
  @moduledoc false
  use Swagger.Plug.Serializer

  def serialize(body) when is_map(body) do
    {:ok, URI.encode_query(body)}
  end
end
