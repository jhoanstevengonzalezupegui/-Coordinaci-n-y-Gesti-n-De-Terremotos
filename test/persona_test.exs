defmodule personaTest do

  alias Emergencia.Persona

  @fecha "2026-11-14T09:15:00"
  @fecha2 "2026-11-14T16:40:00"

  defp crear(id, nombre, documento, zona, estado) do
    {:ok, p} = Persona.nuevo(id, nombre, documento, 28, zona, estado, @fecha)
    p
  end

  defp andres(estado \\ :reportada), do: crear("P001", "Andres Gomez", "1094567890", "zona_norte", estado)

  describe "nuevo/7" do
    test "crea una persona válida con el estado inicial en el historial" do
      p = andres()
      assert p.estado == :reportada
      assert p.historial == [{:reportada, @fecha}]
    end

    test "rechaza un estado inexistente" do
      assert {:error, :estado_invalido} =
               Persona.nuevo("P001", "Andres", "1094567890", 28, "zona_norte", :volando, @fecha)
    end

    test "rechaza datos de texto vacíos" do
      assert {:error, :datos_invalidos} =
               Persona.nuevo("P001", "", "1094567890", 28, "zona_norte", :reportada, @fecha)
    end

    test "rechaza una edad negativa o que no sea número" do
      assert {:error, :edad_invalida} =
               Persona.nuevo("P001", "Andres", "1094567890", -5, "zona_norte", :reportada, @fecha)

      assert {:error, :edad_invalida} =
               Persona.nuevo("P001", "Andres", "1094567890", "28", "zona_norte", :reportada, @fecha)
    end
  end

  describe "cambiar_estado/3" do
    test "permite una transición válida y la agrega al historial" do
      assert {:ok, p} = Persona.cambiar_estado(andres(), :localizada, @fecha2)
      assert p.estado == :localizada
      assert p.historial == [{:reportada, @fecha}, {:localizada, @fecha2}]
    end

    test "rechaza una transición inválida" do
      assert {:error, :transicion_invalida} = Persona.cambiar_estado(andres(:en_albergue), :reportada, @fecha2)
    end

    test "una persona reunificada ya no cambia de estado" do
      assert {:error, :transicion_invalida} = Persona.cambiar_estado(andres(:reunificada), :localizada, @fecha2)
    end

    test "rechaza un estado inexistente" do
      assert {:error, :estado_invalido} = Persona.cambiar_estado(andres(), :volando, @fecha2)
    end
  end

  describe "buscar/3" do
    setup do
      p1 = andres()
      p2 = crear("P002", "Marta Ruiz", "1098123456", "zona_centro", :localizada)
      p3 = crear("P003", "Luis Perez", "1090456789", "zona_norte", :reportada)
      %{todos: [p1, p2, p3], p1: p1, p2: p2, p3: p3}
    end

    test "por nombre, sin importar mayúsculas", %{todos: todos, p1: p1} do
      assert [^p1] = Persona.buscar(todos, :nombre, "GOMEZ")
    end

    test "por documento", %{todos: todos, p2: p2} do
      assert [^p2] = Persona.buscar(todos, :documento, "1098123456")
    end

    test "por zona", %{todos: todos, p1: p1, p3: p3} do
      assert [^p1, ^p3] = Persona.buscar(todos, :zona, "zona_norte")
    end

    test "por estado", %{todos: todos, p2: p2} do
      assert [^p2] = Persona.buscar(todos, :estado, :localizada)
    end

    test "sin resultados devuelve lista vacía", %{todos: todos} do
      assert [] = Persona.buscar(todos, :nombre, "nadie")
    end
  end

  describe "a_linea/1 y de_linea/1" do
    test "ida y vuelta conserva todo, incluido el historial" do
      {:ok, p} = Persona.cambiar_estado(andres(), :localizada, @fecha2)
      assert {:ok, ^p} = Persona.de_linea(Persona.a_linea(p))
    end

    test "lee una línea igual a las de data/personas.txt" do
      linea =
        "P001|Andres Gomez|1094567890|28|zona_norte|en_albergue|reportada@2026-11-14T09:15:00;localizada@2026-11-14T16:40:00;en_albergue@2026-11-14T18:05:00"

      assert {:ok, p} = Persona.de_linea(linea)
      assert p.estado == :en_albergue
      assert length(p.historial) == 3
    end

    test "una línea con pocos campos devuelve error" do
      assert {:error, :linea_invalida} = Persona.de_linea("x|y")
    end

    test "una edad que no es número devuelve error" do
      assert {:error, :linea_invalida} =
               Persona.de_linea("P001|Andres|1094567890|abc|zona_norte|reportada|reportada@2026-11-14T09:15:00")
    end

    test "un historial dañado devuelve error" do
      assert {:error, :linea_invalida} =
               Persona.de_linea("P001|Andres|1094567890|28|zona_norte|reportada|reportada")
    end
  end
end
