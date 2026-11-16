#  Coordinación y Gestión De Terremotos
atención y coordinación posterior a un terremoto



Sistema Distribuido de Gestión de Emergencias y Ayuda HumanitariaSistema concurrente y tolerante a fallos desarrollado en Elixir / OTP para la coordinación integral de emergencias (terremotos y desastres naturales). Permite administrar zonas afectadas, inventarios críticos, asignación priorizada de recursos, albergues temporales, localización de familiares, mensajería humanitaria y reencuentro de mascotas mediante una interfaz de línea de comandos (CLI) interactiva con persistencia en archivos.Arquitectura del Sistema (OTP)El proyecto está construido bajo el modelo de actores de Erlang/Elixir, empleando un Árbol de Supervisión (Emergencia.Supervisor) con estrategia :one_for_one que garantiza el aislamiento de fallos y la disponibilidad continua de cada módulo de negocio:                       [ Emergencia.Application ]
                                   |
                                   v
                       [ Emergencia.Supervisor ]
                         (Estrategia :one_for_one)
                                   |
       +---------------+-----------+-----------+---------------+---------------+
       |               |                       |               |               |
       v               v                       v               v               v
[UsuariosServer] [ZonasServer]        [InventarioServer] [AlberguesServer] [FamiliaresServer]
                                                                               |
                                                                               v
                                                                        [MascotasServer]
Componentes PrincipalesEmergencia.Servidores.UsuariosServer: Gestión de sesiones y control de acceso basado en roles (coordinador, voluntario, ciudadano, organizacion).Emergencia.Servidores.ZonasServer: Registro jerárquico de zonas afectadas, sectores y puntos de atención, con cálculo recursivo de estadísticas de afectación.Emergencia.Servidores.InventarioServer: Control centralizado de lotes de recursos y necesidades humanitarias. Serializa las operaciones mediante el mailbox del GenServer para evitar condiciones de carrera y saldos negativos.Emergencia.Servidores.AlberguesServer: Administración de capacidad máxima y control de ingresos/salidas de personas mediante estructuras MapSet.Emergencia.Servidores.FamiliaresServer: Registro de personas reportadas, trazabilidad del historial de estados y buzón de mensajes familiares.Emergencia.Servidores.MascotasServer: Gestión de reportes de mascotas perdidas y encontradas, confirmación de reencuentros y cierre de casos.Emergencia.OperacionesExtendidas: Módulo de lógica funcional pura y recursiva para transferencias entre centros de acopio, ordenamiento por prioridad, búsqueda multicriterio, cálculo de similitud de mascotas y generación del resumen global.Emergencia.CLI: Consola interactiva con soporte para argumentos entrecomillados, validación de permisos y simulación de concurrencia en vivo.Aspectos Clave de ImplementaciónConcurrencia Segura sin Condiciones de Carrera:
Las solicitudes simultáneas de asignación de recursos (por ejemplo, múltiples procesos Task.async compitiendo por el mismo lote de agua) son encoladas y procesadas secuencialmente por InventarioServer, garantizando integridad transaccional e impidiendo inventarios negativos.Recursividad y Programación Funcional:Cálculo recursivo de damnificados, sectores críticos y puntos de atención por zona (ZonasServer).Filtrado recursivo de lotes de inventario y ordenamiento recursivo (Quicksort) de necesidades según nivel de urgencia (critica > alta > media > baja).Búsqueda recursiva multicriterio de personas por documento, nombre, zona o estado.Motor recursivo de emparejamiento de mascotas perdidas y encontradas con puntaje porcentual de similitud (especie, color, tamaño, zona y características).Persistencia en Archivos:
El estado de los servidores se almacena y recupera automáticamente desde archivos planos en el directorio data/, conservando la información entre reinicios del sistema.Estructura del ProyectoProyecto final P3/
├── data/                        # Archivos de persistencia (.txt)
├── lib/
│   ├── emergencia/
│   │   ├── modelos/             # Estructuras de datos y operaciones extendidas
│   │   ├── servidores/          # GenServers de cada dominio
│   │   ├── application.ex       # Punto de entrada y árbol de supervisión OTP
│   │   └── cli.ex               # Interfaz de línea de comandos interactiva
│   └── emergencia.ex
├── test/
│   └── emergencia_test.exs      # Suite de pruebas unitarias y de concurrencia (ExUnit)
├── mix.exs                      # Configuración del proyecto Mix
└── README.md
Requisitos e InstalaciónElixir >= 1.14Erlang/OTP >= 25Nota para usuarios de Windows: Asegúrese de ubicar y abrir el proyecto en una ruta sin tildes ni espacios iniciales en el nombre de las carpetas (por ejemplo: C:\Proyectos\Proyecto_Final_P3) para evitar conflictos de codificación en la consola de Erlang.Ubíquese en la carpeta raíz del proyecto (donde se encuentra mix.exs):cd "Proyecto final P3"
Compile el proyecto y ejecute la suite de pruebas automatizadas:mix test
Salida esperada: 12 tests, 0 failures.Ejecución de la CLIInicie la consola interactiva ejecutando:mix run -e "Emergencia.CLI.iniciar()"
Comandos DisponiblesSesión y UsuariosComandoDescripciónconnect <user> <pass> <rol> <zona> [nombre]Inicia sesión (coordinador, voluntario, ciudadano, organizacion).whoamiMuestra los datos de la sesión activa.disconnectCierra la sesión actual.ayuda / salirMuestra la lista de comandos o finaliza el programa.Zonas AfectadasComandoDescripciónzona_registrar <cod> <nombre> <riesgo> <afec>Registra una zona (bajo, medio, alto, critico).sector_agregar <z_cod> <s_cod> <nom> <r> <af>Agrega un sector a una zona existente.punto_agregar <z_cod> <s_cod> <p_cod> <n> <t>Agrega un punto de atención a un sector.zona_stats <zona_cod>Calcula estadísticas recursivas de la zona.Inventario, Transferencias y NecesidadesComandoDescripciónrecurso_registrar <id> <nom> <cat> <cant> <u_med> <ubic> <zona>Registra un nuevo lote de recursos en inventario.recurso_transferir <rec_id> <ubic_dest> <zona_dest> <cant>Transfiere unidades entre centros de apoyo creando un nuevo lote.recursos [zona]Lista todos los lotes de inventario (opcionalmente filtrados por zona).inventario <nombre_recurso> [zona]Consulta el stock disponible total de un recurso.necesidad_registrar <tipo> <cant> <prio> <zona> <desc>Registra una necesidad (agua, alimentos, medicamentos, otra, etc.).necesidades [zona] [prioridad]Lista necesidades ordenadas de mayor a menor prioridad.recurso_asignar <necesidad_id> <recurso_id> <cant>Asigna unidades de un lote para cubrir una necesidad.simular_concurrenciaEjecuta una prueba en vivo de solicitudes concurrentes sobre un mismo lote.Albergues, Familiares y MascotasComandoDescripciónalbergue_registrar <id> <nombre> <zona> <capacidad>Crea un nuevo albergue con cupo máximo.albergue_ingreso <albergue_id> <documento>Registra el ingreso de una persona al albergue.albergue_salida <albergue_id> <documento>Registra la salida de una persona y libera su cupo.albergue_consultar <id> / albergues_reporteConsulta detalle de cupos y ranking de ocupación.persona_reportar <doc> <nombre> <zona> <estado> <edad>Registra o actualiza el estado de una persona.persona_buscar <criterio>Busca personas por documento, nombre, zona o estado.mensaje_enviar <doc_destino> <contenido>Envía un mensaje al buzón de una persona reportada.mensajes <doc>Lista los mensajes recibidos para un documento.mascota_reportar <perdida|encontrada> <esp> <nom> <caract> <color> <tam> <zona> <contacto> [id]Registra un reporte de mascota perdida o encontrada.mascota_coincidenciasEjecuta el motor recursivo de similitud entre mascotas.mascota_confirmar <id_perdida> <id_encontrada>Confirma el reencuentro y cierra ambos reportes.resumen (o summary)Muestra el tablero consolidado global del sistema.Ejemplo Rápido de Demostraciónconnect laura 1234 coordinador centro "Laura Gomez"
zona_stats Z01
recursos
recurso_transferir R02 albergue_norte norte 20
necesidad_registrar agua 40 critica centro "Agua potable urgente"
necesidades
simular_concurrencia
albergue_consultar A01
albergues_reporte
persona_buscar 1094555
mascota_coincidencias
resumen
salir
