defmodule Emergencia.Modelos.Albergue do
  @moduledoc """
  Modelo de dominio para albergues temporales y control de cupos.
  """

  defstruct [
    :codigo,
    :nombre,
    :zona,
    :capacidad_maxima,
    ocupacion_actual: 0,
    personas_alojadas: MapSet.new(),
    recursos_asociados: MapSet.new(),
    necesidades_asociadas: MapSet.new()
  ]

  @doc """
  Crea un nuevo albergue validando capacidad máxima > 0.
  """
  def nuevo(codigo, nombre, zona, capacidad_maxima) do
    cond do
      is_nil(codigo) or String.trim(to_string(codigo)) == "" ->
        {:error, :codigo_invalido}

      is_nil(nombre) or String.trim(to_string(nombre)) == "" ->
        {:error, :nombre_invalido}

      is_nil(zona) or String.trim(to_string(zona)) == "" ->
        {:error, :zona_invalida}

      not is_integer(capacidad_maxima) or capacidad_maxima <= 0 ->
        {:error, :capacidad_invalida}

      true ->
        {:ok,
         %__MODULE__{
           codigo: String.trim(to_string(codigo)),
           nombre: String.trim(to_string(nombre)),
           zona: String.trim(to_string(zona)),
           capacidad_maxima: capacidad_maxima,
           ocupacion_actual: 0
         }}
    end
  end

  @doc """
  Registra el ingreso de una persona por documento/ID, impidiendo exceder capacidad máxima.
  """
  def registrar_ingreso(%__MODULE__{ocupacion_actual: ocup, capacidad_maxima: cap}, _doc)
      when ocup >= cap do
    {:error, :albergue_sin_cupos}
  end

  def registrar_ingreso(%__MODULE__{} = alb, documento) do
    doc = String.trim(to_string(documento))

    cond do
      doc == "" ->
        {:error, :documento_invalido}

      MapSet.member?(alb.personas_alojadas, doc) ->
        {:error, :persona_ya_ingresada}

      true ->
        {:ok,
         %{
           alb
           | ocupacion_actual: alb.ocupacion_actual + 1,
             personas_alojadas: MapSet.put(alb.personas_alojadas, doc)
         }}
    end
  end

  @doc """
  Registra la salida de una persona previamente ingresada en el albergue.
  """
  def registrar_salida(%__MODULE__{ocupacion_actual: 0}, _documento) do
    {:error, :albergue_vacio}
  end

  def registrar_salida(%__MODULE__{} = alb, documento) do
    doc = String.trim(to_string(documento))

    if MapSet.member?(alb.personas_alojadas, doc) do
      {:ok,
       %{
         alb
         | ocupacion_actual: alb.ocupacion_actual - 1,
           personas_alojadas: MapSet.delete(alb.personas_alojadas, doc)
       }}
    else
      {:error, :persona_no_registrada_en_albergue}
    end
  end

  def cupos_disponibles(%__MODULE__{capacidad_maxima: cap, ocupacion_actual: ocup}) do
    cap - ocup
  end

  def porcentaje_ocupacion(%__MODULE__{capacidad_maxima: cap, ocupacion_actual: ocup}) do
    Float.round(ocup / cap * 100, 2)
  end

  def asociar_recurso(%__MODULE__{} = alb, cod_recurso) do
    {:ok, %{alb | recursos_asociados: MapSet.put(alb.recursos_asociados, cod_recurso)}}
  end

  def asociar_necesidad(%__MODULE__{} = alb, id_necesidad) do
    {:ok, %{alb | necesidades_asociadas: MapSet.put(alb.necesidades_asociadas, id_necesidad)}}
  end

  @doc """
  Genera un reporte ordenado de mayor a menor nivel de ocupación.
  """
  def reporte_mayor_ocupacion(lista_albergues) do
    lista_albergues
    |> Enum.map(fn alb ->
      %{
        codigo: alb.codigo,
        nombre: alb.nombre,
        zona: alb.zona,
        ocupacion_actual: alb.ocupacion_actual,
        capacidad_maxima: alb.capacidad_maxima,
        cupos_disponibles: cupos_disponibles(alb),
        porcentaje_ocupacion: porcentaje_ocupacion(alb)
      }
    end)
    |> Enum.sort_by(& &1.porcentaje_ocupacion, :desc)
  end

  @doc """
  Serialización a texto plano para data/albergues.txt.
  """
  def a_linea(%__MODULE__{} = a) do
    [
      a.codigo,
      a.nombre,
      a.zona,
      Integer.to_string(a.capacidad_maxima),
      Integer.to_string(a.ocupacion_actual),
      Enum.join(MapSet.to_list(a.personas_alojadas), ","),
      Enum.join(MapSet.to_list(a.recursos_asociados), ","),
      Enum.join(MapSet.to_list(a.necesidades_asociadas), ",")
    ]
    |> Enum.join("|")
  end

  def desde_linea(linea) do
    case String.split(String.trim(linea), "|") do
      [codigo, nombre, zona, cap, ocup, personas, recursos, necesidades] ->
        {:ok,
         %__MODULE__{
           codigo: codigo,
           nombre: nombre,
           zona: zona,
           capacidad_maxima: String.to_integer(cap),
           ocupacion_actual: String.to_integer(ocup),
           personas_alojadas: parsear_set(personas),
           recursos_asociados: parsear_set(recursos),
           necesidades_asociadas: parsear_set(necesidades)
         }}

      _ ->
        {:error, :formato_albergue_invalido}
    end
  end

  defp parsear_set(""), do: MapSet.new()
  defp parsear_set(str), do: str |> String.split(",") |> MapSet.new()
end
