defmodule Swagger.Client.HTTP do
  use Tesla

  defp debug_mode?, do: Application.get_env(:libswagger_plug, :debug, false)

  def create() do
    middleware = [
      cond do
        debug_mode? -> {Tesla.Middleware.Logger, []}
        :else       -> {Tesla.Middleware.DebugLogger, []}
      end,
      # {Tesla.Middleware.Fuse, []}
    ]
    Tesla.build_client(middleware)
  end
end
