defmodule Persona do
  @moduledoc """
  Modelo para la gestión de personas (familiares y voluntarios).
  """

  # Definimos los campos obligatorios para crear una persona
  @enforce_keys [:documento, :nombre, :telefono]
  defstruct [
    :documento,
    :nombre,
    :telefono,
    :rol # Puede ser :familiar o :voluntario
  ]

  @doc """
  Crea un nuevo registro de persona validando sus campos.
  """
  def crear(datos) when is_map(datos) do
    campos_requeridos = [:documento, :nombre, :telefono]

    faltantes = Enum.reject(campos_requeridos, fn campo -> Map.has_key?(datos, campo) end)

    if Enum.empty?(faltantes) do
      persona = struct(__MODULE__, datos)
      {:ok, persona}
    else
      {:error, "Faltan campos obligatorios: #{inspect(faltantes)}"}
    end
  end
end
