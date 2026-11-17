defmodule FamiliaresServer do
  use GenServer

  @ruta_archivo "data/mensajes.txt"

  # ==========================================
  # API del Cliente
  # ==========================================

  def start_link(_args) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def enviar(id, remitente, destinatario, contenido) do
    GenServer.call(__MODULE__, {:enviar, id, remitente, destinatario, contenido})
  end

  def listar_por_documento(documento) do
    GenServer.call(__MODULE__, {:listar, documento})
  end

  def marcar_entregado(id_mensaje) do
    GenServer.call(__MODULE__, {:marcar_entregado, id_mensaje})
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
  def handle_call({:enviar, id, remitente, destinatario, contenido}, _from, estado_actual) do
    # Preparamos el mapa con los datos requeridos por tu modelo
    datos = %{
      id: id,
      fecha: Date.utc_today(),
      remitente: remitente,
      destinatario: destinatario,
      contenido: contenido
    }

    case Mensaje.crear(datos) do
      {:ok, nuevo_mensaje} ->
        nuevo_estado = [nuevo_mensaje | estado_actual]
        Persistencia.guardar(@ruta_archivo, nuevo_estado)
        {:reply, {:ok, "Mensaje enviado exitosamente", nuevo_mensaje}, nuevo_estado}

      {:error, motivo} ->
        {:reply, {:error, motivo}, estado_actual}
    end
  end

  @impl true
  def handle_call({:listar, documento}, _from, estado_actual) do
    # Delegamos la lógica de filtrado a tu modelo puro
    {:ok, filtrados} = Mensaje.listar_por_documento(estado_actual, documento)
    {:reply, {:ok, filtrados}, estado_actual}
  end

  @impl true
  def handle_call({:marcar_entregado, id_mensaje}, _from, estado_actual) do
    # Actualizamos la lista de forma inmutable usando tu modelo
    {:ok, nuevo_estado} = Mensaje.marcar_entregado(estado_actual, id_mensaje)

    Persistencia.guardar(@ruta_archivo, nuevo_estado)
    {:reply, {:ok, "Mensaje marcado como entregado"}, nuevo_estado}
  end
end
