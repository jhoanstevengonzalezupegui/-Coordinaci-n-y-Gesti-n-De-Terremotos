defmodule Usuarios_server do
  use GenServer

  @ruta_archivo "data/usuarios.txt"

  # ==========================================
  # API del Cliente
  # ==========================================

  def start_link(_args) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def conectar(username, password, tipo \\ :ciudadano, zona \\ "general") do
    GenServer.call(__MODULE__, {:conectar, username, password, tipo, zona})
  end

  def desconectar(username) do
    GenServer.call(__MODULE__, {:desconectar, username})
  end

  def registrar_actividad(username, accion) do
    GenServer.call(__MODULE__, {:actividad, username, accion})
  end

  def listar_usuarios() do
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
  def handle_call({:conectar, username, password, tipo, zona}, _from, estado_actual) do
    case Enum.find(estado_actual, fn u -> u.username == username end) do
      nil ->
        # Registro automático si no existe
        datos = %{
          username: username,
          password: password,
          nombre_completo: username,
          tipo: tipo,
          zona_principal: zona,
          activo: true
        }

        case Usuario.crear(datos) do
          {:ok, nuevo_usuario} ->
            usuario_con_log = Usuario.registrar_actividad(nuevo_usuario, "Registro y conexión automática")
            nuevo_estado = [usuario_con_log | estado_actual]
            Persistencia.guardar(@ruta_archivo, nuevo_estado)
            {:reply, {:ok, "Usuario registrado y conectado", usuario_con_log}, nuevo_estado}

          {:error, motivo} ->
            {:reply, {:error, motivo}, estado_actual}
        end

      usuario_existente ->
        if usuario_existente.password == password do
          actualizado = %{usuario_existente | activo: true}
                        |> Usuario.registrar_actividad("Inicio de sesión")

          nuevo_estado = Enum.map(estado_actual, fn u ->
            if u.username == username, do: actualizado, else: u
          end)

          Persistencia.guardar(@ruta_archivo, nuevo_estado)
          {:reply, {:ok, "Conexión exitosa", actualizado}, nuevo_estado}
        else
          {:reply, {:error, "Contraseña incorrecta"}, estado_actual}
        end
    end
  end

  @impl true
  def handle_call({:desconectar, username}, _from, estado_actual) do
    nuevo_estado = Enum.map(estado_actual, fn u ->
      if u.username == username do
        %{u | activo: false} |> Usuario.registrar_actividad("Desconexión")
      else
        u
      end
    end)

    Persistencia.guardar(@ruta_archivo, nuevo_estado)
    {:reply, {:ok, "Usuario #{username} desconectado"}, nuevo_estado}
  end

  @impl true
  def handle_call({:actividad, username, accion}, _from, estado_actual) do
    nuevo_estado = Enum.map(estado_actual, fn u ->
      if u.username == username, do: Usuario.registrar_actividad(u, accion), else: u
    end)

    Persistencia.guardar(@ruta_archivo, nuevo_estado)
    {:reply, :ok, nuevo_estado}
  end

  @impl true
  def handle_call(:listar, _from, estado_actual) do
    {:reply, {:ok, estado_actual}, estado_actual}
  end
end
