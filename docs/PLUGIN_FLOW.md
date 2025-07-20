# 🔄 Flujo Detallado del Plugin L4D2 Fix Spawn Order

## 📋 Índice
- [🚀 Inicialización del Plugin](#-inicialización-del-plugin)
- [🎮 Flujo de Ronda](#-flujo-de-ronda)
- [👤 Manejo de Jugadores](#-manejo-de-jugadores)
- [🔄 Sistema de Cola](#-sistema-de-cola)
- [⚖️ Validación de Límites](#️-validación-de-límites)
- [🤖 Integración de Bots](#-integración-de-bots)
- [📊 Sistema de Eventos](#-sistema-de-eventos)

---

## 🚀 Inicialización del Plugin

### **Secuencia de Arranque**
```
OnPluginStart() → Configuración básica y hooks
├── BuildPath() → Establece ruta de logs
├── g_SIConfig.Init() → Inicializa configuración de Special Infected
├── InitSpawnConfiguration() → Configura parámetros de spawn
├── HookEvent() → Registra eventos de L4D2
└── FindConVar() → Obtiene referencias a ConVars del juego
```

### **Carga Tardía (Late Load)**
```
AskPluginLoad2() → Manejo de carga tardía del plugin
├── RegisterNatives() → Registra funciones nativas para otros plugins
├── RegisterForwards() → Registra forwards para comunicación
└── RegPluginLibrary() → Registra biblioteca "l4d2_fix_spawn_order"
```

### **Configuración de Special Infected (`g_SIConfig.Init()`)**
```cpp
// Establece rangos de clases válidas
genericBegin = 1  // L4D2Infected_Smoker
genericEnd = 7    // L4D2Infected_Witch (no incluida)
maxSize = 10      // Tamaño total del array
```

---

## 🎮 Flujo de Ronda

### **Inicio de Ronda**
```
Event_RoundStart() → Reset inicial del sistema
├── g_gameState.isLive = false → Marca ronda como no activa
├── g_SpawnsArray.Clear() → Limpia cola de spawns
└── g_bSurvivorsLeftSafeArea = false → Reset estado safe area
```

### **Inicio de Ronda Real (Versus/Scavenge)**
```
Event_RealRoundStart() → Inicio efectivo del juego
├── L4D_HasPlayerControlledZombies() → Verifica infectados controlados
├── g_gameState.isLive = true → Activa el sistema
├── g_gameState.currentRound++ → Incrementa contador de ronda
├── FireGameStateChangedForward() → Notifica cambio de estado
├── FireRoundTransitionForward() → Notifica transición de ronda
├── L4D_HasAnySurvivorLeftSafeArea() → Verifica estado safe area
├── FillQueue() → Llena cola inicial de spawns
└── FireQueueRefilledForward() → Notifica llenado de cola
```

### **Salida de Safe Area**
```
L4D_OnFirstSurvivorLeftSafeArea_Post() → Primer superviviente sale
├── g_bSurvivorsLeftSafeArea = true → Habilita spawn de bots
├── SOLog.Events() → Log del evento
└── Call_StartForward(g_fwdOnGameStateChanged) → Notifica cambio
```

---

## 👤 Manejo de Jugadores

### **Conexión de Cliente**
```
OnClientPutInServer() → Cliente se conecta al servidor
├── IsValidClientIndex() → Valida índice de cliente
├── GetClientTeam() == 3 → Verifica equipo infectado
├── IsFakeClient() → Determina si es bot o humano
├── GetPlayerStoredClass() → Obtiene clase almacenada
├── SOLog.Events() → Log de conexión
└── FirePlayerClassChangedForward() → Notifica cambio de clase
```

### **Muerte de Jugador**
```
Event_PlayerDeath() → Jugador muere
├── GetClientOfUserId() → Obtiene cliente del evento
├── IsValidClientIndex() → Valida cliente
├── GetClientTeam() == 3 → Verifica equipo infectado
├── GetPlayerStoredClass() → Obtiene clase del jugador muerto
├── QueueSI() → Añade clase a la cola para re-spawn
├── SOLog.Events() → Log de muerte y re-queue
└── FirePlayerClassChangedForward() → Notifica cambio
```

---

## 🔄 Sistema de Cola

### **Llenado de Cola (`FillQueue()`)**
```
FillQueue() → Llena cola con clases disponibles
├── g_SpawnsArray.Clear() → Limpia cola actual
├── CollectZombies() → Cuenta infectados actuales por clase
├── BuildOptimalQueue() → Construye cola optimizada
├── SOLog.Queue() → Log de composición de cola
└── return g_SpawnsArray.Length → Retorna tamaño de cola
```

### **Construcción Óptima (`BuildOptimalQueue()`)**
```
BuildOptimalQueue() → Algoritmo de rotación natural
├── CalculateQueueLength() → Suma z_versus_*_limit
├── GetTotalInfectedPlayers() → Cuenta infectados totales
├── FOR cada clase SI (Smoker a Charger):
│   ├── adjustedLimits[SI] → Límite ajustado por clase
│   ├── needed = adjustedLimits[SI] - currentZombies[SI]
│   └── FOR needed > 0: g_SpawnsArray.Push(SI)
├── LightShuffleQueue() → Mezcla ligera para distribución
└── SOLog.Queue() → Log de cola construida
```

### **Mezclado Ligero (`LightShuffleQueue()`)**
```cpp
// Preserva patrones naturales de quad-cap
for (int start = 0; start < size - 1; start += 3) {
    int end = (start + 2 < size) ? start + 2 : size - 1;
    // Mini-shuffle en segmentos de 3 clases
    // Mantiene oportunidades de rotación natural
}
```

### **Extracción de Cola (`PopFromQueue()`)**
```
PopFromQueue() → Extrae siguiente clase válida
├── FOR each position in g_SpawnsArray:
│   ├── int SI = g_SpawnsArray.Get(i)
│   ├── CheckLimits(SI) → Valida límites de clase
│   ├── IF OverLimit_OK:
│   │   ├── g_SpawnsArray.Erase(i) → Remueve de cola
│   │   ├── SOLog.Queue() → Log de extracción exitosa
│   │   └── return SI → Retorna clase válida
│   └── ELSE: SOLog.Limits() → Log de límite excedido
└── return SI_None → Sin clases disponibles
```

---

## ⚖️ Validación de Límites

### **Verificación de Límites (`CheckLimits()`)**
```
CheckLimits(int zombieClass) → Verifica si clase puede spawn
├── CollectZombies() → Cuenta infectados actuales
├── IsDominator(zombieClass) → Verifica si es dominador
├── IF IsDominator:
│   ├── CountDominators() → Cuenta dominadores actuales
│   ├── IF dominatorCount >= 4:
│   │   └── return OverLimit_Dominator
├── classLimit = g_gameState.cvSILimits[zombieClass].IntValue
├── IF currentZombies[zombieClass] >= classLimit:
│   └── return OverLimit_Class
└── return OverLimit_OK
```

### **Detección de Dominadores (`IsDominator()`)**
```cpp
bool IsDominator(int zombieClass) {
    // Bitmask: 53 = 110101 (binario)
    // Posiciones: Smoker(1) + Hunter(4) + Jockey(16) + Charger(32)
    return (g_Dominators & (1 << (zombieClass - 1))) != 0;
}
```

### **Conteo de Infectados (`CollectZombies()`)**
```
CollectZombies(int[] zombieClasses) → Cuenta por clase
├── FOR client = 1 to MaxClients:
│   ├── IsClientInGame() → Verifica conexión
│   ├── GetClientTeam() == 3 → Verifica equipo infectado
│   ├── GetPlayerStoredClass() → Obtiene clase del jugador
│   └── zombieClasses[playerClass]++ → Incrementa contador
└── return total zombies counted
```

---

## 🤖 Integración de Bots

### **Detección de Tipo de Jugador**
```
GetInfectedPlayerCount() → Solo humanos
├── FOR client = 1 to MaxClients:
│   ├── IsClientInGame() && GetClientTeam() == 3
│   ├── !IsFakeClient() → Solo humanos reales
│   └── count++
└── return human infected count

GetTotalInfectedPlayers(includeHumans = true) → Todos
├── FOR client = 1 to MaxClients:
│   ├── IsClientInGame() && GetClientTeam() == 3  
│   ├── IF includeHumans OR IsFakeClient():
│   │   └── count++
└── return total infected count
```

### **Control de Spawn de Bots**
```
L4D_OnTryOfferingTankBot() → Bot Tank intenta spawn
├── IF !g_gameState.isLive → Rechaza si ronda no activa
├── IF !g_bSurvivorsLeftSafeArea → Rechaza si en safe area
├── SOLog.Events() → Log de decisión de spawn
└── return Plugin_Continue/Plugin_Handled
```

---

## 📊 Sistema de Eventos

### **Eventos de Hook**
```cpp
// Eventos principales registrados
HookEvent("round_start", Event_RoundStart);
HookEvent("round_end", Event_RoundEnd); 
HookEvent("versus_round_start", Event_RealRoundStart);
HookEvent("scavenge_round_start", Event_RealRoundStart);
HookEvent("player_death", Event_PlayerDeath);
```

### **Forwards del Plugin**
```cpp
// Comunicación con otros plugins
g_fwdOnRebalanceTriggered    → Rebalanceo iniciado
g_fwdOnQueueUpdated         → Cola actualizada
g_fwdOnPlayerClassChanged   → Clase de jugador cambió
g_fwdOnQueueRefilled        → Cola rellenada
g_fwdOnQueueEmptied         → Cola vacía
g_fwdOnLimitExceeded        → Límite excedido
g_fwdOnGameStateChanged     → Estado de juego cambió
```

### **Sistema de Logging (`SOLog`)**
```
SOLog.WriteLog(category, message) → Log categorizado
├── VFormat() → Formatea mensaje con argumentos
├── switch(category) → Determina prefijo por categoría
│   ├── SOLog_General → [FSO]
│   ├── SOLog_Queue → [FSO][Queue]  
│   ├── SOLog_Limits → [FSO][Limits]
│   ├── SOLog_Events → [FSO][Events]
│   └── SOLog_Rebalance → [FSO][Rebalance]
├── CPrintToChatAll() → Envía a chat con colores
├── CRemoveTags() → Remueve tags de color  
└── LogToFileEx() → Guarda en archivo de log
```

---

## 🎯 Comandos Administrativos

### **Estado de Cola (`Command_QueueStatus()`)**
```
sm_fso_queue_status → Análisis completo de cola
├── g_SpawnsArray.Length → Tamaño actual
├── FOR each position: GetSafeZombieClassName() → Nombres de clases
├── FOR each class: IsDominator() → Clasificación
├── AnalyzeQuadCapOpportunities() → Busca oportunidades naturales
├── GetInfectedPlayerCount() → Humanos vs bots
├── CalculateQueueLength() → Configuración z_versus_*_limit
└── ReplyToCommand() → Respuesta detallada al admin
```

### **Análisis de Equipo (`Command_TeamAnalysis()`)**
```
sm_fso_team_analysis → Composición detallada del equipo
├── GetInfectedPlayerCount() → Solo humanos
├── GetTotalInfectedPlayers() → Incluye bots
├── z_max_player_zombies.IntValue → Límite del servidor
├── CalculateQueueLength() → Suma de z_versus_*_limit
├── CollectZombies() → Distribución actual por clase
├── FOR each client: IsFakeClient() → Tipo de jugador
└── ReplyToCommand() → Análisis completo
```

---

## 🔄 Flujo Completo de Spawn

### **Secuencia Típica de Spawn**
```
1. Player dies → Event_PlayerDeath()
2. QueueSI(playerClass) → Añade clase a cola
3. Bot/Player spawns → L4D2 engine requests class
4. PopFromQueue() → Extrae clase válida
5. CheckLimits(SI) → Valida restricciones
6. IF valid → Assign class
7. IF invalid → Try next in queue
8. IF queue empty → FillQueue()
9. Repeat until valid class found
```

### **Gestión de Cola Vacía**
```
IF g_SpawnsArray.Length == 0:
├── SOLog.Queue("Queue is empty, refilling...")
├── FillQueue() → Reconstruye cola completa
├── FireQueueRefilledForward(FSO_REFILL_EMERGENCY)
└── PopFromQueue() → Intenta nuevamente
```

---

## 🎮 Integración con L4D2

### **Hooks de Left4DHooks**
```cpp
// Eventos nativos de L4D2 interceptados
L4D_OnFirstSurvivorLeftSafeArea_Post() → Safe area control
L4D_OnTryOfferingTankBot() → Tank bot spawn control
L4D_HasPlayerControlledZombies() → Verifica modo PvP
L4D_HasAnySurvivorLeftSafeArea() → Estado safe area
```

### **ConVars del Juego Utilizadas**
```cpp
z_max_player_zombies     → Límite de infectados simultáneos
z_versus_smoker_limit    → Smokers en cola
z_versus_boomer_limit    → Boomers en cola
z_versus_hunter_limit    → Hunters en cola
z_versus_spitter_limit   → Spitters en cola
z_versus_jockey_limit    → Jockeys en cola
z_versus_charger_limit   → Chargers en cola
```

Este flujo garantiza una **rotación natural** donde los quad-caps pueden emerger **espontáneamente** del orden de muertes, sin forzar patrones artificiales.
