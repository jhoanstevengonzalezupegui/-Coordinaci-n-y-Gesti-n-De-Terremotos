defmodule Mensaje do
  @moduledoc """
  Modelo para la comunicación y mensajes entre familiares.
  """

  @enforce_keys [:id, :fecha, :remitente, :destinatario, :contenido]
  defstruct [
    :id,
    :fecha,
    :remitente,
    :destinatario, # Documento de la persona a la que va dirigido
    :contenido,
    estado: :pendiente # :pendiente o :entregado
  ]

  @doc """
  Crea un nuevo mensaje validando los campos.
  """
  def crear(datos) when is_map(datos) do
    campos_requeridos = [:id, :fecha, :remitente, :destinatario, :contenido]
    faltantes = Enum.reject(campos_requeridos, fn c -> Map.has_key?(datos, c) end)

    if Enum.empty?(faltantes) do
      mensaje = struct(__MODULE__, datos)
      {:ok, mensaje}
    else
      {:error, "Faltan campos: #{inspect(faltantes)}"}
    end
  end

  @doc """
  Filtra los mensajes dirigidos a un documento específico.
  """
  def listar_por_documento(lista_mensajes, documento) do
    filtrados = Enum.filter(lista_mensajes, fn m -> m.destinatario == documento end)
    {:ok, filtrados}
  end

  @doc """
  Actualiza el estado de un mensaje a :entregado devolviendo una nueva lista (inmutabilidad).
  """
  def marcar_entregado(lista_mensajes, id_mensaje) do
    lista_actualizada = Enum.map(lista_mensajes, fn m ->
      if m.id == id_mensaje do
        %{m | estado: :entregado}
      else
        m
      end
    end)

    {:ok, lista_actualizada}
  end
end
