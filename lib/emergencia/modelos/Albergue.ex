defmodule Albergue do
  @moduledoc """
  Modelo para la gestión de albergues, capacidades y control de ocupación.
  """

  @enforce_keys [:codigo, :nombre, :zona, :capacidad_maxima]
  defstruct [
    :codigo,
    :nombre,
    :zona,
    :capacidad_maxima,
    ocupacion_actual: 0,
    personas: [] # Lista de documentos de personas alojadas
  ]

  def crear(datos) when is_map(datos) do
    campos_requeridos = [:codigo, :nombre, :zona, :capacidad_maxima]
    faltantes = Enum.reject(campos_requeridos, fn campo -> Map.has_key?(datos, campo) end)

    cond do
      not Enum.empty?(faltantes) ->
        {:error, "Faltan campos obligatorios: #{inspect(faltantes)}"}

      datos.capacidad_maxima <= 0 ->
        {:error, "La capacidad máxima debe ser mayor a 0"}

      true ->
        {:ok, struct(__MODULE__, datos)}
    end
  end

  def cupos_disponibles(%Albergue{capacidad_maxima: cap, ocupacion_actual: ocup}) do
    cap - ocup
  end
end
