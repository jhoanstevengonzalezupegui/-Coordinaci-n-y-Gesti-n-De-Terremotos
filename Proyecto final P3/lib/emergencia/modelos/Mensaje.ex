defmodule Emergencia.Modelos.Mensaje do
  @moduledoc """
  Modelo de dominio para mensajes de comunicación entre familiares.
  """

  defstruct [
    :id,
    :fecha,
    :remitente,
    :destinatario,
    :contenido,
    estado: :pendiente
  ]

  def nuevo(id, remitente, destinatario, contenido) do
    cond do
      is_nil(id) or String.trim(to_string(id)) == "" ->
        {:error, :id_invalido}

      is_nil(remitente) or String.trim(to_string(remitente)) == "" ->
        {:error, :remitente_invalido}

      is_nil(destinatario) or String.trim(to_string(destinatario)) == "" ->
        {:error, :destinatario_invalido}

      is_nil(contenido) or String.trim(to_string(contenido)) == "" ->
        {:error, :contenido_vacio}

      true ->
        {:ok,
         %__MODULE__{
           id: String.trim(to_string(id)),
           fecha: timestamp_actual(),
           remitente: String.trim(to_string(remitente)),
           destinatario: String.trim(to_string(destinatario)),
           contenido: String.trim(to_string(contenido)),
           estado: :pendiente
         }}
    end
  end

  def marcar_entregado(%__MODULE__{estado: :entregado}), do: {:error, :mensaje_ya_entregado}
  def marcar_entregado(%__MODULE__{} = msg), do: {:ok, %{msg | estado: :entregado}}

  def a_linea(%__MODULE__{} = m) do
    [
      m.id,
      m.fecha,
      m.remitente,
      m.destinatario,
      String.replace(m.contenido, "|", "/"),
      Atom.to_string(m.estado)
    ]
    |> Enum.join("|")
  end

  def desde_linea(linea) do
    case String.split(String.trim(linea), "|") do
      [id, fecha, rem, dest, cont, est] ->
        {:ok,
         %__MODULE__{
           id: id,
           fecha: fecha,
           remitente: rem,
           destinatario: dest,
           contenido: cont,
           estado: String.to_existing_atom(est)
         }}

      _ ->
        {:error, :formato_mensaje_invalido}
    end
  end

  defp timestamp_actual do
    DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
  end
end
