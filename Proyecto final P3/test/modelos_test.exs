defmodule Emergencia.ModelosTest do
  use ExUnit.Case, async: true

  alias Emergencia.Modelos.{
    Albergue,
    Coincidencias,
    Mascota,
    Mensaje,
    Necesidad,
    Persona,
    Recurso,
    Usuario,
    Zona
  }

  test "Usuario: registro, credenciales y control de permisos por rol" do
    {:ok, coord} = Usuario.nuevo("laura", "1234", "Laura Gómez", :coordinador, "centro")
    assert coord.conectado == true
    assert :ok == Usuario.validar_credenciales(coord, "1234")
    assert {:error, :credenciales_invalidas} == Usuario.validar_credenciales(coord, "0000")

    assert Usuario.puede_ejecutar?(coord, :asignar_recurso) == true

    {:ok, ciud} = Usuario.nuevo("pedro", "1111", "Pedro Ruiz", :ciudadano, "norte")
    assert Usuario.puede_ejecutar?(ciud, :registrar_necesidad) == true
    assert Usuario.puede_ejecutar?(ciud, :asignar_recurso) == false
  end

  test "Zona: jerarquía Zona -> Sectores -> Puntos de atención y Función Recursiva #1" do
    {:ok, z} = Zona.nueva("Z01", "Centro", :critico, 100)
    {:ok, z} = Zona.agregar_sector(z, "S01", "Sector Parque", :critico, 60)
    {:ok, z} = Zona.agregar_sector(z, "S02", "Sector Estación", :alto, 40)
    {:ok, z} = Zona.agregar_punto_atencion(z, "S01", "PA01", "Carpa Médica", "salud")
    {:ok, z} = Zona.agregar_punto_atencion(z, "S02", "PA02", "Punto Agua", "acopio")

    stats = Zona.calcular_estadisticas(z)
    assert stats.total_afectados == 200
    assert stats.total_sectores == 2
    assert stats.sectores_criticos == 1
    assert stats.total_puntos_atencion == 2

    assert {:ok, %{sector: "S01", punto: %{codigo: "PA01"}}} =
             Zona.buscar_punto_atencion(z, "PA01")
  end

  test "Necesidad: ordenamiento recursivo por prioridad (Función Recursiva #2) y bloqueo de cierre doble" do
    {:ok, n1} = Necesidad.nueva("N001", :agua, "Agua potable", 20, "centro", :baja, "laura")
    {:ok, n2} = Necesidad.nueva("N002", :rescate, "Rescate estructura", 5, "centro", :critica, "laura")
    {:ok, n3} = Necesidad.nueva("N003", :alimentos, "Raciones", 50, "norte", :alta, "laura")

    ordenadas = Necesidad.ordenar_por_prioridad([n1, n2, n3])
    assert Enum.map(ordenadas, & &1.id) == ["N002", "N003", "N001"]

    {:ok, n1_atendida} = Necesidad.asignar_recurso(n1, 20)
    assert n1_atendida.estado == :atendida
    assert {:error, :necesidad_cerrada} == Necesidad.asignar_recurso(n1_atendida, 5)
  end

  test "Recurso: inventario no negativo y disponibilidad recursiva (Función Recursiva #3)" do
    {:ok, r1} = Recurso.nuevo("R001", "agua", "hidratacion", 50, "litros", "acopio_1", "centro")
    {:ok, r2} = Recurso.nuevo("R002", "agua", "hidratacion", 30, "litros", "acopio_2", "centro")
    {:ok, r3} = Recurso.nuevo("R003", "agua", "hidratacion", 40, "litros", "acopio_3", "norte")

    assert Recurso.calcular_disponibilidad_recursiva([r1, r2, r3], "agua", "centro") == 80
    assert Recurso.calcular_disponibilidad_recursiva([r1, r2, r3], "agua") == 120
    assert {:error, :inventario_insuficiente} == Recurso.registrar_salida(r1, 60, :salida, "test")
  end

  test "Albergue: control estricto de capacidad máxima y cupos" do
    {:ok, alb} = Albergue.nuevo("A01", "Albergue Norte", "norte", 2)
    {:ok, alb} = Albergue.registrar_ingreso(alb, "1001")
    {:ok, alb} = Albergue.registrar_ingreso(alb, "1002")

    assert Albergue.cupos_disponibles(alb) == 0
    assert {:error, :albergue_sin_cupos} == Albergue.registrar_ingreso(alb, "1003")

    {:ok, alb} = Albergue.registrar_salida(alb, "1001")
    assert Albergue.cupos_disponibles(alb) == 1
  end

  test "Persona y Mensaje: historial de estados y entrega de mensajes" do
    {:ok, p} = Persona.nueva("P001", "Andrés Pérez", "1094001", 28, "norte", :reportada)
    {:ok, p} = Persona.actualizar_estado(p, :en_albergue, "Ingresado en A01")
    assert p.estado == :en_albergue
    assert length(p.historial_estados) == 2

    {:ok, msg} = Mensaje.nuevo("MSG001", "familiar1", "1094001", "Estamos bien en casa de la tía")
    assert msg.estado == :pendiente
    {:ok, msg_ent} = Mensaje.marcar_entregado(msg)
    assert msg_ent.estado == :entregado
  end

  test "Mascota y Coincidencias: emparejamiento recursivo (Función Recursiva #4) y resolución única" do
    {:ok, m1} =
      Mascota.nuevo("PET001", :perdida, "perro", "Luna", "collar rojo", "negra", "mediana", "norte", "3001112233")

    {:ok, m2} =
      Mascota.nuevo("PET002", :encontrada, "perro", "desconocido", "collar rojo", "negra", "mediana", "norte", "3119998877")

    matches = Coincidencias.buscar_coincidencias([m1, m2])
    assert length(matches) == 1
    assert hd(matches).puntaje >= 80

    {:ok, m1_res} = Mascota.resolver(m1, "PET002")
    assert {:error, :reporte_ya_resuelto} == Mascota.resolver(m1_res, "PET003")
  end
end
