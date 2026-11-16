defmodule Emergencias.Logistica.Persistencia do
  @moduledoc "Persistencia en texto plano (una línea por registro, campos separados por |)."

  def limpiar(s), do: s |> to_string() |> String.replace(["|", "\n", "\r"], " ")

  def leer(nil, _archivo), do: []

  def leer(dir, archivo) do
    case File.read(Path.join(dir, archivo)) do
      {:ok, txt} -> String.split(txt, "\n", trim: true)
      {:error, _} -> []
    end
  end

  def guardar(nil, _archivo, _lineas), do: :ok

  def guardar(dir, archivo, lineas) do
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, archivo), Enum.map_join(lineas, "", &(&1 <> "\n")))
  end

  def agregar(nil, _archivo, _lineas), do: :ok

  def agregar(dir, archivo, lineas) do
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, archivo), Enum.map_join(lineas, "", &(&1 <> "\n")), [:append])
  end
end
