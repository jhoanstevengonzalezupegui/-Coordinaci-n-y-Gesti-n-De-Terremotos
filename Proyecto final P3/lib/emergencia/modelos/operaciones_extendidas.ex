defmodule Emergencia.OperacionesExtendidas do
  @moduledoc """
  Operaciones complementarias de consulta, reportes consolidados, búsqueda de
  coincidencias y transferencia entre centros de apoyo sobre los servidores OTP.
  """

  alias Emergencia.Servidores.{
    AlberguesServer,
    FamiliaresServer,
    InventarioServer,
    MascotasServer,
    ZonasServer
  }

  @tipos_necesidad_validos [
    :agua,
    :alimentos,
    :medicamentos,
    :primeros_auxilios,
    :refugio,
    :transporte,
    :rescate,
    :otra
  ]

  # ============================================================================
  # 1. TRANSFERENCIA DE RECURSOS ENTRE CENTROS DE APOYO (Req. 1.4.5)
  # ============================================================================

  def transferir_recurso(recurso_id, ubicacion_destino, zona_destino, cantidad, usuario \\ "sistema")

  def transferir_recurso(recurso_id, ubicacion_destino, zona_destino, cantidad, usuario)
      when is_integer(cantidad) and cantidad > 0 do
    recursos = listar_recursos(nil)

    case Enum.find(recursos, fn r -> id_de(r) == recurso_id end) do
      nil ->
        {:error, :recurso_no_encontrado}

      rec ->
        disp = Map.get(rec, :cantidad_disponible, 0)

        if disp < cantidad do
          {:error, :inventario_insuficiente}
        else
          desc =
            "Transferencia interna de #{Map.get(rec, :ubicacion)} (#{Map.get(rec, :zona)}) hacia #{ubicacion_destino} (#{zona_destino})"

          candidato = rec.nombre |> to_string() |> String.downcase() |> String.to_atom()
          tipo_atom = if candidato in @tipos_necesidad_validos, do: candidato, else: :otra

          with {:ok, nec} <-
                 InventarioServer.registrar_necesidad(
                   tipo_atom,
                   cantidad,
                   :alta,
                   zona_destino,
                   desc,
                   usuario,
                   "transferencia",
                   nil
                 ),
               nec_id = id_de(nec),
               {:ok, _} <- InventarioServer.asignar_recurso(nec_id, recurso_id, cantidad),
               nuevo_id = "#{recurso_id}_T#{System.unique_integer([:positive])}",
               unidad = Map.get(rec, :unidad) || Map.get(rec, :unidad_medida, "unidades"),
               {:ok, nuevo_rec} <-
                 InventarioServer.registrar_recurso(
                   nuevo_id,
                   rec.nombre,
                   rec.categoria,
                   cantidad,
                   unidad,
                   ubicacion_destino,
                   zona_destino
                 ) do
            {:ok,
             %{
               origen_id: recurso_id,
               destino_id: id_de(nuevo_rec),
               recurso: rec.nombre,
               cantidad_transferida: cantidad,
               ubicacion_destino: ubicacion_destino,
               zona_destino: zona_destino
             }}
          end
        end
    end
  end

  def transferir_recurso(_, _, _, _, _), do: {:error, :cantidad_invalida}

  # ============================================================================
  # 2. LISTADO RECURSIVO DE RECURSOS Y NECESIDADES (Req. 1.4.4 y 1.4.5)
  # ============================================================================

  def listar_recursos(zona \\ nil) do
    :sys.get_state(InventarioServer)
    |> extraer_lista([:recursos])
    |> filtrar_recursos_rec(zona, [])
    |> Enum.reverse()
  end

  defp filtrar_recursos_rec([], _zona, acc), do: acc

  defp filtrar_recursos_rec([r | resto], nil, acc) do
    filtrar_recursos_rec(resto, nil, [r | acc])
  end

  defp filtrar_recursos_rec([r | resto], zona, acc) do
    if String.downcase(to_string(Map.get(r, :zona, ""))) == String.downcase(to_string(zona)) do
      filtrar_recursos_rec(resto, zona, [r | acc])
    else
      filtrar_recursos_rec(resto, zona, acc)
    end
  end

  def listar_necesidades(zona \\ nil, prioridad \\ nil) do
    :sys.get_state(InventarioServer)
    |> extraer_lista([:necesidades])
    |> filtrar_necesidades_rec(zona, prioridad, [])
    |> ordenar_necesidades_rec()
  end

  defp filtrar_necesidades_rec([], _zona, _prio, acc), do: acc

  defp filtrar_necesidades_rec([n | resto], zona, prio, acc) do
    coincide_zona =
      is_nil(zona) or
        String.downcase(to_string(Map.get(n, :zona, ""))) == String.downcase(to_string(zona))

    coincide_prio =
      is_nil(prio) or
        String.downcase(to_string(Map.get(n, :prioridad, ""))) == String.downcase(to_string(prio))

    nuevo_acc = if coincide_zona and coincide_prio, do: [n | acc], else: acc
    filtrar_necesidades_rec(resto, zona, prio, nuevo_acc)
  end

  defp ordenar_necesidades_rec([]), do: []

  defp ordenar_necesidades_rec([pivote | resto]) do
    mayores =
      Enum.filter(resto, fn n ->
        peso_prioridad(Map.get(n, :prioridad)) >= peso_prioridad(Map.get(pivote, :prioridad))
      end)

    menores =
      Enum.filter(resto, fn n ->
        peso_prioridad(Map.get(n, :prioridad)) < peso_prioridad(Map.get(pivote, :prioridad))
      end)

    ordenar_necesidades_rec(mayores) ++ [pivote] ++ ordenar_necesidades_rec(menores)
  end

  defp peso_prioridad(:critica), do: 4
  defp peso_prioridad("critica"), do: 4
  defp peso_prioridad(:alta), do: 3
  defp peso_prioridad("alta"), do: 3
  defp peso_prioridad(:media), do: 2
  defp peso_prioridad("media"), do: 2
  defp peso_prioridad(_), do: 1

  # ============================================================================
  # 3. BÚSQUEDA RECURSIVA DE FAMILIARES (Req. 1.4.6)
  # ============================================================================

  def buscar_personas(criterio) do
    term = String.downcase(to_string(criterio))

    :sys.get_state(FamiliaresServer)
    |> extraer_lista([:personas])
    |> buscar_personas_rec(term, [])
    |> Enum.reverse()
  end

  defp buscar_personas_rec([], _term, acc), do: acc

  defp buscar_personas_rec([p | resto], term, acc) do
    doc = String.downcase(to_string(Map.get(p, :documento, "")))
    nom = String.downcase(to_string(Map.get(p, :nombre, "")))
    zona = String.downcase(to_string(Map.get(p, :zona, "")))
    est = String.downcase(to_string(Map.get(p, :estado, "")))

    coincide =
      String.contains?(doc, term) or
        String.contains?(nom, term) or
        zona == term or
        est == term

    nuevo_acc = if coincide, do: [p | acc], else: acc
    buscar_personas_rec(resto, term, nuevo_acc)
  end

  # ============================================================================
  # 4. MOTOR RECURSIVO DE COINCIDENCIAS DE MASCOTAS (Req. 1.4.7)
  # ============================================================================

  def buscar_coincidencias_mascotas do
    reportes =
      :sys.get_state(MascotasServer)
      |> extraer_lista([:reportes, :mascotas])

    perdidas =
      Enum.filter(reportes, fn m ->
        tipo = Map.get(m, :tipo_reporte) || Map.get(m, :tipo)
        tipo == :perdida and Map.get(m, :estado) != :resuelta
      end)

    encontradas =
      Enum.filter(reportes, fn m ->
        tipo = Map.get(m, :tipo_reporte) || Map.get(m, :tipo)
        tipo == :encontrada and Map.get(m, :estado) != :resuelta
      end)

    emparejar_rec(perdidas, encontradas, [])
    |> Enum.sort_by(fn c -> c.puntaje end, :desc)
  end

  defp emparejar_rec([], _encontradas, acc), do: acc

  defp emparejar_rec([p | resto], encontradas, acc) do
    nuevas = evaluar_contra_encontradas(p, encontradas, [])
    emparejar_rec(resto, encontradas, nuevas ++ acc)
  end

  defp evaluar_contra_encontradas(_p, [], acc), do: acc

  defp evaluar_contra_encontradas(p, [e | resto], acc) do
    puntaje = calcular_similitud(p, e)

    nuevo_acc =
      if puntaje >= 40 do
        [
          %{
            id_perdida: id_de(p),
            nombre_perdida: Map.get(p, :nombre, "sin_nombre"),
            id_encontrada: id_de(e),
            especie: Map.get(p, :especie, ""),
            zona: Map.get(p, :zona, ""),
            puntaje: puntaje
          }
          | acc
        ]
      else
        acc
      end

    evaluar_contra_encontradas(p, resto, nuevo_acc)
  end

  defp calcular_similitud(p, e) do
    s1 = if norm(Map.get(p, :especie)) == norm(Map.get(e, :especie)), do: 30, else: 0
    s2 = if norm(Map.get(p, :color)) == norm(Map.get(e, :color)), do: 25, else: 0
    s3 = if norm(tamano_de(p)) == norm(tamano_de(e)), do: 15, else: 0
    s4 = if norm(Map.get(p, :zona)) == norm(Map.get(e, :zona)), do: 20, else: 0
    s5 = if norm(Map.get(p, :caracteristicas)) == norm(Map.get(e, :caracteristicas)), do: 10, else: 0
    s1 + s2 + s3 + s4 + s5
  end

  defp tamano_de(m), do: Map.get(m, :tamano) || Map.get(m, :"tamaño") || ""

  defp norm(val), do: val |> to_string() |> String.trim() |> String.downcase()

  # ============================================================================
  # 5. CONSULTA Y REPORTE DE OCUPACIÓN DE ALBERGUES (Req. 1.4.8)
  # ============================================================================

  def consultar_albergue(id) do
    albergues = :sys.get_state(AlberguesServer) |> extraer_lista([:albergues])

    case Enum.find(albergues, fn a -> id_de(a) == id end) do
      nil ->
        {:error, :albergue_no_encontrado}

      alb ->
        cap = Map.get(alb, :capacidad_maxima) || Map.get(alb, :capacidad, 0)
        ocup_set = Map.get(alb, :personas_alojadas) || Map.get(alb, :ocupantes, MapSet.new())
        ocupados = if is_struct(ocup_set, MapSet), do: MapSet.size(ocup_set), else: length(ocup_set)
        lista_ocup = if is_struct(ocup_set, MapSet), do: MapSet.to_list(ocup_set), else: ocup_set
        disponibles = max(cap - ocupados, 0)
        porcentaje = if cap > 0, do: Float.round(ocupados * 100 / cap, 1), else: 0.0

        {:ok,
         %{
           id: id_de(alb),
           nombre: Map.get(alb, :nombre, ""),
           zona: Map.get(alb, :zona, ""),
           capacidad: cap,
           ocupados: ocupados,
           disponibles: disponibles,
           porcentaje: porcentaje,
           lista_ocupantes: lista_ocup
         }}
    end
  end

  def reporte_albergues do
    :sys.get_state(AlberguesServer)
    |> extraer_lista([:albergues])
    |> Enum.map(fn alb ->
      cap = Map.get(alb, :capacidad_maxima) || Map.get(alb, :capacidad, 0)
      ocup_set = Map.get(alb, :personas_alojadas) || Map.get(alb, :ocupantes, MapSet.new())
      ocupados = if is_struct(ocup_set, MapSet), do: MapSet.size(ocup_set), else: length(ocup_set)
      porcentaje = if cap > 0, do: Float.round(ocupados * 100 / cap, 1), else: 0.0

      %{
        id: id_de(alb),
        nombre: Map.get(alb, :nombre, ""),
        zona: Map.get(alb, :zona, ""),
        ocupados: ocupados,
        capacidad: cap,
        disponibles: max(cap - ocupados, 0),
        porcentaje: porcentaje
      }
    end)
    |> Enum.sort_by(fn r -> r.porcentaje end, :desc)
  end

  # ============================================================================
  # 6. RESUMEN GLOBAL DEL SISTEMA (Req. 1.4.10 - summary)
  # ============================================================================

  def resumen_global do
    zonas = :sys.get_state(ZonasServer) |> extraer_lista([:zonas])
    recursos = listar_recursos(nil)
    necesidades = listar_necesidades(nil, nil)
    albergues = reporte_albergues()
    personas = :sys.get_state(FamiliaresServer) |> extraer_lista([:personas])
    mensajes = :sys.get_state(FamiliaresServer) |> extraer_lista([:mensajes])
    mascotas = :sys.get_state(MascotasServer) |> extraer_lista([:reportes, :mascotas])

    %{
      total_zonas: length(zonas),
      recursos: recursos,
      necesidades_pendientes:
        Enum.count(necesidades, fn n -> Map.get(n, :estado) not in [:atendida, :cancelada] end),
      necesidades_atendidas: Enum.count(necesidades, fn n -> Map.get(n, :estado) == :atendida end),
      albergues: albergues,
      total_personas: length(personas),
      total_mensajes: length(mensajes),
      mascotas_activas: Enum.count(mascotas, fn m -> Map.get(m, :estado) != :resuelta end),
      mascotas_resueltas: Enum.count(mascotas, fn m -> Map.get(m, :estado) == :resuelta end)
    }
  end

  # ============================================================================
  # AUXILIARES DE EXTRACCIÓN SEGURA DE ESTADO
  # ============================================================================

  def id_de(struct_o_mapa) when is_map(struct_o_mapa) do
    Map.get(struct_o_mapa, :codigo) || Map.get(struct_o_mapa, :id) || Map.get(struct_o_mapa, :documento)
  end

  defp extraer_lista(state, keys) when is_map(state) do
    val = Enum.find_value(keys, [], fn k -> Map.get(state, k) end)

    cond do
      is_map(val) and not is_struct(val) -> Map.values(val)
      is_list(val) -> val
      true -> []
    end
  end

  defp extraer_lista(_, _), do: []
end
