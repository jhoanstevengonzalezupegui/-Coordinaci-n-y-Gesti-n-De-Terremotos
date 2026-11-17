defmodule Persistencia do
  @moduledoc """
  Módulo genérico para guardar y leer la información del sistema en archivos de texto plano (.txt).
  """

  @doc """
  Recibe la ruta del archivo (ej. "data/mascotas.txt") y la lista de datos.
  Lo guarda como texto plano y retorna una tupla.
  """
  def guardar(ruta_archivo, lista_datos) do
    # Convertimos la lista de datos a texto plano formateado
    texto = inspect(lista_datos, limit: :infinity, pretty: true)

    case File.write(ruta_archivo, texto) do
      :ok ->
        {:ok, "Datos guardados correctamente en #{ruta_archivo}"}

      {:error, razon} ->
        {:error, "No se pudo guardar el archivo. Razón: #{inspect(razon)}"}
    end
  end

  @doc """
  Lee un archivo de texto y convierte su contenido de vuelta a estructuras de Elixir.
  Si el archivo no existe (por ejemplo, la primera vez que arranca), retorna una lista vacía.
  """
  def cargar(ruta_archivo) do
    case File.read(ruta_archivo) do
      {:ok, ""} ->
        # Si el archivo está vacío
        {:ok, []}

      {:ok, texto} ->
        # Convertimos el texto plano de vuelta a la lista de datos de Elixir
        {datos, _binding} = Code.eval_string(texto)
        {:ok, datos}

      {:error, :enoent} ->
        # :enoent significa que el archivo aún no existe. Devolvemos lista vacía.
        {:ok, []}

      {:error, razon} ->
        {:error, "Error al leer el archivo. Razón: #{inspect(razon)}"}
    end
  end
end
