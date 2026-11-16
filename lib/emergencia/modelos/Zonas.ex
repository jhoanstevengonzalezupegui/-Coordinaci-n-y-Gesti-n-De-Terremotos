defmodule Zona do
  @moduledoc """
  Modelo para la gestión de zonas afectadas, sectores y puntos de atención.
  """

  @enforce_keys [:codigo, :nombre, :nivel]
  defstruct [
    :codigo,
    :nombre,
    :nivel,                 # :critico, :alto, :medio, :bajo
    personas_afectadas: 0,
    sectores: []            # Lista de mapas: %{nombre: "...", puntos: ["Punto 1", ...]}
  ]

  def crear(datos) when is_map(datos) do
    campos_requeridos = [:codigo, :nombre, :nivel]
    faltantes = Enum.reject(campos_requeridos, fn campo -> Map.has_key?(datos, campo) end)

    cond do
      not Enum.empty?(faltantes) ->
        {:error, "Faltan campos obligatorios: #{inspect(faltantes)}"}

      Map.get(datos, :personas_afectadas, 0) < 0 ->
        {:error, "La cantidad de personas afectadas no puede ser negativa"}

      true ->
        {:ok, struct(__MODULE__, datos)}
    end
  end

  # =========================================================================
  # REQUISITO RECURSIVO: Jerarquía Zona -> Sectores -> Puntos de Atención
  # =========================================================================
  def contar_puntos_zona(%Zona{sectores: sectores}) do
    do_contar_sectores(sectores, 0)
  end

  # Caso base: no quedan sectores
  defp do_contar_sectores([], acumulado), do: acumulado

  # Paso recursivo: cuenta los puntos del sector actual y continúa con el resto
  defp do_contar_sectores([sector | resto_sectores], acumulado) do
    puntos = Map.get(sector, :puntos, [])
    cantidad_en_sector = do_contar_puntos(puntos, 0)
    do_contar_sectores(resto_sectores, acumulado + cantidad_en_sector)
  end

  # Recursividad interna sobre los puntos de un sector
  defp do_contar_puntos([], total), do: total
  defp do_contar_puntos([_punto | resto_puntos], total) do
    do_contar_puntos(resto_puntos, total + 1)
  end
end
