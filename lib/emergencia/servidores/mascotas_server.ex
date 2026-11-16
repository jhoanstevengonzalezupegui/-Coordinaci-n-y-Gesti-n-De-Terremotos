defmodule MascotasServer do
  use GenServer

  @ruta_archivo "data/mascotas.txt"

  # ==========================================
  # API del Cliente (Funciones que llamas tú o tus compañeros)
  # ==========================================

  @doc """
  Inicia el servidor. Se llamará automáticamente desde el supervisor (application.ex).
  """
  def start_link(_args) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Envía la solicitud para reportar una nueva mascota.
  """
  def reportar(datos) do
    GenServer.call(__MODULE__, {:reportar, datos})
  end

  @doc """
  Pide al servidor la lista actual de todas las mascotas.
  """
  def listar_todas() do
    GenServer.call(__MODULE__, :listar_todas)
  end

  @doc """
  Pide al servidor que ejecute el algoritmo de coincidencias.
  """
  def buscar_coincidencias() do
    GenServer.call(__MODULE__, :buscar_coincidencias)
  end

  # ==========================================
  # Callbacks del Servidor (Lógica interna concurrente)
  # ==========================================

  @impl true
  def init(_args) do
    # Cuando el servidor arranca, cargamos los datos del archivo de texto
    estado_inicial = case Persistencia.cargar(@ruta_archivo) do
      {:ok, datos} -> datos
      _error -> []
    end

    {:ok, estado_inicial}
  end

  @impl true
  def handle_call({:reportar, datos}, _from, estado_actual) do
    case Mascota.crear(datos) do
      {:ok, nueva_mascota} ->
        nuevo_estado = [nueva_mascota | estado_actual]

        # Guardamos en el archivo .txt para que haya persistencia
        Persistencia.guardar(@ruta_archivo, nuevo_estado)

        {:reply, {:ok, "Mascota reportada con éxito", nueva_mascota}, nuevo_estado}

      {:error, motivo} ->
        # Si faltan campos, no modificamos el estado ni guardamos
        {:reply, {:error, motivo}, estado_actual}
    end
  end

  @impl true
  def handle_call(:listar_todas, _from, estado_actual) do
    # Simplemente devolvemos el estado que tenemos en memoria
    {:reply, {:ok, estado_actual}, estado_actual}
  end

  @impl true
  def handle_call(:buscar_coincidencias, _from, estado_actual) do
    # Separamos las listas en memoria
    {:ok, perdidas} = Mascota.filtrar(estado_actual, %{tipo_reporte: :perdida, estado: :activa})
    {:ok, encontradas} = Mascota.filtrar(estado_actual, %{tipo_reporte: :encontrada, estado: :activa})

    # Llamamos a tu algoritmo recursivo
    {:ok, matches} = Coincidencias.buscar(perdidas, encontradas)

    {:reply, {:ok, matches}, estado_actual}
  end
end
