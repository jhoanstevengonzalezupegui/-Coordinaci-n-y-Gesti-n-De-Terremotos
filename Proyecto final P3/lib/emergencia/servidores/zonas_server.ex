defmodule Emergencia.Servidores.ZonasServer do
  @moduledoc """
  GenServer encargado de la gestión jerárquica de zonas afectadas, sectores y puntos de atención.
  """
  use GenServer

  alias Emergencia.Modelos.Zona
  alias Emergencia.Persistencia

  @archivo "zonas.txt"

  # --- API Cliente ---

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    data_dir = Keyword.get(opts, :data_dir, "data")
    GenServer.start_link(__MODULE__, %{data_dir: data_dir}, name: name)
  end

  def registrar_zona(codigo, nombre, nivel, afectados \\ 0, server \\ __MODULE__) do
    GenServer.call(server, {:registrar_zona, codigo, nombre, nivel, afectados})
  end

  def agregar_sector(cod_zona, cod_sector, nombre_sector, nivel, afectados \\ 0, server \\ __MODULE__) do
    GenServer.call(server, {:agregar_sector, cod_zona, cod_sector, nombre_sector, nivel, afectados})
  end

  def agregar_punto_atencion(cod_zona, cod_sector, cod_punto, nombre_punto, tipo, server \\ __MODULE__) do
    GenServer.call(server, {:agregar_punto, cod_zona, cod_sector, cod_punto, nombre_punto, tipo})
  end

  def asociar_entidad(cod_zona, categoria, id_entidad, server \\ __MODULE__) do
    GenServer.call(server, {:asociar_entidad, cod_zona, categoria, id_entidad})
  end

  def consultar_zona(cod_zona, server \\ __MODULE__) do
    GenServer.call(server, {:consultar_zona, cod_zona})
  end

  def estadisticas_zona(cod_zona, server \\ __MODULE__) do
    GenServer.call(server, {:estadisticas_zona, cod_zona})
  end

  def buscar_punto_atencion(cod_zona, cod_punto, server \\ __MODULE__) do
    GenServer.call(server, {:buscar_punto, cod_zona, cod_punto})
  end

  def listar_zonas(server \\ __MODULE__) do
    GenServer.call(server, :listar)
  end

  # --- Callbacks GenServer ---

  @impl true
  def init(%{data_dir: data_dir}) do
    {:ok, lista} = Persistencia.cargar_lista(@archivo, &Zona.desde_linea/1, data_dir)
    zonas = Map.new(lista, fn z -> {z.codigo, z} end)
    {:ok, %{zonas: zonas, data_dir: data_dir}}
  end

  @impl true
  def handle_call({:registrar_zona, codigo, nombre, nivel, afectados}, _from, state) do
    cod_key = String.trim(to_string(codigo))

    if Map.has_key?(state.zonas, cod_key) do
      {:reply, {:error, :zona_ya_existe}, state}
    else
      case Zona.nueva(cod_key, nombre, nivel, afectados) do
        {:ok, zona} ->
          nuevo_estado = guardar_y_actualizar(state, zona)
          {:reply, {:ok, zona}, nuevo_estado}

        {:error, motivo} ->
          {:reply, {:error, motivo}, state}
      end
    end
  end

  @impl true
  def handle_call({:agregar_sector, cod_zona, cod_sector, nombre_sector, nivel, afectados}, _from, state) do
    with {:ok, zona} <- buscar_zona(state.zonas, cod_zona),
         {:ok, zona_act} <- Zona.agregar_sector(zona, cod_sector, nombre_sector, nivel, afectados) do
      nuevo_estado = guardar_y_actualizar(state, zona_act)
      {:reply, {:ok, zona_act}, nuevo_estado}
    else
      {:error, motivo} -> {:reply, {:error, motivo}, state}
    end
  end

  @impl true
  def handle_call({:agregar_punto, cod_zona, cod_sector, cod_punto, nombre_punto, tipo}, _from, state) do
    with {:ok, zona} <- buscar_zona(state.zonas, cod_zona),
         {:ok, zona_act} <- Zona.agregar_punto_atencion(zona, cod_sector, cod_punto, nombre_punto, tipo) do
      nuevo_estado = guardar_y_actualizar(state, zona_act)
      {:reply, {:ok, zona_act}, nuevo_estado}
    else
      {:error, motivo} -> {:reply, {:error, motivo}, state}
    end
  end

  @impl true
  def handle_call({:asociar_entidad, cod_zona, categoria, id_entidad}, _from, state) do
    with {:ok, zona} <- buscar_zona(state.zonas, cod_zona),
         {:ok, zona_act} <- Zona.asociar_entidad(zona, categoria, id_entidad) do
      nuevo_estado = guardar_y_actualizar(state, zona_act)
      {:reply, {:ok, zona_act}, nuevo_estado}
    else
      {:error, motivo} -> {:reply, {:error, motivo}, state}
    end
  end

  @impl true
  def handle_call({:consultar_zona, cod_zona}, _from, state) do
    {:reply, buscar_zona(state.zonas, cod_zona), state}
  end

  @impl true
  def handle_call({:estadisticas_zona, cod_zona}, _from, state) do
    case buscar_zona(state.zonas, cod_zona) do
      {:ok, zona} -> {:reply, {:ok, Zona.calcular_estadisticas(zona)}, state}
      {:error, motivo} -> {:reply, {:error, motivo}, state}
    end
  end

  @impl true
  def handle_call({:buscar_punto, cod_zona, cod_punto}, _from, state) do
    case buscar_zona(state.zonas, cod_zona) do
      {:ok, zona} -> {:reply, Zona.buscar_punto_atencion(zona, cod_punto), state}
      {:error, motivo} -> {:reply, {:error, motivo}, state}
    end
  end

  @impl true
  def handle_call(:listar, _from, state) do
    {:reply, Map.values(state.zonas), state}
  end

  defp buscar_zona(zonas, cod_zona) do
    case Map.get(zonas, String.trim(to_string(cod_zona))) do
      nil -> {:error, :zona_no_encontrada}
      zona -> {:ok, zona}
    end
  end

  defp guardar_y_actualizar(state, %Zona{} = zona) do
    nuevas_zonas = Map.put(state.zonas, zona.codigo, zona)
    Persistencia.guardar_lista(@archivo, Map.values(nuevas_zonas), &Zona.a_linea/1, state.data_dir)
    %{state | zonas: nuevas_zonas}
  end
end
