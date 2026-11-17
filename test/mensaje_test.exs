defmodule mensajeTest do
  use ExUnit.Case

  alias Emergencia.Mensaje

  @fecha "2026-11-14T17:20:00"

  defp crear(id, destinatario) do
    {:ok, m} = Mensaje.nuevo(id, "carlos", destinatario, "Estoy bien, voy en camino", @fecha)
    m
  end

  describe "nuevo/5" do
    test "crea un mensaje válido en estado pendiente" do
      m = crear("MS001", "1094567890")
      assert m.estado == :pendiente
      assert m.fecha == @fecha
    end

    test "rechaza un contenido con el separador |" do
      assert {:error, :datos_invalidos} = Mensaje.nuevo("MS001", "carlos", "1094567890", "hola|mundo", @fecha)
    end

    test "rechaza un contenido vacío" do
      assert {:error, :datos_invalidos} = Mensaje.nuevo("MS001", "carlos", "1094567890", "", @fecha)
    end
  end

  describe "marcar_entregado/1 y marcar_pendiente/1" do
    test "marca un mensaje como entregado" do
      assert {:ok, m} = Mensaje.marcar_entregado(crear("MS001", "111"))
      assert m.estado == :entregado
    end

    test "no se puede entregar dos veces" do
      {:ok, m} = Mensaje.marcar_entregado(crear("MS001", "111"))
      assert {:error, :ya_entregado} = Mensaje.marcar_entregado(m)
    end

    test "un mensaje entregado puede volver a pendiente" do
      {:ok, m} = Mensaje.marcar_entregado(crear("MS001", "111"))
      assert {:ok, vuelto} = Mensaje.marcar_pendiente(m)
      assert vuelto.estado == :pendiente
    end

    test "un mensaje pendiente no se puede marcar pendiente otra vez" do
      assert {:error, :ya_pendiente} = Mensaje.marcar_pendiente(crear("MS001", "111"))
    end
  end

  describe "filtrar/3 (recursiva)" do
    setup do
      m1 = crear("MS001", "111")
      m2 = crear("MS002", "222")
      {:ok, m3} = Mensaje.marcar_entregado(crear("MS003", "111"))
      m4 = crear("MS004", "111")
      %{lista: [m1, m2, m3, m4], m1: m1, m3: m3, m4: m4}
    end

    test "trae todos los mensajes de un destinatario, en el mismo orden", %{lista: lista, m1: m1, m3: m3, m4: m4} do
      assert [^m1, ^m3, ^m4] = Mensaje.filtrar(lista, "111")
    end

    test "filtra por estado", %{lista: lista, m1: m1, m4: m4} do
      assert [^m1, ^m4] = Mensaje.filtrar(lista, "111", :pendiente)
    end

    test "un destinatario sin mensajes devuelve lista vacía", %{lista: lista} do
      assert [] = Mensaje.filtrar(lista, "999")
    end

    test "caso base: lista vacía" do
      assert [] = Mensaje.filtrar([], "111")
    end
  end

  describe "a_linea/1 y de_linea/1" do
    test "ida y vuelta devuelve el mismo mensaje" do
      m = crear("MS001", "1094567890")
      assert {:ok, ^m} = Mensaje.de_linea(Mensaje.a_linea(m))
    end

    test "lee una línea igual a las de data/mensajes.txt" do
      linea = "MS001|2026-11-14T17:20:00|carlos|1094567890|Andres, te buscamos en el albergue norte, ya vamos|pendiente"
      assert {:ok, m} = Mensaje.de_linea(linea)
      assert m.remitente == "carlos"
      assert m.estado == :pendiente
    end

    test "una línea dañada devuelve error" do
      assert {:error, :linea_invalida} = Mensaje.de_linea("MS001|solo|tres")
    end
  end
end
