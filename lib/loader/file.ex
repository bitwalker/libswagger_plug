defmodule Swagger.Schema.Loader.FileLoader do
  @moduledoc false
  use Swagger.Schema.Loader

  def load(path) when is_binary(path) do
    resolved = resolve_path(path)
    case File.exists?(resolved) do
      true  -> Swagger.parse_file(resolved)
      false -> {:error, "doesn't exist"}
    end
  end

  defp resolve_path(path) do
    resolved = case get_config(:root_dir) do
      nil -> path
      base_path -> Path.join(base_path, path)
    end
    case get_config(:extension) do
      nil -> resolved
      ext -> Path.expand(resolved <> ext)
    end
  end

  defp get_config(opt, default \\ nil) do
    options = Application.get_env(:libswagger_plug, __MODULE__, [])
    Keyword.get(options, opt, default)
  end
end
