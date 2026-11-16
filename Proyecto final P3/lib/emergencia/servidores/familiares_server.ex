defmodule Emergencia.Servidores.FamiliaresServer do
  @moduledoc """
  GenServer encargado de la localización de personas afectadas y mensajes entre familiares.
  """
  use GenServer

  alias Emergencia.Modelos.{Mensaje, Persona}
  alias Emergencia.{Persistencia, Util}

  @archivo_personas "personas.txt"
  @archivo_mensajes "mensajes.txt"

  # --- API Cliente ---

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    data_dir = Keyword.get(opts, :data_dir, "data")
    GenServer.start_link(__MODULE__, %{data_dir: data_dir}, name: name)
  end

  def registrar_persona(documento, nombre, zona, estado \\ :reportada, edad \\ 0, server \\ __MODULE__) do
    GenServer.call(server, {:registrar_persona, documento, nombre, zona, estado, edad})
  end

  def reportar_o_actualizar_persona(documento, nombre, zona, estado \\ :reportada, edad \\ 0, server \\ __MODULE__) do
    GenServer.call(server, {:reportar_o_actualizar, documento, nombre, zona, estado, edad})
  end

  def actualizar_estado_persona(documento, nuevo_estado, detalle \\ "", server \\ __MODULE__) do
    GenServer.call(server, {:actualizar_estado, documento, nuevo_estado, detalle})
  end

  def buscar_por_documento(documento, server \\ __MODULE__) do
    GenServer.call(server, {:buscar_documento, documento})
  end

  def buscar_personas(filtros \\ %{}, server \\ __MODULE__) do
    GenServer.call(server, {:buscar_personas, filtros})
  end

  def listar_personas(server \\ __MODULE__) do
    GenServer.call(server, :listar_personas)
  end

  def enviar_mensaje(remitente, destinatario, contenido, server \\ __MODULE__) do
    GenServer.call(server, {:enviar_mensaje, remitente, destinatario, contenido})
  end

  def marcar_mensaje_entregado(id_mensaje, server \\ __MODULE__) do
    GenServer.call(server, {:marcar_entregado, id_mensaje})
  end

  def listar_mensajes(destinatario \\ nil, server \\ __MODULE__) do
    GenServer.call(server, {:listar_mensajes, destinatario})
  end

  # --- Callbacks GenServer ---

  @impl true
  def init(%{data_dir: data_dir}) do
    {:ok, lista_p} = Persistencia.cargar_lista(@archivo_personas, &Persona.desde_linea/1, data_dir)
    {:ok, lista_m} = Persistencia.cargar_lista(@archivo_mensajes, &Mensaje.desde_linea/1, data_dir)

    personas = Map.new(lista_p, fn p -> {p.documento, p} end)
    mensajes = Map.new(lista_m, fn m -> {m.id, m} end)

    {:ok, %{personas: personas, mensajes: mensajes, data_dir: data_dir}}
  end

  @impl true
  def handle_call({:registrar_persona, documento, nombre, zona, estado, edad}, _from, state) do
    doc_key = String.trim(to_string(documento))

    if Map.has_key?(state.personas, doc_key) do
      {:reply, {:error, :persona_ya_registrada}, state}
    else
      id_nuevo = Util.generar_id("P", Enum.map(Map.values(state.personas), & &1.id))

      case Persona.nueva(id_nuevo, nombre, doc_key, edad, zona, estado) do
        {:ok, persona} ->
          nuevo_estado = guardar_personas(state, Map.put(state.personas, doc_key, persona))
          {:reply, {:ok, persona}, nuevo_estado}

        {:error, motivo} ->
          {:reply, {:error, motivo}, state}
      end
    end
  end

  @impl true
  def handle_call({:reportar_o_actualizar, documento, nombre, zona, estado, edad}, _from, state) do
    doc_key = String.trim(to_string(documento))

    case Map.get(state.personas, doc_key) do
      nil ->
        id_nuevo = Util.generar_id("P", Enum.map(Map.values(state.personas), & &1.id))

        case Persona.nueva(id_nuevo, nombre, doc_key, edad, zona, estado) do
          {:ok, persona} ->
            nuevo_estado = guardar_personas(state, Map.put(state.personas, doc_key, persona))
            {:reply, {:ok, persona}, nuevo_estado}

          {:error, motivo} ->
            {:reply, {:error, motivo}, state}
        end

      persona_existente ->
        case Persona.actualizar_estado(persona_existente, estado, "Actualizado en zona #{zona}") do
          {:ok, persona_act} ->
            persona_final = %{persona_act | zona: String.trim(to_string(zona))}
            nuevo_estado = guardar_personas(state, Map.put(state.personas, doc_key, persona_final))
            {:reply, {:ok, persona_final}, nuevo_estado}

          {:error, motivo} ->
            {:reply, {:error, motivo}, state}
        end
    end
  end

  @impl true
  def handle_call({:actualizar_estado, documento, nuevo_estado, detalle}, _from, state) do
    doc_key = String.trim(to_string(documento))

    case Map.get(state.personas, doc_key) do
      nil ->
        {:reply, {:error, :persona_no_encontrada}, state}

      persona ->
        case Persona.actualizar_estado(persona, nuevo_estado, detalle) do
          {:ok, persona_act} ->
            estado_guardado = guardar_personas(state, Map.put(state.personas, doc_key, persona_act))
            {:reply, {:ok, persona_act}, estado_guardado}

          {:error, motivo} ->
            {:reply, {:error, motivo}, state}
        end
    end
  end

  @impl true
  def handle_call({:buscar_documento, documento}, _from, state) do
    case Map.get(state.personas, String.trim(to_string(documento))) do
      nil -> {:reply, {:error, :persona_no_encontrada}, state}
      persona -> {:reply, {:ok, persona}, state}
    end
  end

  @impl true
  def handle_call({:buscar_personas, filtros}, _from, state) do
    coincidencias =
      state.personas
      |> Map.values()
      |> Enum.filter(&Persona.coincide_filtros?(&1, filtros))

    {:reply, coincidencias, state}
  end

  @impl true
  def handle_call(:listar_personas, _from, state) do
    {:reply, Map.values(state.personas), state}
  end

  @impl true
  def handle_call({:enviar_mensaje, remitente, destinatario, contenido}, _from, state) do
    id_msg = Util.generar_id("MSG", Map.keys(state.mensajes))

    case Mensaje.nuevo(id_msg, remitente, destinatario, contenido) do
      {:ok, mensaje} ->
        nuevo_estado = guardar_mensajes(state, Map.put(state.mensajes, id_msg, mensaje))
        {:reply, {:ok, mensaje}, nuevo_estado}

      {:error, motivo} ->
        {:reply, {:error, motivo}, state}
    end
  end

  @impl true
  def handle_call({:marcar_entregado, id_mensaje}, _from, state) do
    case Map.get(state.mensajes, String.trim(to_string(id_mensaje))) do
      nil ->
        {:reply, {:error, :mensaje_no_encontrado}, state}

      msg ->
        case Mensaje.marcar_entregado(msg) do
          {:ok, msg_act} ->
            nuevo_estado = guardar_mensajes(state, Map.put(state.mensajes, msg_act.id, msg_act))
            {:reply, {:ok, msg_act}, nuevo_estado}

          {:error, motivo} ->
            {:reply, {:error, motivo}, state}
        end
    end
  end

  @impl true
  def handle_call({:listar_mensajes, nil}, _from, state) do
    {:reply, Map.values(state.mensajes), state}
  end

  @impl true
  def handle_call({:listar_mensajes, destinatario}, _from, state) do
    dest_norm = String.downcase(String.trim(to_string(destinatario)))

    filtrados =
      state.mensajes
      |> Map.values()
      |> Enum.filter(fn m -> String.downcase(m.destinatario) == dest_norm end)

    {:reply, filtrados, state}
  end

  defp guardar_personas(state, nuevas_personas) do
    Persistencia.guardar_lista(@archivo_personas, Map.values(nuevas_personas), &Persona.a_linea/1, state.data_dir)
    %{state | personas: nuevas_personas}
  end

  defp guardar_mensajes(state, nuevos_mensajes) do
    Persistencia.guardar_lista(@archivo_mensajes, Map.values(nuevos_mensajes), &Mensaje.a_linea/1, state.data_dir)
    %{state | mensajes: nuevos_mensajes}
  end
end
