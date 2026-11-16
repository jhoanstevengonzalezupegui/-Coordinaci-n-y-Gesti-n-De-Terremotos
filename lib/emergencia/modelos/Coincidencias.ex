defmodule Coincidencias do
  @moduledoc """
  Algoritmo recursivo para buscar coincidencias entre mascotas perdidas y encontradas.
  """

  @doc """
  Recibe la lista de mascotas perdidas y la de encontradas, y retorna una lista de tuplas
  con los IDs que hicieron match.
  """
  def buscar(perdidas, encontradas) do
    # Iniciamos la recursividad con un acumulador vacío para los resultados
    do_buscar(perdidas, encontradas, [])
  end

  # Caso base: no quedan más mascotas perdidas por evaluar
  defp do_buscar([], _encontradas, resultados), do: {:ok, Enum.reverse(resultados)}

  # Paso recursivo: tomamos la cabeza (una perdida) y la comparamos
  defp do_buscar([perdida | resto_perdidas], encontradas, resultados) do
    mejor_match = evaluar_candidatos(perdida, encontradas, nil, 0)

    nuevos_resultados = if mejor_match do
      [{perdida.id, mejor_match.id} | resultados]
    else
      resultados
    end

    # Llamada recursiva con el resto de la lista
    do_buscar(resto_perdidas, encontradas, nuevos_resultados)
  end

  # Recursividad interna para recorrer las mascotas encontradas y darles puntaje
  defp evaluar_candidatos(_perdida, [], mejor_candidato, _mejor_puntaje), do: mejor_candidato

  defp evaluar_candidatos(perdida, [encontrada | resto_encontradas], mejor_candidato, mejor_puntaje) do
    puntaje = calcular_puntaje(perdida, encontrada)

    # Si el puntaje es mayor a 3 (umbral de similitud) y supera al candidato anterior
    if puntaje > mejor_puntaje and puntaje >= 3 do
      evaluar_candidatos(perdida, resto_encontradas, encontrada, puntaje)
    else
      evaluar_candidatos(perdida, resto_encontradas, mejor_candidato, mejor_puntaje)
    end
  end

  # Asignación de puntos según atributos que coincidan
  defp calcular_puntaje(p, e) do
    puntos = 0
    puntos = if p.especie == e.especie, do: puntos + 2, else: puntos
    puntos = if p.zona == e.zona, do: puntos + 1, else: puntos
    puntos = if p.color == e.color, do: puntos + 1, else: puntos
    puntos = if p.tamano == e.tamano, do: puntos + 1, else: puntos
    puntos
  end
end
