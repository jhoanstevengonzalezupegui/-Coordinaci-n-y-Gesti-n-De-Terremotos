defmodule Emergencia.Servidores.InventarioServer do
  @moduledoc """
  GenServer que gestiona de forma atómica y concurrente el inventario de recursos
  y las necesidades puntuales, evitando condiciones de carrera en las asignaciones.
  """
  use GenServer

  alias Emergencia.Modelos.{Necesidad, Recurso}
  alias Emergencia.{Persistencia, Util}

  @archivo_recursos "recursos.txt"
  @archivo_necesidades "necesidades.txt"

  # --- API Cliente ---

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    data_dir = Keyword.get(opts, :data_dir, "data")
    GenServer.start_link(__MODULE__, %{data_dir: data_dir}, name: name)
  end

  # Operaciones de Recursos
  def registrar_recurso(codigo, nombre, categoria, cantidad, unidad, ubicacion, zona \\ "general", server \\ __MODULE__) do
    GenServer.call(server, {:registrar_recurso, codigo, nombre, categoria, cantidad, unidad, ubicacion, zona})
  end

  def entrada_recurso(codigo, cantidad, referencia \\ "Entrada de inventario", server \\ __MODULE__) do
    GenServer.call(server, {:entrada_recurso, codigo, cantidad, referencia})
  end

  def salida_recurso(codigo, cantidad, referencia \\ "Salida de inventario", server \\ __MODULE__) do
    GenServer.call(server, {:salida_recurso, codigo, cantidad, referencia})
  end

  def transferir_recurso(codigo_origen, origen, destino, cantidad, server \\ __MODULE__) do
    GenServer.call(server, {:transferir_recurso, codigo_origen, origen, destino, cantidad})
  end

  def consultar_disponibilidad(criterio_tipo, zona \\ nil, server \\ __MODULE__) do
    GenServer.call(server, {:consultar_disponibilidad, criterio_tipo, zona})
  end

  def listar_recursos(server \\ __MODULE__) do
    GenServer.call(server, :listar_recursos)
  end

  def recursos_criticos(umbral \\ 20, server \\ __MODULE__) do
    GenServer.call(server, {:recursos_criticos, umbral})
  end

  # Operaciones de Necesidades
  def registrar_necesidad(tipo, cantidad, prioridad, zona, descripcion, responsable \\ "sistema", entidad \\ "general", id_custom \\ nil, server \\ __MODULE__) do
    GenServer.call(server, {:registrar_necesidad, tipo, cantidad, prioridad, zona, descripcion, responsable, entidad, id_custom})
  end

  def listar_necesidades(filtros \\ %{}, server \\ __MODULE__) do
    GenServer.call(server, {:listar_necesidades, filtros})
  end

  def necesidades_pendientes(server \\ __MODULE__) do
    GenServer.call(server, :necesidades_pendientes)
  end

  def cambiar_estado_necesidad(id_necesidad, nuevo_estado, server \\ __MODULE__) do
    GenServer.call(server, {:cambiar_estado_necesidad, id_necesidad, nuevo_estado})
  end

  # Operación Atómica de Asignación Concurrente
  def asignar_recurso(id_necesidad, tipo_o_codigo_recurso, cantidad, server \\ __MODULE__) do
    GenServer.call(server, {:asignar_recurso, id_necesidad, tipo_o_codigo_recurso, cantidad})
  end

  # --- Callbacks GenServer ---

  @impl true
  def init(%{data_dir: data_dir}) do
    {:ok, lista_rec} = Persistencia.cargar_lista(@archivo_recursos, &Recurso.desde_linea/1, data_dir)
    {:ok, lista_nec} = Persistencia.cargar_lista(@archivo_necesidades, &Necesidad.desde_linea/1, data_dir)

    recursos = Map.new(lista_rec, fn r -> {r.codigo, r} end)
    necesidades = Map.new(lista_nec, fn n -> {n.id, n} end)

    {:ok, %{recursos: recursos, necesidades: necesidades, data_dir: data_dir}}
  end

  @impl true
  def handle_call({:registrar_recurso, codigo, nombre, categoria, cantidad, unidad, ubicacion, zona}, _from, state) do
    cod_key = String.trim(to_string(codigo))

    if Map.has_key?(state.recursos, cod_key) do
      {:reply, {:error, :recurso_ya_existe}, state}
    else
      case Recurso.nuevo(cod_key, nombre, categoria, cantidad, unidad, ubicacion, zona) do
        {:ok, recurso} ->
          nuevo_estado = guardar_recursos(state, Map.put(state.recursos, cod_key, recurso))
          {:reply, {:ok, recurso}, nuevo_estado}

        {:error, motivo} ->
          {:reply, {:error, motivo}, state}
      end
    end
  end

  @impl true
  def handle_call({:entrada_recurso, codigo, cantidad, referencia}, _from, state) do
    with {:ok, rec} <- buscar_recurso(state.recursos, codigo),
         {:ok, rec_act} <- Recurso.registrar_entrada(rec, cantidad, referencia) do
      nuevo_estado = guardar_recursos(state, Map.put(state.recursos, rec_act.codigo, rec_act))
      {:reply, {:ok, rec_act}, nuevo_estado}
    else
      {:error, motivo} -> {:reply, {:error, motivo}, state}
    end
  end

  @impl true
  def handle_call({:salida_recurso, codigo, cantidad, referencia}, _from, state) do
    with {:ok, rec} <- buscar_recurso(state.recursos, codigo),
         {:ok, rec_act} <- Recurso.registrar_salida(rec, cantidad, :salida, referencia) do
      nuevo_estado = guardar_recursos(state, Map.put(state.recursos, rec_act.codigo, rec_act))
      {:reply, {:ok, rec_act}, nuevo_estado}
    else
      {:error, motivo} -> {:reply, {:error, motivo}, state}
    end
  end

  @impl true
  def handle_call({:transferir_recurso, codigo_origen, origen, destino, cantidad}, _from, state) do
    origen_norm = String.trim(to_string(origen))
    destino_norm = String.trim(to_string(destino))

    with {:ok, rec_origen} <- buscar_recurso(state.recursos, codigo_origen),
         :ok <- validar_ubicacion_transferencia(rec_origen, origen_norm, destino_norm),
         {:ok, rec_origen_act} <-
           Recurso.registrar_salida(rec_origen, cantidad, :transferencia_salida, "Transferido a #{destino_norm}") do
      recursos_temp = Map.put(state.recursos, rec_origen_act.codigo, rec_origen_act)

      case actualizar_o_crear_destino(recursos_temp, rec_origen, destino_norm, cantidad) do
        {:ok, recursos_finales, rec_destino_act} ->
          nuevo_estado = guardar_recursos(state, recursos_finales)
          {:reply, {:ok, %{origen: rec_origen_act, destino: rec_destino_act}}, nuevo_estado}

        {:error, motivo} ->
          {:reply, {:error, motivo}, state}
      end
    else
      {:error, motivo} -> {:reply, {:error, motivo}, state}
    end
  end

  @impl true
  def handle_call({:consultar_disponibilidad, criterio_tipo, zona}, _from, state) do
    total = Recurso.calcular_disponibilidad_recursiva(Map.values(state.recursos), criterio_tipo, zona)
    {:reply, total, state}
  end

  @impl true
  def handle_call(:listar_recursos, _from, state) do
    {:reply, Map.values(state.recursos), state}
  end

  @impl true
  def handle_call({:recursos_criticos, umbral}, _from, state) do
    criticos =
      state.recursos
      |> Map.values()
      |> Enum.filter(fn r -> r.cantidad_disponible <= umbral end)
      |> Enum.sort_by(& &1.cantidad_disponible, :asc)

    {:reply, criticos, state}
  end

  @impl true
  def handle_call({:registrar_necesidad, tipo, cantidad, prioridad, zona, descripcion, responsable, entidad, id_custom}, _from, state) do
    id_final =
      if is_nil(id_custom) or String.trim(to_string(id_custom)) == "" do
        Util.generar_id("N", Map.keys(state.necesidades))
      else
        String.trim(to_string(id_custom))
      end

    if Map.has_key?(state.necesidades, id_final) do
      {:reply, {:error, :necesidad_ya_existe}, state}
    else
      case Necesidad.nueva(id_final, tipo, descripcion, cantidad, zona, prioridad, responsable, entidad) do
        {:ok, necesidad} ->
          nuevo_estado = guardar_necesidades(state, Map.put(state.necesidades, id_final, necesidad))
          {:reply, {:ok, necesidad}, nuevo_estado}

        {:error, motivo} ->
          {:reply, {:error, motivo}, state}
      end
    end
  end

  @impl true
  def handle_call({:listar_necesidades, filtros}, _from, state) do
    resultado = Necesidad.filtrar(Map.values(state.necesidades), filtros)
    {:reply, resultado, state}
  end

  @impl true
  def handle_call(:necesidades_pendientes, _from, state) do
    pendientes =
      state.necesidades
      |> Map.values()
      |> Enum.filter(fn n -> n.estado in [:pendiente, :asignada, :en_atencion] end)
      |> Necesidad.ordenar_por_prioridad()

    {:reply, pendientes, state}
  end

  @impl true
  def handle_call({:cambiar_estado_necesidad, id_necesidad, nuevo_estado}, _from, state) do
    with {:ok, nec} <- buscar_necesidad(state.necesidades, id_necesidad),
         {:ok, nec_act} <- Necesidad.cambiar_estado(nec, nuevo_estado) do
      estado_final = guardar_necesidades(state, Map.put(state.necesidades, nec_act.id, nec_act))
      {:reply, {:ok, nec_act}, estado_final}
    else
      {:error, motivo} -> {:reply, {:error, motivo}, state}
    end
  end

  @impl true
  def handle_call({:asignar_recurso, id_necesidad, tipo_o_codigo, cantidad}, _from, state) do
    with {:ok, nec} <- buscar_necesidad(state.necesidades, id_necesidad),
         {:ok, nec_act} <- Necesidad.asignar_recurso(nec, cantidad),
         {:ok, recursos_act, detalle_asignacion} <-
           descontar_inventario_atomico(state.recursos, tipo_o_codigo, cantidad, nec.id, nec.zona) do
      nuevo_estado =
        state
        |> guardar_recursos(recursos_act)
        |> guardar_necesidades(Map.put(state.necesidades, nec_act.id, nec_act))

      {:reply, {:ok, %{necesidad: nec_act, asignacion: detalle_asignacion}}, nuevo_estado}
    else
      {:error, motivo} -> {:reply, {:error, motivo}, state}
    end
  end

  # --- Helpers Privados ---

  defp buscar_recurso(recursos, codigo) do
    case Map.get(recursos, String.trim(to_string(codigo))) do
      nil -> {:error, :recurso_no_encontrado}
      rec -> {:ok, rec}
    end
  end

  defp buscar_necesidad(necesidades, id) do
    case Map.get(necesidades, String.trim(to_string(id))) do
      nil -> {:error, :necesidad_no_encontrada}
      nec -> {:ok, nec}
    end
  end

  defp validar_ubicacion_transferencia(%Recurso{ubicacion: ubic}, origen, destino) do
    cond do
      ubic != origen -> {:error, :ubicacion_origen_no_coincide}
      origen == destino -> {:error, :origen_y_destino_iguales}
      true -> :ok
    end
  end

  defp actualizar_o_crear_destino(recursos_map, rec_origen, destino, cantidad) do
    existente =
      recursos_map
      |> Map.values()
      |> Enum.find(fn r ->
        r.ubicacion == destino and r.nombre == rec_origen.nombre and r.categoria == rec_origen.categoria
      end)

    case existente do
      nil ->
        nuevo_cod = "#{rec_origen.codigo}_#{destino}"

        case Recurso.nuevo(
               nuevo_cod,
               rec_origen.nombre,
               rec_origen.categoria,
               cantidad,
               rec_origen.unidad,
               destino,
               rec_origen.zona
             ) do
          {:ok, nuevo_rec} ->
            {:ok, Map.put(recursos_map, nuevo_cod, nuevo_rec), nuevo_rec}

          {:error, motivo} ->
            {:error, motivo}
        end

      rec_dest ->
        {:ok, rec_dest_act} =
          Recurso.registrar_entrada(rec_dest, cantidad, "Transferencia desde #{rec_origen.ubicacion}")

        {:ok, Map.put(recursos_map, rec_dest_act.codigo, rec_dest_act), rec_dest_act}
    end
  end

  defp descontar_inventario_atomico(recursos_map, tipo_o_codigo, cantidad, id_necesidad, zona_necesidad) do
    criterio = String.trim(to_string(tipo_o_codigo))
    criterio_norm = String.downcase(criterio)

    candidatos =
      case Map.get(recursos_map, criterio) do
        %Recurso{} = exacto ->
          [exacto]

        nil ->
          recursos_map
          |> Map.values()
          |> Enum.filter(fn r ->
            (r.nombre == criterio_norm or r.categoria == criterio_norm) and r.cantidad_disponible > 0
          end)
          |> Enum.sort_by(fn r ->
            {if(String.downcase(r.zona) == String.downcase(zona_necesidad), do: 0, else: 1), r.codigo}
          end)
      end

    total_disponible = Enum.reduce(candidatos, 0, fn r, acc -> acc + r.cantidad_disponible end)

    cond do
      candidatos == [] ->
        {:error, :recurso_no_encontrado}

      total_disponible < cantidad ->
        {:error, :inventario_insuficiente}

      true ->
        {recursos_actualizados, usado, _restante} =
          Enum.reduce(candidatos, {recursos_map, [], cantidad}, fn rec, {mapa_acc, log_acc, falta} ->
            if falta == 0 do
              {mapa_acc, log_acc, 0}
            else
              a_tomar = min(rec.cantidad_disponible, falta)

              {:ok, rec_act} =
                Recurso.registrar_salida(rec, a_tomar, :asignacion, "Asignado a necesidad #{id_necesidad}")

              {
                Map.put(mapa_acc, rec_act.codigo, rec_act),
                [{rec_act.codigo, a_tomar} | log_acc],
                falta - a_tomar
              }
            end
          end)

        {:ok, recursos_actualizados, Enum.reverse(usado)}
    end
  end

  defp guardar_recursos(state, nuevos_recursos) do
    Persistencia.guardar_lista(@archivo_recursos, Map.values(nuevos_recursos), &Recurso.a_linea/1, state.data_dir)
    %{state | recursos: nuevos_recursos}
  end

  defp guardar_necesidades(state, nuevas_necesidades) do
    Persistencia.guardar_lista(@archivo_necesidades, Map.values(nuevas_necesidades), &Necesidad.a_linea/1, state.data_dir)
    %{state | necesidades: nuevas_necesidades}
  end
end
