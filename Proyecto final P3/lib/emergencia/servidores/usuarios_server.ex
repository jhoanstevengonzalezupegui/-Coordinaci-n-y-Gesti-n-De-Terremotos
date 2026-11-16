defmodule Emergencia.Servidores.UsuariosServer do
  @moduledoc """
  GenServer encargado de la autenticación, sesiones, roles y bitácora de usuarios.
  """
  use GenServer

  alias Emergencia.Modelos.Usuario
  alias Emergencia.Persistencia

  @archivo "usuarios.txt"

  # --- API Cliente ---

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    data_dir = Keyword.get(opts, :data_dir, "data")
    GenServer.start_link(__MODULE__, %{data_dir: data_dir}, name: name)
  end

  def connect(username, password, rol \\ :ciudadano, zona \\ "general", nombre \\ nil, server \\ __MODULE__) do
    GenServer.call(server, {:connect, username, password, rol, zona, nombre})
  end

  def disconnect(username, server \\ __MODULE__) do
    GenServer.call(server, {:disconnect, username})
  end

  def registrar_usuario(username, password, nombre_completo, rol, zona_principal, server \\ __MODULE__) do
    GenServer.call(server, {:registrar, username, password, nombre_completo, rol, zona_principal})
  end

  def autorizar(username, accion, server \\ __MODULE__) do
    GenServer.call(server, {:autorizar, username, accion})
  end

  def registrar_actividad(username, accion, server \\ __MODULE__) do
    GenServer.call(server, {:registrar_actividad, username, accion})
  end

  def obtener_usuario(username, server \\ __MODULE__) do
    GenServer.call(server, {:obtener, username})
  end

  def listar_usuarios(server \\ __MODULE__) do
    GenServer.call(server, :listar)
  end

  # --- Callbacks GenServer ---

  @impl true
  def init(%{data_dir: data_dir}) do
    {:ok, lista} = Persistencia.cargar_lista(@archivo, &Usuario.desde_linea/1, data_dir)
    usuarios = Map.new(lista, fn u -> {u.username, u} end)
    {:ok, %{usuarios: usuarios, data_dir: data_dir}}
  end

  @impl true
  def handle_call({:connect, username, password, rol, zona, nombre}, _from, state) do
    user_key = String.trim(to_string(username))

    case Map.get(state.usuarios, user_key) do
      nil ->
        nombre_final = nombre || user_key

        case Usuario.nuevo(user_key, password, nombre_final, rol, zona) do
          {:ok, nuevo_usuario} ->
            nuevo_estado = guardar_y_actualizar(state, nuevo_usuario)
            {:reply, {:ok, :registrado_y_conectado, nuevo_usuario}, nuevo_estado}

          {:error, motivo} ->
            {:reply, {:error, motivo}, state}
        end

      usuario_existente ->
        case Usuario.validar_credenciales(usuario_existente, to_string(password)) do
          :ok ->
            usuario_conectado = Usuario.conectar(usuario_existente)
            nuevo_estado = guardar_y_actualizar(state, usuario_conectado)
            {:reply, {:ok, :conectado, usuario_conectado}, nuevo_estado}

          {:error, motivo} ->
            {:reply, {:error, motivo}, state}
        end
    end
  end

  @impl true
  def handle_call({:disconnect, username}, _from, state) do
    case Map.get(state.usuarios, to_string(username)) do
      nil ->
        {:reply, {:error, :usuario_no_encontrado}, state}

      %{conectado: false} ->
        {:reply, {:error, :usuario_ya_desconectado}, state}

      usuario ->
        usuario_desc = Usuario.desconectar(usuario)
        nuevo_estado = guardar_y_actualizar(state, usuario_desc)
        {:reply, {:ok, usuario_desc}, nuevo_estado}
    end
  end

  @impl true
  def handle_call({:registrar, username, password, nombre, rol, zona}, _from, state) do
    user_key = String.trim(to_string(username))

    if Map.has_key?(state.usuarios, user_key) do
      {:reply, {:error, :usuario_ya_existe}, state}
    else
      case Usuario.nuevo(user_key, password, nombre, rol, zona) do
        {:ok, usuario} ->
          nuevo_estado = guardar_y_actualizar(state, usuario)
          {:reply, {:ok, usuario}, nuevo_estado}

        {:error, motivo} ->
          {:reply, {:error, motivo}, state}
      end
    end
  end

  @impl true
  def handle_call({:autorizar, username, accion}, _from, state) do
    case Map.get(state.usuarios, to_string(username)) do
      nil ->
        {:reply, {:error, :usuario_no_autenticado}, state}

      %{conectado: false} ->
        {:reply, {:error, :sesion_inactiva}, state}

      usuario ->
        if Usuario.puede_ejecutar?(usuario, accion) do
          {:reply, {:ok, usuario}, state}
        else
          {:reply, {:error, :permiso_denegado}, state}
        end
    end
  end

  @impl true
  def handle_call({:registrar_actividad, username, accion}, _from, state) do
    case Map.get(state.usuarios, to_string(username)) do
      nil ->
        {:reply, {:error, :usuario_no_encontrado}, state}

      usuario ->
        actualizado = Usuario.registrar_actividad(usuario, accion)
        nuevo_estado = guardar_y_actualizar(state, actualizado)
        {:reply, {:ok, actualizado}, nuevo_estado}
    end
  end

  @impl true
  def handle_call({:obtener, username}, _from, state) do
    case Map.get(state.usuarios, to_string(username)) do
      nil -> {:reply, {:error, :usuario_no_encontrado}, state}
      usuario -> {:reply, {:ok, usuario}, state}
    end
  end

  @impl true
  def handle_call(:listar, _from, state) do
    {:reply, Map.values(state.usuarios), state}
  end

  defp guardar_y_actualizar(state, %Usuario{} = usuario) do
    nuevos_usuarios = Map.put(state.usuarios, usuario.username, usuario)
    Persistencia.guardar_lista(@archivo, Map.values(nuevos_usuarios), &Usuario.a_linea/1, state.data_dir)
    %{state | usuarios: nuevos_usuarios}
  end
end
