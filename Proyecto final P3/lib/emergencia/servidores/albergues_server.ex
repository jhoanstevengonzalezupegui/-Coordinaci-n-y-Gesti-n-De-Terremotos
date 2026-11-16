defmodule Emergencia.Servidores.AlberguesServer do
  @moduledoc """
  GenServer encargado de la gestión de albergues temporales y control estricto de cupos.
  """
  use GenServer

  alias Emergencia.Modelos.Albergue
  alias Emergencia.Persistencia

  @archivo "albergues.txt"

  # --- API Cliente ---

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    data_dir = Keyword.get(opts, :data_dir, "data")
    GenServer.start_link(__MODULE__, %{data_dir: data_dir}, name: name)
  end

  def registrar_albergue(codigo, nombre, zona, capacidad_maxima, server \\ __MODULE__) do
    GenServer.call(server, {:registrar_albergue, codigo, nombre, zona, capacidad_maxima})
  end

  def registrar_ingreso(codigo_albergue, documento, server \\ __MODULE__) do
    GenServer.call(server, {:registrar_ingreso, codigo_albergue, documento})
  end

  def registrar_salida(codigo_albergue, documento, server \\ __MODULE__) do
    GenServer.call(server, {:registrar_salida, codigo_albergue, documento})
  end

  def consultar_albergue(codigo_albergue, server \\ __MODULE__) do
    GenServer.call(server, {:consultar_albergue, codigo_albergue})
  end

  def asociar_recurso(codigo_albergue, cod_recurso, server \\ __MODULE__) do
    GenServer.call(server, {:asociar_recurso, codigo_albergue, cod_recurso})
  end

  def asociar_necesidad(codigo_albergue, id_necesidad, server \\ __MODULE__) do
    GenServer.call(server, {:asociar_necesidad, codigo_albergue, id_necesidad})
  end

  def reporte_ocupacion(server \\ __MODULE__) do
    GenServer.call(server, :reporte_ocupacion)
  end

  def listar_albergues(server \\ __MODULE__) do
    GenServer.call(server, :listar)
  end

  # --- Callbacks GenServer ---

  @impl true
  def init(%{data_dir: data_dir}) do
    {:ok, lista} = Persistencia.cargar_lista(@archivo, &Albergue.desde_linea/1, data_dir)
    albergues = Map.new(lista, fn a -> {a.codigo, a} end)
    {:ok, %{albergues: albergues, data_dir: data_dir}}
  end

  @impl true
  def handle_call({:registrar_albergue, codigo, nombre, zona, capacidad}, _from, state) do
    cod_key = String.trim(to_string(codigo))

    if Map.has_key?(state.albergues, cod_key) do
      {:reply, {:error, :albergue_ya_existe}, state}
    else
      case Albergue.nuevo(cod_key, nombre, zona, capacidad) do
        {:ok, albergue} ->
          nuevo_estado = guardar_y_actualizar(state, albergue)
          {:reply, {:ok, albergue}, nuevo_estado}

        {:error, motivo} ->
          {:reply, {:error, motivo}, state}
      end
    end
  end

  @impl true
  def handle_call({:registrar_ingreso, codigo, documento}, _from, state) do
    with {:ok, alb} <- buscar_albergue(state.albergues, codigo),
         {:ok, alb_act} <- Albergue.registrar_ingreso(alb, documento) do
      nuevo_estado = guardar_y_actualizar(state, alb_act)
      {:reply, {:ok, alb_act}, nuevo_estado}
    else
      {:error, motivo} -> {:reply, {:error, motivo}, state}
    end
  end

  @impl true
  def handle_call({:registrar_salida, codigo, documento}, _from, state) do
    with {:ok, alb} <- buscar_albergue(state.albergues, codigo),
         {:ok, alb_act} <- Albergue.registrar_salida(alb, documento) do
      nuevo_estado = guardar_y_actualizar(state, alb_act)
      {:reply, {:ok, alb_act}, nuevo_estado}
    else
      {:error, motivo} -> {:reply, {:error, motivo}, state}
    end
  end

  @impl true
  def handle_call({:consultar_albergue, codigo}, _from, state) do
    case buscar_albergue(state.albergues, codigo) do
      {:ok, alb} ->
        info = %{
          albergue: alb,
          cupos_disponibles: Albergue.cupos_disponibles(alb),
          porcentaje_ocupacion: Albergue.porcentaje_ocupacion(alb)
        }

        {:reply, {:ok, info}, state}

      {:error, motivo} ->
        {:reply, {:error, motivo}, state}
    end
  end

  @impl true
  def handle_call({:asociar_recurso, codigo, cod_recurso}, _from, state) do
    with {:ok, alb} <- buscar_albergue(state.albergues, codigo),
         {:ok, alb_act} <- Albergue.asociar_recurso(alb, cod_recurso) do
      nuevo_estado = guardar_y_actualizar(state, alb_act)
      {:reply, {:ok, alb_act}, nuevo_estado}
    else
      {:error, motivo} -> {:reply, {:error, motivo}, state}
    end
  end

  @impl true
  def handle_call({:asociar_necesidad, codigo, id_necesidad}, _from, state) do
    with {:ok, alb} <- buscar_albergue(state.albergues, codigo),
         {:ok, alb_act} <- Albergue.asociar_necesidad(alb, id_necesidad) do
      nuevo_estado = guardar_y_actualizar(state, alb_act)
      {:reply, {:ok, alb_act}, nuevo_estado}
    else
      {:error, motivo} -> {:reply, {:error, motivo}, state}
    end
  end

  @impl true
  def handle_call(:reporte_ocupacion, _from, state) do
    reporte = Albergue.reporte_mayor_ocupacion(Map.values(state.albergues))
    {:reply, reporte, state}
  end

  @impl true
  def handle_call(:listar, _from, state) do
    {:reply, Map.values(state.albergues), state}
  end

  defp buscar_albergue(albergues, codigo) do
    case Map.get(albergues, String.trim(to_string(codigo))) do
      nil -> {:error, :albergue_no_encontrado}
      alb -> {:ok, alb}
    end
  end

  defp guardar_y_actualizar(state, %Albergue{} = albergue) do
    nuevos = Map.put(state.albergues, albergue.codigo, albergue)
    Persistencia.guardar_lista(@archivo, Map.values(nuevos), &Albergue.a_linea/1, state.data_dir)
    %{state | albergues: nuevos}
  end
end
