defmodule Emergencia.Modelos.Usuario do
  @moduledoc """
  Modelo de dominio para los usuarios del sistema de gestión de emergencias.
  """

  @roles_validos [:ciudadano, :voluntario, :coordinador, :administrador]

  defstruct [
    :username,
    :password,
    :nombre_completo,
    :rol,
    :zona_principal,
    conectado: false,
    historial_actividad: []
  ]

  @doc """
  Crea un nuevo usuario validando campos obligatorios y roles permitidos.
  Retorna {:ok, %Usuario{}} o {:error, motivo}.
  """
  def nuevo(username, password, nombre_completo, rol, zona_principal) do
    rol_atom = normalizar_rol(rol)

    cond do
      is_nil(username) or String.trim(to_string(username)) == "" ->
        {:error, :username_invalido}

      is_nil(password) or String.trim(to_string(password)) == "" ->
        {:error, :password_invalido}

      is_nil(nombre_completo) or String.trim(to_string(nombre_completo)) == "" ->
        {:error, :nombre_invalido}

      rol_atom not in @roles_validos ->
        {:error, :rol_invalido}

      is_nil(zona_principal) or String.trim(to_string(zona_principal)) == "" ->
        {:error, :zona_invalida}

      true ->
        usuario = %__MODULE__{
          username: String.trim(to_string(username)),
          password: to_string(password),
          nombre_completo: String.trim(to_string(nombre_completo)),
          rol: rol_atom,
          zona_principal: String.trim(to_string(zona_principal)),
          conectado: true,
          historial_actividad: [{timestamp_actual(), "Registro y conexión inicial"}]
        }

        {:ok, usuario}
    end
  end

  def validar_credenciales(%__MODULE__{password: pass}, password_ingresado)
      when pass == password_ingresado,
      do: :ok

  def validar_credenciales(%__MODULE__{}, _password_ingresado),
    do: {:error, :credenciales_invalidas}

  def conectar(%__MODULE__{} = usuario) do
    %{usuario | conectado: true}
    |> registrar_actividad("Inicio de sesión")
  end

  def desconectar(%__MODULE__{} = usuario) do
    %{usuario | conectado: false}
    |> registrar_actividad("Cierre de sesión")
  end

  def registrar_actividad(%__MODULE__{historial_actividad: hist} = usuario, accion) do
    nuevo_registro = {timestamp_actual(), accion}
    %{usuario | historial_actividad: [nuevo_registro | hist]}
  end

  @doc """
  Verifica si el rol del usuario tiene permiso para ejecutar una operación.
  """
  def puede_ejecutar?(%__MODULE__{conectado: false}, _accion), do: false
  def puede_ejecutar?(%__MODULE__{rol: :administrador}, _accion), do: true

  def puede_ejecutar?(%__MODULE__{rol: :coordinador}, accion)
      when accion in [
             :registrar_zona,
             :registrar_necesidad,
             :asignar_recurso,
             :registrar_recurso,
             :transferir_recurso,
             :registrar_albergue,
             :gestionar_albergue,
             :reportar_persona,
             :enviar_mensaje,
             :reportar_mascota,
             :confirmar_mascota,
             :consultar
           ],
      do: true

  def puede_ejecutar?(%__MODULE__{rol: :voluntario}, accion)
      when accion in [
             :registrar_necesidad,
             :transferir_recurso,
             :gestionar_albergue,
             :reportar_persona,
             :enviar_mensaje,
             :reportar_mascota,
             :confirmar_mascota,
             :consultar
           ],
      do: true

  def puede_ejecutar?(%__MODULE__{rol: :ciudadano}, accion)
      when accion in [
             :registrar_necesidad,
             :reportar_persona,
             :enviar_mensaje,
             :reportar_mascota,
             :consultar
           ],
      do: true

  def puede_ejecutar?(_, _), do: false

  @doc """
  Serializa el usuario a una línea de texto plano para persistencia.
  """
  def a_linea(%__MODULE__{} = u) do
    historial_str =
      u.historial_actividad
      |> Enum.map(fn {ts, act} -> "#{ts}~#{String.replace(act, "|", "/")}" end)
      |> Enum.join(";")

    [
      u.username,
      u.password,
      String.replace(u.nombre_completo, "|", "/"),
      Atom.to_string(u.rol),
      u.zona_principal,
      Atom.to_string(u.conectado),
      historial_str
    ]
    |> Enum.join("|")
  end

  def desde_linea(linea) do
    case String.split(String.trim(linea), "|") do
      [username, password, nombre, rol, zona, conectado, historial_str] ->
        historial =
          if historial_str == "" do
            []
          else
            historial_str
            |> String.split(";")
            |> Enum.map(fn item ->
              case String.split(item, "~", parts: 2) do
                [ts, act] -> {ts, act}
                [act] -> {"sin_fecha", act}
              end
            end)
          end

        {:ok,
         %__MODULE__{
           username: username,
           password: password,
           nombre_completo: nombre,
           rol: String.to_existing_atom(rol),
           zona_principal: zona,
           conectado: conectado == "true",
           historial_actividad: historial
         }}

      _ ->
        {:error, :formato_usuario_invalido}
    end
  end

  defp normalizar_rol(rol) when is_atom(rol) and rol in @roles_validos, do: rol

  defp normalizar_rol(rol) when is_binary(rol) do
    case String.downcase(String.trim(rol)) do
      "ciudadano" -> :ciudadano
      "voluntario" -> :voluntario
      "coordinador" -> :coordinador
      "administrador" -> :administrador
      _ -> :invalido
    end
  end

  defp normalizar_rol(_), do: :invalido

  defp timestamp_actual do
    DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
  end
end
