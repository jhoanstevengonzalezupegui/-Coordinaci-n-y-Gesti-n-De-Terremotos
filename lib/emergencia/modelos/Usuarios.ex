defmodule Usuario do
  @moduledoc """
  Modelo para la gestión de usuarios, roles y control de sesión.
  """

  @enforce_keys [:username, :password, :nombre_completo, :tipo, :zona_principal]
  defstruct [
    :username,
    :password,
    :nombre_completo,
    :tipo,           # :ciudadano, :voluntario, :coordinador, :administrador
    :zona_principal,
    activo: false,
    historial: []
  ]

  def crear(datos) when is_map(datos) do
    campos_requeridos = [:username, :password, :nombre_completo, :tipo, :zona_principal]
    faltantes = Enum.reject(campos_requeridos, fn campo -> Map.has_key?(datos, campo) end)

    if Enum.empty?(faltantes) do
      usuario = struct(__MODULE__, datos)
      {:ok, usuario}
    else
      {:error, "Faltan campos obligatorios: #{inspect(faltantes)}"}
    end
  end

  def registrar_actividad(usuario, accion) do
    evento = %{accion: accion, fecha: NaiveDateTime.utc_now()}
    %{usuario | historial: [evento | usuario.historial]}
  end
end
