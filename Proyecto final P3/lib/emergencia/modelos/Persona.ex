defmodule Emergencia.Modelos.Persona do
  @moduledoc """
  Modelo de dominio para personas afectadas y seguimiento de su estado durante la emergencia.
  """

  @estados_validos [
    :sin_informacion,
    :reportada,
    :localizada,
    :trasladada,
    :en_albergue,
    :reunificada
  ]

  defstruct [
    :id,
    :nombre,
    :documento,
    :edad,
    :zona,
    estado: :reportada,
    historial_estados: []
  ]

  @doc """
  Registra una persona afectada validando campos obligatorios y edad >= 0.
  """
  def nueva(id, nombre, documento, edad, zona, estado \\ :reportada) do
    estado_atom = normalizar_estado(estado)

    cond do
      is_nil(id) or String.trim(to_string(id)) == "" ->
        {:error, :id_invalido}

      is_nil(nombre) or String.trim(to_string(nombre)) == "" ->
        {:error, :nombre_invalido}

      is_nil(documento) or String.trim(to_string(documento)) == "" ->
        {:error, :documento_invalido}

      not is_integer(edad) or edad < 0 ->
        {:error, :edad_invalida}

      is_nil(zona) or String.trim(to_string(zona)) == "" ->
        {:error, :zona_invalida}

      estado_atom not in @estados_validos ->
        {:error, :estado_persona_invalido}

      true ->
        registro_inicial = {timestamp_actual(), estado_atom, "Registro inicial en zona #{zona}"}

        {:ok,
         %__MODULE__{
           id: String.trim(to_string(id)),
           nombre: String.trim(to_string(nombre)),
           documento: String.trim(to_string(documento)),
           edad: edad,
           zona: String.trim(to_string(zona)),
           estado: estado_atom,
           historial_estados: [registro_inicial]
         }}
    end
  end

  @doc """
  Actualiza el estado de la persona y conserva el historial de cambios.
  """
  def actualizar_estado(%__MODULE__{} = persona, nuevo_estado, detalle \\ "") do
    estado_atom = normalizar_estado(nuevo_estado)

    cond do
      estado_atom not in @estados_validos ->
        {:error, :estado_persona_invalido}

      persona.estado == estado_atom ->
        {:error, :estado_sin_cambios}

      true ->
        entrada = {timestamp_actual(), estado_atom, detalle}

        {:ok,
         %{
           persona
           | estado: estado_atom,
             historial_estados: [entrada | persona.historial_estados]
         }}
    end
  end

  @doc """
  Evalúa si una persona coincide con los filtros de búsqueda (nombre, documento, zona, estado).
  """
  def coincide_filtros?(%__MODULE__{} = p, filtros) do
    coincide_texto?(p.nombre, Map.get(filtros, :nombre)) and
      coincide_exacto?(p.documento, Map.get(filtros, :documento)) and
      coincide_texto?(p.zona, Map.get(filtros, :zona)) and
      coincide_exacto?(p.estado, Map.get(filtros, :estado))
  end

  defp coincide_texto?(_valor, nil), do: true

  defp coincide_texto?(valor, filtro) do
    String.contains?(String.downcase(to_string(valor)), String.downcase(String.trim(to_string(filtro))))
  end

  defp coincide_exacto?(_valor, nil), do: true
  defp coincide_exacto?(valor, filtro), do: String.downcase(to_string(valor)) == String.downcase(String.trim(to_string(filtro)))

  def a_linea(%__MODULE__{} = p) do
    hist_str =
      p.historial_estados
      |> Enum.map(fn {ts, est, det} ->
        det_limpio = String.replace(to_string(det), "|", "/")
        "#{ts}~#{est}~#{det_limpio}"
      end)
      |> Enum.join(";")

    [
      p.id,
      String.replace(p.nombre, "|", "/"),
      p.documento,
      Integer.to_string(p.edad),
      p.zona,
      Atom.to_string(p.estado),
      hist_str
    ]
    |> Enum.join("|")
  end

  def desde_linea(linea) do
    case String.split(String.trim(linea), "|") do
      [id, nombre, doc, edad, zona, estado, hist_str] ->
        historial =
          if hist_str == "" do
            []
          else
            hist_str
            |> String.split(";")
            |> Enum.map(fn item ->
              case String.split(item, "~", parts: 3) do
                [ts, est, det] -> {ts, String.to_existing_atom(est), det}
                [ts, est] -> {ts, String.to_existing_atom(est), ""}
              end
            end)
          end

        {:ok,
         %__MODULE__{
           id: id,
           nombre: nombre,
           documento: doc,
           edad: String.to_integer(edad),
           zona: zona,
           estado: String.to_existing_atom(estado),
           historial_estados: historial
         }}

      _ ->
        {:error, :formato_persona_invalido}
    end
  end

  def normalizar_estado(e) when is_atom(e) and e in @estados_validos, do: e

  def normalizar_estado(e) when is_binary(e) do
    case String.downcase(String.trim(e)) do
      "sin_informacion" -> :sin_informacion
      "reportada" -> :reportada
      "localizada" -> :localizada
      "trasladada" -> :trasladada
      "en_albergue" -> :en_albergue
      "reunificada" -> :reunificada
      _ -> :invalido
    end
  end

  def normalizar_estado(_), do: :invalido

  defp timestamp_actual do
    DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
  end
end
