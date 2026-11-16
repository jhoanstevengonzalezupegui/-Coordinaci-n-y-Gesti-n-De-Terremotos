defmodule Emergencia.Persistencia do
  @moduledoc """
  Capa de persistencia en archivos de texto plano dentro del directorio data/.
  Cada entidad se almacena en su propio archivo .txt delimitado por '|'.
  """

  @directorio_default "data"

  def guardar_lista(archivo, registros, fun_a_linea, dir \\ @directorio_default) do
    File.mkdir_p!(dir)
    ruta = Path.join(dir, archivo)

    contenido =
      registros
      |> Enum.map(fun_a_linea)
      |> Enum.join("\n")

    texto_final = if contenido == "", do: "", else: contenido <> "\n"

    case File.write(ruta, texto_final) do
      :ok -> :ok
      {:error, razon} -> {:error, razon}
    end
  end

  def cargar_lista(archivo, fun_desde_linea, dir \\ @directorio_default) do
    File.mkdir_p!(dir)
    ruta = Path.join(dir, archivo)

    case File.read(ruta) do
      {:ok, contenido} ->
        registros =
          contenido
          |> String.split("\n", trim: true)
          |> Enum.reduce([], fn linea, acc ->
            case fun_desde_linea.(linea) do
              {:ok, entidad} -> [entidad | acc]
              {:error, _} -> acc
            end
          end)
          |> Enum.reverse()

        {:ok, registros}

      {:error, :enoent} ->
        {:ok, []}

      {:error, razon} ->
        {:error, razon}
    end
  end
end
