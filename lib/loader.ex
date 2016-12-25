defmodule Swagger.Schema.Loader do

  alias Swagger.Schema
  alias Swagger.Schema.Loader.FileLoader

  defmacro __using__(_) do
    quote do
      @behaviour Swagger.Schema.Loader
    end
  end

  @type key :: term
  @type reason :: term

  @callback load(key) :: {:ok, Schema.t} | {:error, reason}

  @spec load(key) :: {:ok, Schema.t} | {:error, reason}
  def load(key), do: loader_module().load(key)


  defp loader_module(), do: Application.get_env(:libswagger_plug, :schema_loader, FileLoader)
end
