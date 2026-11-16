defmodule Albergues_server do
  use GenServer

  @ruta_archivo "data/albergues.txt"

  # ==========================================
  # API del Cliente
  # ==========================================

  def start_link(_args) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def registrar_albergue(datos) do
    GenServer.call(__MODULE__, {:registrar, datos})
  end

  def registrar_ingreso(codigo_albergue, documento_persona) do
    GenServer.call(__MODULE__, {:ingreso, codigo_albergue, documento_persona})
  end

  def registrar_salida(codigo_albergue, documento_persona) do
    GenServer.call(__MODULE__, {:salida, codigo_albergue, documento_persona})
  end

  def consultar_albergue(codigo_albergue) do
    GenServer.call(__MODULE__, {:consultar, codigo_albergue})
  end

  def reporte_mayor_ocupacion() do
    GenServer.call(__MODULE__, :reporte_ocupacion)
  end

  # ==========================================
  # Callbacks del Servidor
  # ==========================================

  @impl true
  def init(_args) do
    estado_inicial = case Persistencia.cargar(@ruta_archivo) do
      {:ok, datos} -> datos
      _error -> []
    end

    {:ok, estado_inicial}
  end

  @impl true
  def handle_call({:registrar, datos}, _from, estado_actual) do
    if Enum.any?(estado_actual, fn a -> a.codigo == datos[:codigo] end) do
      {:reply, {:error, "El código de albergue ya existe"}, estado_actual}
    else
      case Albergue.crear(datos) do
        {:ok, nuevo_albergue} ->
          nuevo_estado = [nuevo_albergue | estado_actual]
          Persistencia.guardar(@ruta_archivo, nuevo_estado)
          {:reply, {:ok, "Albergue registrado exitosamente", nuevo_albergue}, nuevo_estado}

        {:error, motivo} ->
          {:reply, {:error, motivo}, estado_actual}
      end
    end
  end

  @impl true
  def handle_call({:ingreso, codigo_albergue, documento}, _from, estado_actual) do
    case Enum.find(estado_actual, fn a -> a.codigo == codigo_albergue end) do
      nil ->
        {:reply, {:error, "Albergue no encontrado"}, estado_actual}

      albergue ->
        cond do
          documento in albergue.personas ->
            {:reply, {:error, "La persona ya se encuentra registrada en este albergue"}, estado_actual}

          albergue.ocupacion_actual >= albergue.capacidad_maxima ->
            {:reply, {:error, "Capacidad máxima alcanzada. No hay cupos disponibles"}, estado_actual}

          true ->
            actualizado = %{
              albergue |
              ocupacion_actual: albergue.ocupacion_actual + 1,
              personas: [documento | albergue.personas]
            }

            nuevo_estado = Enum.map(estado_actual, fn a ->
              if a.codigo == codigo_albergue, do: actualizado, else: a
            end)

            Persistencia.guardar(@ruta_archivo, nuevo_estado)
            {:reply, {:ok, "Ingreso registrado. Cupos restantes: #{Albergue.cupos_disponibles(actualizado)}"}, nuevo_estado}
        end
    end
  end

  @impl true
  def handle_call({:salida, codigo_albergue, documento}, _from, estado_actual) do
    case Enum.find(estado_actual, fn a -> a.codigo == codigo_albergue end) do
      nil ->
        {:reply, {:error, "Albergue no encontrado"}, estado_actual}

      albergue ->
        if documento in albergue.personas do
          actualizado = %{
            albergue |
            ocupacion_actual: max(0, albergue.ocupacion_actual - 1),
            personas: List.delete(albergue.personas, documento)
          }

          nuevo_estado = Enum.map(estado_actual, fn a ->
            if a.codigo == codigo_albergue, do: actualizado, else: a
          end)

          Persistencia.guardar(@ruta_archivo, nuevo_estado)
          {:reply, {:ok, "Salida registrada exitosamente"}, nuevo_estado}
        else
          {:reply, {:error, "La persona no está registrada en este albergue"}, estado_actual}
        end
    end
  end

  @impl true
  def handle_call({:consultar, codigo_albergue}, _from, estado_actual) do
    case Enum.find(estado_actual, fn a -> a.codigo == codigo_albergue end) do
      nil -> {:reply, {:error, "Albergue no encontrado"}, estado_actual}
      albergue -> {:reply, {:ok, albergue, Albergue.cupos_disponibles(albergue)}, estado_actual}
    end
  end

  @impl true
  def handle_call(:reporte_ocupacion, _from, estado_actual) do
    ordenados = Enum.sort_by(estado_actual, fn a ->
      a.ocupacion_actual / a.capacidad_maxima
    end, :desc)

    {:reply, {:ok, ordenados}, estado_actual}
  end
end
