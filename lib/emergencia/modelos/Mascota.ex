defmodule Mascota do
  @moduledoc """
  Modelo para la gestión de reportes de mascotas perdidas y encontradas.
  """

  @enforce_keys [:id, :tipo_reporte, :especie, :zona, :contacto]
  defstruct [
    :id,
    :tipo_reporte,    # :perdida o :encontrada
    :especie,
    :nombre,          # nil si es desconocido
    :caracteristicas,
    :color,
    :tamano,
    :zona,
    :contacto,
    estado: :activa   # :activa, :posible_coincidencia, :resuelta
  ]

  @doc """
  Crea un nuevo reporte validando que existan los campos obligatorios.
  Retorna {:ok, mascota} o {:error, motivo}.
  """
  def crear(datos) when is_map(datos) do
    campos_requeridos = [:id, :tipo_reporte, :especie, :zona, :contacto]

    # Verificamos si falta algún campo obligatorio
    faltantes = Enum.reject(campos_requeridos, fn campo -> Map.has_key?(datos, campo) end)

    if Enum.empty?(faltantes) do
      mascota = struct(__MODULE__, datos)
      {:ok, mascota}
    else
      {:error, "Faltan campos obligatorios: #{inspect(faltantes)}"}
    end
  end

  @doc """
  Filtra una lista de mascotas basándose en un mapa de criterios.
  Ejemplo: %{especie: "perro", zona: "norte", estado: :activa}
  """
  def filtrar(lista_mascotas, criterios) when is_map(criterios) do
    resultados = Enum.filter(lista_mascotas, fn mascota ->
      Enum.all?(criterios, fn {clave, valor} ->
        Map.get(mascota, clave) == valor
      end)
    end)

    {:ok, resultados}
  end
end
