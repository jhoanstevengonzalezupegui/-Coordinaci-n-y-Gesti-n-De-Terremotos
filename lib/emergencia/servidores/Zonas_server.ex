defmodule Zonas_server do
  use GenServer

  @ruta_archivo "data/zonas.txt"

  # ==========================================
  # API del Cliente
  # ==========================================

  def start_link(_args) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def registrar_zona(datos) do
    GenServer.call(__MODULE__, {:registrar_zona, datos})
  end

  def agregar_sector(codigo_zona, nombre_sector, puntos_atencion) do
    GenServer.call(__MODULE__, {:agregar_sector, codigo_zona, nombre_sector, puntos_atencion})
  end

  def estadisticas_zona(codigo_zona) do
    GenServer.call(__MODULE__, {:estadisticas, codigo_zona})
  end

  def listar_zonas() do
    GenServer.call(__MODULE__, :listar)
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
  def handle_call({:registrar_zona, datos}, _from, estado_actual) do
    if Enum.any?(estado_actual, fn z -> z.codigo == datos[:codigo] end) do
      {:reply, {:error, "El código de zona ya existe"}, estado_actual}
    else
      case Zona.crear(datos) do
        {:ok, nueva_zona} ->
          nuevo_estado = [nueva_zona | estado_actual]
          Persistencia.guardar(@ruta_archivo, nuevo_estado)
          {:reply, {:ok, "Zona registrada correctamente", nueva_zona}, nuevo_estado}

        {:error, motivo} ->
          {:reply, {:error, motivo}, estado_actual}
      end
    end
  end

  @impl true
  def handle_call({:agregar_sector, codigo_zona, nombre_sector, puntos_atencion}, _from, estado_actual) do
    case Enum.find(estado_actual, fn z -> z.codigo == codigo_zona end) do
      nil ->
        {:reply, {:error, "Zona no encontrada"}, estado_actual}

      zona ->
        nuevo_sector = %{nombre: nombre_sector, puntos: puntos_atencion}
        zona_actualizada = %{zona | sectores: [nuevo_sector | zona.sectores]}

        nuevo_estado = Enum.map(estado_actual, fn z ->
          if z.codigo == codigo_zona, do: zona_actualizada, else: z
        end)

        Persistencia.guardar(@ruta_archivo, nuevo_estado)
        {:reply, {:ok, "Sector agregado a la zona", zona_actualizada}, nuevo_estado}
    end
  end

  @impl true
  def handle_call({:estadisticas, codigo_zona}, _from, estado_actual) do
    case Enum.find(estado_actual, fn z -> z.codigo == codigo_zona end) do
      nil ->
        {:reply, {:error, "Zona no encontrada"}, estado_actual}

      zona ->
        total_puntos = Zona.contar_puntos_zona(zona)
        resumen = %{
          codigo: zona.codigo,
          nombre: zona.nombre,
          nivel: zona.nivel,
          personas_afectadas: zona.personas_afectadas,
          total_sectores: length(zona.sectores),
          total_puntos_atencion: total_puntos
        }
        {:reply, {:ok, resumen}, estado_actual}
    end
  end

  @impl true
  def handle_call(:listar, _from, estado_actual) do
    {:reply, {:ok, estado_actual}, estado_actual}
  end
end
