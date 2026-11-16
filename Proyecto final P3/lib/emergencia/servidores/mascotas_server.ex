defmodule Emergencia.Servidores.MascotasServer do
  @moduledoc """
  GenServer encargado de la gestión de mascotas perdidas/encontradas, emparejamiento
  recursivo y resolución atómica sin duplicados.
  """
  use GenServer

  alias Emergencia.Modelos.{Coincidencias, Mascota}
  alias Emergencia.{Persistencia, Util}

  @archivo "mascotas.txt"

  # --- API Cliente ---

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    data_dir = Keyword.get(opts, :data_dir, "data")
    GenServer.start_link(__MODULE__, %{data_dir: data_dir}, name: name)
  end

  def reportar_mascota(tipo_reporte, especie, nombre, caracteristicas, color, tamano, zona, contacto, id_custom \\ nil, server \\ __MODULE__) do
    GenServer.call(
      server,
      {:reportar_mascota, tipo_reporte, especie, nombre, caracteristicas, color, tamano, zona, contacto, id_custom}
    )
  end

  def consultar_reportes(filtros \\ %{}, server \\ __MODULE__) do
    GenServer.call(server, {:consultar_reportes, filtros})
  end

  def buscar_coincidencias(umbral \\ 45, server \\ __MODULE__) do
    GenServer.call(server, {:buscar_coincidencias, umbral})
  end

  def confirmar_coincidencia(id_perdida, id_encontrada, server \\ __MODULE__) do
    GenServer.call(server, {:confirmar_coincidencia, id_perdida, id_encontrada})
  end

  def listar_mascotas(server \\ __MODULE__) do
    GenServer.call(server, :listar)
  end

  # --- Callbacks GenServer ---

  @impl true
  def init(%{data_dir: data_dir}) do
    {:ok, lista} = Persistencia.cargar_lista(@archivo, &Mascota.desde_linea/1, data_dir)
    mascotas = Map.new(lista, fn m -> {m.id, m} end)
    {:ok, %{mascotas: mascotas, data_dir: data_dir}}
  end

  @impl true
  def handle_call({:reportar_mascota, tipo, especie, nombre, caract, color, tamano, zona, contacto, id_custom}, _from, state) do
    id_final =
      if is_nil(id_custom) or String.trim(to_string(id_custom)) == "" do
        Util.generar_id("PET", Map.keys(state.mascotas))
      else
        String.trim(to_string(id_custom))
      end

    if Map.has_key?(state.mascotas, id_final) do
      {:reply, {:error, :reporte_ya_existe}, state}
    else
      case Mascota.nuevo(id_final, tipo, especie, nombre, caract, color, tamano, zona, contacto) do
        {:ok, mascota} ->
          nuevo_estado = guardar_y_actualizar(state, Map.put(state.mascotas, id_final, mascota))
          {:reply, {:ok, mascota}, nuevo_estado}

        {:error, motivo} ->
          {:reply, {:error, motivo}, state}
      end
    end
  end

  @impl true
  def handle_call({:consultar_reportes, filtros}, _from, state) do
    resultados =
      state.mascotas
      |> Map.values()
      |> Enum.filter(fn m ->
        coincide?(m.especie, Map.get(filtros, :especie)) and
          coincide?(m.zona, Map.get(filtros, :zona)) and
          coincide?(m.estado, Map.get(filtros, :estado)) and
          coincide?(m.tipo_reporte, Map.get(filtros, :tipo_reporte))
      end)

    {:reply, resultados, state}
  end

  @impl true
  def handle_call({:buscar_coincidencias, umbral}, _from, state) do
    coincidencias = Coincidencias.buscar_coincidencias(Map.values(state.mascotas), umbral)

    ids_involucrados =
      coincidencias
      |> Enum.flat_map(fn c -> [c.id_perdida, c.id_encontrada] end)
      |> MapSet.new()

    mascotas_act =
      Map.new(state.mascotas, fn {id, mascota} ->
        if MapSet.member?(ids_involucrados, id) and mascota.estado == :activa do
          {:ok, m_act} = Mascota.marcar_posible_coincidencia(mascota)
          {id, m_act}
        else
          {id, mascota}
        end
      end)

    nuevo_estado = guardar_y_actualizar(state, mascotas_act)
    {:reply, coincidencias, nuevo_estado}
  end

  @impl true
  def handle_call({:confirmar_coincidencia, id_perdida, id_encontrada}, _from, state) do
    with {:ok, rep_perdida} <- buscar_mascota(state.mascotas, id_perdida),
         {:ok, rep_encontrada} <- buscar_mascota(state.mascotas, id_encontrada),
         :ok <- validar_par_compatible(rep_perdida, rep_encontrada),
         {:ok, perdida_resuelta} <- Mascota.resolver(rep_perdida, rep_encontrada.id),
         {:ok, encontrada_resuelta} <- Mascota.resolver(rep_encontrada, rep_perdida.id) do
      mascotas_act =
        state.mascotas
        |> Map.put(perdida_resuelta.id, perdida_resuelta)
        |> Map.put(encontrada_resuelta.id, encontrada_resuelta)

      nuevo_estado = guardar_y_actualizar(state, mascotas_act)
      {:reply, {:ok, {perdida_resuelta, encontrada_resuelta}}, nuevo_estado}
    else
      {:error, motivo} -> {:reply, {:error, motivo}, state}
    end
  end

  @impl true
  def handle_call(:listar, _from, state) do
    {:reply, Map.values(state.mascotas), state}
  end

  defp buscar_mascota(mascotas, id) do
    case Map.get(mascotas, String.trim(to_string(id))) do
      nil -> {:error, :reporte_mascota_no_encontrado}
      m -> {:ok, m}
    end
  end

  defp validar_par_compatible(%Mascota{tipo_reporte: t1}, %Mascota{tipo_reporte: t2})
       when t1 == t2 do
    {:error, :tipos_reporte_incompatibles}
  end

  defp validar_par_compatible(%Mascota{especie: e1}, %Mascota{especie: e2})
       when e1 != e2 do
    {:error, :especies_distintas}
  end

  defp validar_par_compatible(_, _), do: :ok

  defp coincide?(_valor, nil), do: true
  defp coincide?(valor, filtro), do: String.downcase(to_string(valor)) == String.downcase(String.trim(to_string(filtro)))

  defp guardar_y_actualizar(state, nuevas_mascotas) do
    Persistencia.guardar_lista(@archivo, Map.values(nuevas_mascotas), &Mascota.a_linea/1, state.data_dir)
    %{state | mascotas: nuevas_mascotas}
  end
end
