defmodule Util do
  # ---- Salida por consola ----
  def mostrar_mensaje(mensaje), do: IO.puts(mensaje)
  def mostrar_error(mensaje), do: IO.puts("ERROR: " <> mensaje)

  # ---- Validaciones de texto ----
  # Un texto no puede traer "|" ni saltos de línea porque rompen el archivo plano.
  def sin_separador?(texto) when is_binary(texto), do: not String.contains?(texto, ["|", "\n"])
  def sin_separador?(_), do: false

  def texto_valido?(texto) when is_binary(texto),
    do: String.trim(texto) != "" and sin_separador?(texto)

  def texto_valido?(_), do: false

  # Para comparar textos sin importar mayúsculas ni espacios sobrantes.
  def normalizar(texto) when is_binary(texto), do: texto |> String.trim() |> String.downcase()

  # Fecha y hora actual en formato ISO, por ejemplo "2026-11-14T09:15:00".
  def ahora do
    NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second) |> NaiveDateTime.to_iso8601()
  end

  # Convierte un texto en el átomo válido que coincide (o nil). Evita String.to_atom.
  def a_atomo(texto, validos), do: Enum.find(validos, fn a -> Atom.to_string(a) == texto end)
end
