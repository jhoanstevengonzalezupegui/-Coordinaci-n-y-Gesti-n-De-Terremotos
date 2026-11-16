defmodule Emergencia.Modelos.Coincidencias do
  @moduledoc "Motor recursivo de emparejamiento entre reportes de mascotas perdidas y encontradas."

  alias Emergencia.Modelos.Mascota

  @umbral_minimo 45

  def buscar_coincidencias(mascotas, umbral \\ @umbral_minimo) do
    perdidas =
      Enum.filter(mascotas, fn m ->
        m.tipo_reporte == :perdida and m.estado != :resuelta
      end)

    encontradas =
      Enum.filter(mascotas, fn m ->
        m.tipo_reporte == :encontrada and m.estado != :resuelta
      end)

    emparejar_perdidas_rec(perdidas, encontradas, umbral)
    |> Enum.sort_by(& &1.puntaje, :desc)
  end

  defp emparejar_perdidas_rec([], _encontradas, _umbral), do: []

  defp emparejar_perdidas_rec([perdida | resto_perdidas], encontradas, umbral) do
    coincidencias_para_una = comparar_con_encontradas_rec(perdida, encontradas, umbral)
    coincidencias_para_una ++ emparejar_perdidas_rec(resto_perdidas, encontradas, umbral)
  end

  defp comparar_con_encontradas_rec(_perdida, [], _umbral), do: []

  defp comparar_con_encontradas_rec(perdida, [encontrada | resto], umbral) do
    puntaje = calcular_puntaje(perdida, encontrada)

    if puntaje >= umbral do
      match = %{
        id_perdida: perdida.id,
        id_encontrada: encontrada.id,
        especie: perdida.especie,
        nombre_perdida: perdida.nombre,
        zona_perdida: perdida.zona,
        zona_encontrada: encontrada.zona,
        puntaje: puntaje
      }

      [match | comparar_con_encontradas_rec(perdida, resto, umbral)]
    else
      comparar_con_encontradas_rec(perdida, resto, umbral)
    end
  end

  def calcular_puntaje(%Mascota{especie: esp1}, %Mascota{especie: esp2})
      when esp1 != esp2,
      do: 0

  def calcular_puntaje(%Mascota{} = p, %Mascota{} = e) do
    pts_zona = if String.downcase(p.zona) == String.downcase(e.zona), do: 35, else: 0
    pts_color = if p.color != "" and p.color == e.color, do: 20, else: 0
    pts_tamano = if p.tamano != "" and p.tamano == e.tamano, do: 20, else: 0

    pts_nombre =
      if String.downcase(p.nombre) != "desconocido" and
           String.downcase(e.nombre) != "desconocido" and
           String.downcase(p.nombre) == String.downcase(e.nombre) do
        15
      else
        0
      end

    pts_caract = puntaje_caracteristicas(p.caracteristicas, e.caracteristicas)

    pts_zona + pts_color + pts_tamano + pts_nombre + pts_caract
  end

  defp puntaje_caracteristicas("", _), do: 0
  defp puntaje_caracteristicas(_, ""), do: 0

  defp puntaje_caracteristicas(c1, c2) do
    tokens1 = c1 |> String.split([" ", ",", ";"], trim: true) |> MapSet.new()
    tokens2 = c2 |> String.split([" ", ",", ";"], trim: true) |> MapSet.new()
    comunes = MapSet.intersection(tokens1, tokens2) |> MapSet.size()
    min(comunes * 5, 10)
  end
end
