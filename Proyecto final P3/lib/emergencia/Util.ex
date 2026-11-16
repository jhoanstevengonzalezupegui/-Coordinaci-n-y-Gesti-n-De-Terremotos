defmodule Emergencia.Util do
  @moduledoc """
  Funciones utilitarias puras para normalización, validación y generación de IDs.
  """

  @doc """
  Genera un identificador único secuencial con prefijo (ej: "N001", "M002", "MSG003").
  """
  def generar_id(prefijo, coleccion_ids) do
    numero =
      coleccion_ids
      |> Enum.map(fn id ->
        id
        |> to_string()
        |> String.replace_prefix(prefijo, "")
        |> Integer.parse()
        |> case do
          {n, ""} -> n
          _ -> 0
        end
      end)
      |> Enum.max(fn -> 0 end)
      |> Kernel.+(1)

    sufijo = numero |> Integer.to_string() |> String.pad_leading(3, "0")
    "#{prefijo}#{sufijo}"
  end

  @doc """
  Convierte texto a entero de forma segura retornando {:ok, int} o {:error, :entero_invalido}.
  """
  def parsear_entero(valor) when is_integer(valor), do: {:ok, valor}

  def parsear_entero(valor) when is_binary(valor) do
    case Integer.parse(String.trim(valor)) do
      {num, ""} -> {:ok, num}
      _ -> {:error, :entero_invalido}
    end
  end

  def parsear_entero(_), do: {:error, :entero_invalido}

  def timestamp_actual do
    DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
  end
end
