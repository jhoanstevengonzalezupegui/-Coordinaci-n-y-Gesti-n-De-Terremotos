defmodule Emergencia.Modelos.Recurso do
  @moduledoc """
  Modelo de dominio para recursos e inventario en centros de acopio, albergues o puntos de atención.
  """

  defstruct [
    :codigo,
    :nombre,
    :categoria,
    :cantidad_disponible,
    :unidad,
    :ubicacion,
    zona: "general",
    historial_movimientos: []
  ]

  @doc """
  Crea un nuevo recurso en inventario validando cantidad >= 0.
  """
  def nuevo(codigo, nombre, categoria, cantidad, unidad, ubicacion, zona \\ "general") do
    cond do
      is_nil(codigo) or String.trim(to_string(codigo)) == "" ->
        {:error, :codigo_invalido}

      is_nil(nombre) or String.trim(to_string(nombre)) == "" ->
        {:error, :nombre_invalido}

      is_nil(categoria) or String.trim(to_string(categoria)) == "" ->
        {:error, :categoria_invalida}

      not is_integer(cantidad) or cantidad < 0 ->
        {:error, :cantidad_negativa_no_permitida}

      is_nil(unidad) or String.trim(to_string(unidad)) == "" ->
        {:error, :unidad_invalida}

      is_nil(ubicacion) or String.trim(to_string(ubicacion)) == "" ->
        {:error, :ubicacion_invalida}

      true ->
        movimiento_inicial = %{
          fecha: timestamp_actual(),
          tipo: :entrada_inicial,
          cantidad: cantidad,
          referencia: "Registro inicial en #{ubicacion}"
        }

        {:ok,
         %__MODULE__{
           codigo: String.trim(to_string(codigo)),
           nombre: String.downcase(String.trim(to_string(nombre))),
           categoria: String.downcase(String.trim(to_string(categoria))),
           cantidad_disponible: cantidad,
           unidad: String.trim(to_string(unidad)),
           ubicacion: String.trim(to_string(ubicacion)),
           zona: String.trim(to_string(zona)),
           historial_movimientos: [movimiento_inicial]
         }}
    end
  end

  @doc """
  Registra un ingreso de inventario (cantidad > 0).
  """
  def registrar_entrada(%__MODULE__{}, cantidad, _referencia)
      when not is_integer(cantidad) or cantidad <= 0 do
    {:error, :cantidad_entrada_invalida}
  end

  def registrar_entrada(%__MODULE__{} = recurso, cantidad, referencia) do
    movimiento = %{
      fecha: timestamp_actual(),
      tipo: :entrada,
      cantidad: cantidad,
      referencia: referencia
    }

    {:ok,
     %{
       recurso
       | cantidad_disponible: recurso.cantidad_disponible + cantidad,
         historial_movimientos: [movimiento | recurso.historial_movimientos]
     }}
  end

  @doc """
  Registra una salida o asignación de inventario impidiendo cantidades negativas.
  """
  def registrar_salida(%__MODULE__{}, cantidad, _tipo_salida, _referencia)
      when not is_integer(cantidad) or cantidad <= 0 do
    {:error, :cantidad_salida_invalida}
  end

  def registrar_salida(%__MODULE__{cantidad_disponible: disp}, cantidad, _tipo_salida, _referencia)
      when cantidad > disp do
    {:error, :inventario_insuficiente}
  end

  def registrar_salida(%__MODULE__{} = recurso, cantidad, tipo_salida, referencia) do
    movimiento = %{
      fecha: timestamp_actual(),
      tipo: tipo_salida,
      cantidad: cantidad,
      referencia: referencia
    }

    {:ok,
     %{
       recurso
       | cantidad_disponible: recurso.cantidad_disponible - cantidad,
         historial_movimientos: [movimiento | recurso.historial_movimientos]
     }}
  end

  @doc """
  FUNCIÓN RECURSIVA #3:
  Calcula recursivamente la cantidad total disponible de un recurso (por nombre o categoría)
  y opcionalmente filtrado por zona.
  """
  def calcular_disponibilidad_recursiva(recursos, criterio_tipo, zona \\ nil)

  def calcular_disponibilidad_recursiva([], _criterio_tipo, _zona), do: 0

  def calcular_disponibilidad_recursiva([%__MODULE__{} = rec | resto], criterio_tipo, zona) do
    criterio_norm = String.downcase(String.trim(to_string(criterio_tipo)))

    coincide_tipo =
      rec.nombre == criterio_norm or rec.categoria == criterio_norm

    coincide_zona =
      is_nil(zona) or String.downcase(rec.zona) == String.downcase(String.trim(to_string(zona)))

    aporte = if coincide_tipo and coincide_zona, do: rec.cantidad_disponible, else: 0
    aporte + calcular_disponibilidad_recursiva(resto, criterio_tipo, zona)
  end

  @doc """
  Serialización a texto plano para data/recursos.txt.
  """
  def a_linea(%__MODULE__{} = r) do
    movs_str =
      r.historial_movimientos
      |> Enum.map(fn m ->
        ref_limpia = String.replace(to_string(m.referencia), "|", "/")
        "#{m.fecha}~#{m.tipo}~#{m.cantidad}~#{ref_limpia}"
      end)
      |> Enum.join(";")

    [
      r.codigo,
      r.nombre,
      r.categoria,
      Integer.to_string(r.cantidad_disponible),
      r.unidad,
      r.ubicacion,
      r.zona,
      movs_str
    ]
    |> Enum.join("|")
  end

  def desde_linea(linea) do
    case String.split(String.trim(linea), "|") do
      [codigo, nombre, categoria, cant, unidad, ubicacion, zona, movs_str] ->
        movs =
          if movs_str == "" do
            []
          else
            movs_str
            |> String.split(";")
            |> Enum.map(fn item ->
              [fecha, tipo, c, ref] = String.split(item, "~", parts: 4)

              %{
                fecha: fecha,
                tipo: String.to_existing_atom(tipo),
                cantidad: String.to_integer(c),
                referencia: ref
              }
            end)
          end

        {:ok,
         %__MODULE__{
           codigo: codigo,
           nombre: nombre,
           categoria: categoria,
           cantidad_disponible: String.to_integer(cant),
           unidad: unidad,
           ubicacion: ubicacion,
           zona: zona,
           historial_movimientos: movs
         }}

      _ ->
        {:error, :formato_recurso_invalido}
    end
  end

  defp timestamp_actual do
    DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
  end
end
