defmodule Emergencias.Logistica.NeedServer do
  @moduledoc """
  GenServer de necesidades. Serializa los cambios de estado (una necesidad no se
  atiende dos veces) y pide recursos al ResourceServer, que garantiza el inventario.
  Nunca es llamado por ResourceServer, así que no hay interbloqueo.
  """
  use GenServer
  alias Emergencias.Logistica.{Necesidad, Persistencia, ResourceServer}

  @archivo "necesidades.txt"

  def start_link(opts \\ []),
    do: GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))

  def registrar(tipo, cant, prio, zona, desc, responsable \\ "anonimo", s \\ __MODULE__),
    do: GenServer.call(s, {:registrar, tipo, cant, prio, zona, desc, responsable})

  def listar(filtros \\ [], s \\ __MODULE__), do: GenServer.call(s, {:listar, filtros})
  def pendientes(s \\ __MODULE__), do: listar([estado: "pendiente"], s)

  @doc "La necesidad pendiente más urgente."
  def siguiente(s \\ __MODULE__), do: s |> pendientes() |> List.first()

  def asignar_recurso(id, categoria, cant, s \\ __MODULE__),
    do: GenServer.call(s, {:asignar, id, categoria, cant})

  def cambiar_estado(id, estado, s \\ __MODULE__), do: GenServer.call(s, {:estado, id, estado})

  @impl true
  def init(opts) do
    dir = Keyword.get(opts, :dir, Application.get_env(:emergencias, :data_dir, "data"))
    needs = for l <- Persistencia.leer(dir, @archivo), {:ok, n} <- [Necesidad.de_linea(l)], into: %{}, do: {n.id, n}
    {:ok, %{dir: dir, needs: needs, recursos: Keyword.get(opts, :recursos, ResourceServer)}}
  end

  @impl true
  def handle_call({:registrar, tipo, cant, prio, zona, desc, resp}, _from, st) do
    id = "N" <> String.pad_leading(Integer.to_string(map_size(st.needs) + 1), 3, "0")

    case Necesidad.nuevo(id, tipo, cant, prio, zona, desc, resp) do
      {:ok, n} -> {:reply, {:ok, n}, guardar(st, Map.put(st.needs, id, n))}
      {:error, _} = e -> {:reply, e, st}
    end
  end

  def handle_call({:listar, filtros}, _from, st),
    do: {:reply, st.needs |> Map.values() |> Necesidad.filtrar(filtros) |> Necesidad.ordenar(), st}

  def handle_call({:asignar, id, categoria, cant}, _from, st) do
    with {:ok, n} <- fetch(st, id),
         :ok <- Necesidad.puede_asignar(n, cant),
         :ok <- if(n.tipo in ["otra", Necesidad.norm(categoria)], do: :ok, else: {:error, :categoria_no_coincide}),
         {:ok, tomados} <- ResourceServer.asignar(categoria, cant, id, st.recursos) do
      n2 = Necesidad.aplicar_asignacion(n, cant)
      {:reply, {:ok, n2, tomados}, guardar(st, Map.put(st.needs, id, n2))}
    else
      e -> {:reply, e, st}
    end
  end

  def handle_call({:estado, id, estado}, _from, st) do
    with {:ok, n} <- fetch(st, id),
         {:ok, e} <- Necesidad.parse_estado(estado),
         {:ok, n2} <- Necesidad.transicion(n, e) do
      {:reply, {:ok, n2}, guardar(st, Map.put(st.needs, id, n2))}
    else
      e -> {:reply, e, st}
    end
  end

  defp fetch(st, id) do
    case Map.fetch(st.needs, id) do
      {:ok, n} -> {:ok, n}
      :error -> {:error, :necesidad_no_existe}
    end
  end

  defp guardar(st, needs) do
    lineas = needs |> Map.values() |> Enum.sort_by(& &1.id) |> Enum.map(&Necesidad.a_linea/1)
    Persistencia.guardar(st.dir, @archivo, lineas)
    %{st | needs: needs}
  end
end
