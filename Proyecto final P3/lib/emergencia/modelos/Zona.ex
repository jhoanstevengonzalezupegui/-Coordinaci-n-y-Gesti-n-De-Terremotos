defmodule Emergencia.Modelos.Zona do
  @moduledoc """
  Modelo jerárquico para zonas afectadas: Zona -> Sectores -> Puntos de atención.
  Incluye algoritmos recursivos sobre la jerarquía para estadísticas y búsqueda.
  """

  @niveles_validos [:critico, :alto, :medio, :bajo]

  defstruct [
    :codigo,
    :nombre,
    :nivel_afectacion,
    afectados_estimados: 0,
    sectores: [],
    albergues: MapSet.new(),
    necesidades: MapSet.new(),
    recursos: MapSet.new(),
    reportes: MapSet.new()
  ]

  @doc """
  Crea una nueva zona afectada validando nivel y cantidad no negativa.
  """
  def nueva(codigo, nombre, nivel_afectacion, afectados_estimados \\ 0) do
    nivel = normalizar_nivel(nivel_afectacion)

    cond do
      is_nil(codigo) or String.trim(to_string(codigo)) == "" ->
        {:error, :codigo_invalido}

      is_nil(nombre) or String.trim(to_string(nombre)) == "" ->
        {:error, :nombre_invalido}

      nivel not in @niveles_validos ->
        {:error, :nivel_afectacion_invalido}

      not is_integer(afectados_estimados) or afectados_estimados < 0 ->
        {:error, :cantidad_afectados_invalida}

      true ->
        {:ok,
         %__MODULE__{
           codigo: String.trim(to_string(codigo)),
           nombre: String.trim(to_string(nombre)),
           nivel_afectacion: nivel,
           afectados_estimados: afectados_estimados
         }}
    end
  end

  @doc """
  Agrega un sector a la zona evitando códigos de sector duplicados.
  """
  def agregar_sector(%__MODULE__{sectores: sectores} = zona, cod_sector, nombre_sector, nivel, afectados \\ 0) do
    nivel_atom = normalizar_nivel(nivel)

    cond do
      nivel_atom not in @niveles_validos ->
        {:error, :nivel_afectacion_invalido}

      not is_integer(afectados) or afectados < 0 ->
        {:error, :cantidad_afectados_invalida}

      Enum.any?(sectores, &(&1.codigo == cod_sector)) ->
        {:error, :sector_duplicado}

      true ->
        nuevo_sector = %{
          codigo: cod_sector,
          nombre: nombre_sector,
          nivel_afectacion: nivel_atom,
          afectados_estimados: afectados,
          puntos_atencion: []
        }

        {:ok, %{zona | sectores: sectores ++ [nuevo_sector]}}
    end
  end

  @doc """
  Agrega un punto de atención dentro de un sector existente de la zona.
  """
  def agregar_punto_atencion(%__MODULE__{sectores: sectores} = zona, cod_sector, cod_punto, nombre_punto, tipo) do
    case actualizar_sector_rec(sectores, cod_sector, cod_punto, nombre_punto, tipo) do
      {:ok, nuevos_sectores} -> {:ok, %{zona | sectores: nuevos_sectores}}
      {:error, motivo} -> {:error, motivo}
    end
  end

  defp actualizar_sector_rec([], _cod_sector, _cod_punto, _nombre_punto, _tipo),
    do: {:error, :sector_no_encontrado}

  defp actualizar_sector_rec([%{codigo: cod} = sector | resto], cod_sector, cod_punto, nombre_punto, tipo)
       when cod == cod_sector do
    if Enum.any?(sector.puntos_atencion, &(&1.codigo == cod_punto)) do
      {:error, :punto_atencion_duplicado}
    else
      punto = %{codigo: cod_punto, nombre: nombre_punto, tipo: tipo}
      sector_act = %{sector | puntos_atencion: sector.puntos_atencion ++ [punto]}
      {:ok, [sector_act | resto]}
    end
  end

  defp actualizar_sector_rec([cabeza | resto], cod_sector, cod_punto, nombre_punto, tipo) do
    case actualizar_sector_rec(resto, cod_sector, cod_punto, nombre_punto, tipo) do
      {:ok, resto_act} -> {:ok, [cabeza | resto_act]}
      error -> error
    end
  end

  @doc """
  Asocia un identificador de entidad (:albergues, :necesidades, :recursos, :reportes) a la zona.
  """
  def asociar_entidad(%__MODULE__{} = zona, categoria, id_entidad)
      when categoria in [:albergues, :necesidades, :recursos, :reportes] do
    conjunto_actual = Map.get(zona, categoria)
    {:ok, Map.put(zona, categoria, MapSet.put(conjunto_actual, id_entidad))}
  end

  def asociar_entidad(_, _, _), do: {:error, :categoria_invalida}

  @doc """
  FUNCIÓN RECURSIVA #1:
  Recorre recursivamente la jerarquía Zona -> Sectores -> Puntos de atención
  para calcular estadísticas acumuladas de población afectada y capacidad operativa.
  """
  def calcular_estadisticas(%__MODULE__{} = zona) do
    acumulado_sectores = recorrer_sectores_rec(zona.sectores)

    %{
      codigo_zona: zona.codigo,
      nombre_zona: zona.nombre,
      nivel_zona: zona.nivel_afectacion,
      total_afectados: zona.afectados_estimados + acumulado_sectores.afectados,
      total_sectores: acumulado_sectores.sectores,
      sectores_criticos: acumulado_sectores.criticos,
      total_puntos_atencion: acumulado_sectores.puntos_atencion,
      total_albergues: MapSet.size(zona.albergues),
      total_necesidades: MapSet.size(zona.necesidades),
      total_recursos: MapSet.size(zona.recursos),
      total_reportes: MapSet.size(zona.reportes)
    }
  end

  defp recorrer_sectores_rec([]) do
    %{afectados: 0, sectores: 0, criticos: 0, puntos_atencion: 0}
  end

  defp recorrer_sectores_rec([sector | resto]) do
    puntos_en_sector = contar_puntos_rec(sector.puntos_atencion)
    es_critico = if sector.nivel_afectacion == :critico, do: 1, else: 0
    sub = recorrer_sectores_rec(resto)

    %{
      afectados: sector.afectados_estimados + sub.afectados,
      sectores: 1 + sub.sectores,
      criticos: es_critico + sub.criticos,
      puntos_atencion: puntos_en_sector + sub.puntos_atencion
    }
  end

  defp contar_puntos_rec([]), do: 0
  defp contar_puntos_rec([_punto | resto]), do: 1 + contar_puntos_rec(resto)

  @doc """
  Búsqueda recursiva de un punto de atención por código dentro de todos los sectores de una zona.
  """
  def buscar_punto_atencion(%__MODULE__{sectores: sectores}, cod_punto) do
    buscar_en_sectores_rec(sectores, cod_punto)
  end

  defp buscar_en_sectores_rec([], _cod_punto), do: {:error, :no_encontrado}

  defp buscar_en_sectores_rec([sector | resto], cod_punto) do
    case buscar_en_puntos_rec(sector.puntos_atencion, cod_punto) do
      {:ok, punto} -> {:ok, %{sector: sector.codigo, punto: punto}}
      :no_encontrado -> buscar_en_sectores_rec(resto, cod_punto)
    end
  end

  defp buscar_en_puntos_rec([], _cod_punto), do: :no_encontrado
  defp buscar_en_puntos_rec([%{codigo: cod} = punto | _], cod), do: {:ok, punto}
  defp buscar_en_puntos_rec([_ | resto], cod), do: buscar_en_puntos_rec(resto, cod)

  @doc """
  Serialización a texto plano para persistencia en data/zonas.txt.
  """
  def a_linea(%__MODULE__{} = z) do
    sectores_str =
      z.sectores
      |> Enum.map(fn s ->
        puntos_str =
          s.puntos_atencion
          |> Enum.map(fn p -> "#{p.codigo}:#{p.nombre}:#{p.tipo}" end)
          |> Enum.join(",")

        "#{s.codigo}~#{s.nombre}~#{s.nivel_afectacion}~#{s.afectados_estimados}~#{puntos_str}"
      end)
      |> Enum.join(";")

    [
      z.codigo,
      z.nombre,
      Atom.to_string(z.nivel_afectacion),
      Integer.to_string(z.afectados_estimados),
      sectores_str,
      Enum.join(MapSet.to_list(z.albergues), ","),
      Enum.join(MapSet.to_list(z.necesidades), ","),
      Enum.join(MapSet.to_list(z.recursos), ","),
      Enum.join(MapSet.to_list(z.reportes), ",")
    ]
    |> Enum.join("|")
  end

  def desde_linea(linea) do
    case String.split(String.trim(linea), "|") do
      [codigo, nombre, nivel, afectados, sectores_str, alb, nec, rec, rep] ->
        sectores = parsear_sectores(sectores_str)

        {:ok,
         %__MODULE__{
           codigo: codigo,
           nombre: nombre,
           nivel_afectacion: String.to_existing_atom(nivel),
           afectados_estimados: String.to_integer(afectados),
           sectores: sectores,
           albergues: parsear_set(alb),
           necesidades: parsear_set(nec),
           recursos: parsear_set(rec),
           reportes: parsear_set(rep)
         }}

      _ ->
        {:error, :formato_zona_invalido}
    end
  end

  defp parsear_sectores(""), do: []

  defp parsear_sectores(str) do
    str
    |> String.split(";")
    |> Enum.map(fn s_item ->
      [cod, nom, niv, afec, pts_str] = String.split(s_item, "~")

      puntos =
        if pts_str == "" do
          []
        else
          pts_str
          |> String.split(",")
          |> Enum.map(fn p ->
            [pcod, pnom, ptipo] = String.split(p, ":")
            %{codigo: pcod, nombre: pnom, tipo: ptipo}
          end)
        end

      %{
        codigo: cod,
        nombre: nom,
        nivel_afectacion: String.to_existing_atom(niv),
        afectados_estimados: String.to_integer(afec),
        puntos_atencion: puntos
      }
    end)
  end

  defp parsear_set(""), do: MapSet.new()
  defp parsear_set(str), do: str |> String.split(",") |> MapSet.new()

  defp normalizar_nivel(n) when is_atom(n) and n in @niveles_validos, do: n

  defp normalizar_nivel(n) when is_binary(n) do
    case String.downcase(String.trim(n)) do
      "critico" -> :critico
      "crítico" -> :critico
      "alto" -> :alto
      "medio" -> :medio
      "bajo" -> :bajo
      _ -> :invalido
    end
  end

  defp normalizar_nivel(_), do: :invalido
end
