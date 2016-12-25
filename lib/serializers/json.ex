defmodule Swagger.Plug.Serializers.JSON do
  @moduledoc false
  use Swagger.Plug.Serializer

  def serialize(body) when is_map(body) do
    Poison.encode(body)
  end
end
