# 🏗️ Arquitectura del Plugin

## Estructura de Archivos

```
sourcemod/
├── plugins/
│   └── optional/
│       └── l4d2_fix_spawn_order.smx           # Plugin compilado
├── scripting/
│   ├── l4d2_fix_spawn_order.sp                # Archivo principal
│   ├── l4d2_fix_spawn_order_test.sp          # Versión de testing
│   ├── fix_spawn_order/                       # Módulos del sistema
│   │   ├── fso_api.sp                        # API pública y forwards
│   │   ├── fso_config.sp                     # Configuración y ConVars
│   │   ├── fso_events.sp                     # Manejo de eventos
│   │   └── fso_queue_limits.sp               # Lógica de cola y límites
│   └── include/
│       └── fix_spawn_order.inc               # Headers para otros plugins
```

## Módulos del Sistema

### **l4d2_fix_spawn_order.sp** - Coordinador Principal
**Responsabilidades:**
- Inicialización del plugin
- Registro de comandos administrativos
- Manejo de eventos del juego
- Control de safe area
- Logging y debugging

**Funciones Clave:**
- `OnPluginStart()`: Inicialización
- `Event_RealRoundStart()`: Inicio de ronda
- `Command_QueueStatus()`: Estado de cola
- `Command_TeamAnalysis()`: Análisis de equipo

### **fso_config.sp** - Gestión de Configuración
**Responsabilidades:**
- ConVars y límites de clases
- Configuración dinámica
- Cálculo de longitud de cola
- Scaling de equipos

**Estructuras Principales:**
```cpp
enum struct SIConfig {
    int genericBegin;        // Inicio de clases SI
    int genericEnd;          // Final de clases SI
    int limits[SI_MAX_SIZE]; // Límites por clase
}

enum struct GameState {
    bool isLive;                        // Estado del juego
    ConVar cvSILimits[SI_MAX_SIZE];    // ConVars z_versus_*_limit
    int iSILimit[SI_MAX_SIZE];         // Valores actuales
}

enum struct SpawnConfig {
    bool isDynamic;                     // Scaling dinámico
    float scalingFactor;               // Factor de escala
    int limits[SI_MAX_SIZE];           // Límites ajustados
    int currentPlayerCount;            // Jugadores actuales
}
```

**Funciones Clave:**
- `CalculateQueueLength()`: Suma de z_versus_*_limit
- `InitializeSILimitConVars()`: Configuración de ConVars
- `UpdateSpawnConfiguration()`: Actualización dinámica

### **fso_queue_limits.sp** - Motor de Cola FIFO
**Responsabilidades:**
- Algoritmo de rotación natural
- Construcción de cola óptima
- Validación de límites
- Detección de dominadores

**Algoritmos Principales:**

#### **`BuildOptimalQueue()`** - Rotación Natural
```cpp
// Filosofía: Añadir clases según necesidad real, no por tipo
for (int SI = genericBegin; SI < genericEnd; ++SI) {
    if (adjustedLimits[SI] <= 0) continue;
    
    int needed = adjustedLimits[SI] - currentZombies[SI];
    for (int j = 0; j < needed; ++j) {
        g_SpawnsArray.Push(SI); // Orden natural
    }
}

LightShuffleQueue(); // Mezcla ligera preservando patrones
```

#### **`LightShuffleQueue()`** - Distribución Inteligente
```cpp
// Mezcla en segmentos pequeños (2-3 clases)
// Preserva oportunidades de quad-cap naturales
int segmentSize = 3;
for (int start = 0; start < size - 1; start += segmentSize) {
    // Mini Fisher-Yates dentro del segmento
    // Mantiene algún flujo natural
}
```

#### **`PopQueuedSI()`** - Validación y Spawn
```cpp
// Intenta cada clase en la cola hasta encontrar una válida
for (int i = 0; i < queueSize; ++i) {
    int QueuedSI = g_SpawnsArray.Get(i);
    OverLimitReason status = IsOverLimit(QueuedSI);
    
    if (status == OverLimit_OK) {
        g_SpawnsArray.Erase(i); // Remueve de cola
        return QueuedSI;        // Spawn exitoso
    }
}
```

### **fso_events.sp** - Manejo de Eventos
**Responsabilidades:**
- Eventos de muerte de jugadores
- Conexión/desconexión de clientes
- Integración de bots
- Trigger de rebalance

**Eventos Principales:**
- `Event_PlayerDeath()`: Muerte de infectado
- `OnClientPutInServer()`: Nuevo cliente (incluye bots)
- `OnClientDisconnect()`: Desconexión de cliente

### **fso_api.sp** - API Pública
**Responsabilidades:**
- Natives para otros plugins
- Forwards/callbacks
- Funciones utilitarias públicas

**API Expuesta:**
```cpp
// Natives
native int FSO_GetQueueLength();
native int FSO_GetPlayerSpawnOrder(int client);
native bool FSO_IsClassDominator(int siClass);

// Forwards
forward void FSO_OnQueueRefilled(int newSize, int refillReason);
forward void FSO_OnPlayerClassChanged(int client, int oldClass, int newClass);
forward void FSO_OnLimitExceeded(int siClass, int currentCount, int limit);
```

## Flujo de Datos

### **Inicialización del Sistema**
```
1. OnPluginStart()
   ├── g_SIConfig.Init()
   ├── InitSpawnConfiguration()
   └── Hook de eventos

2. Event_RealRoundStart()
   ├── FillQueue()
   ├── UpdateSpawnConfiguration()
   └── FireQueueRefilledForward()
```

### **Ciclo de Spawn**
```
1. Event_PlayerDeath()
   └── Trigger rebalance si es necesario

2. L4D_OnSpawnSpecialInfected()
   ├── PopQueuedSI()
   ├── Validar límites
   ├── Actualizar configuración
   └── Log del resultado
```

### **Gestión de ConVars**
```
1. z_versus_*_limit cambia
   ├── OnSILimitChanged()
   ├── CalculateQueueLength()
   ├── UpdateSpawnConfiguration()
   └── Rebuild de cola si es necesario

2. z_max_player_zombies cambia
   ├── Actualizar capacidad de spawn
   └── Revalidar límites actuales
```

## Algoritmos Clave

### **Detección de Dominadores**
```cpp
bool IsDominator(int siClass) {
    // Clases que pueden incapacitar supervivientes
    return (siClass == L4D2Infected_Smoker  ||  // 1
            siClass == L4D2Infected_Hunter  ||  // 3
            siClass == L4D2Infected_Jockey  ||  // 5
            siClass == L4D2Infected_Charger);   // 6
    // No-dominadores: Boomer (2), Spitter (4)
}
```

### **Validación de Límites**
```cpp
OverLimitReason IsOverLimit(int SI) {
    // Verifica límites de dominadores
    if (IsDominator(SI) && dominatorCount >= maxDominators)
        return OverLimit_Dominator;
    
    // Verifica límites de clase individual
    if (classCount[SI] >= classLimit[SI])
        return OverLimit_Class;
        
    return OverLimit_OK;
}
```

### **Análisis de Quad-Caps**
```cpp
// Busca secuencias de 4 dominadores consecutivos en la cola
for (int i = 0; i <= queueSize - 4; i++) {
    bool allDominators = true;
    for (int j = i; j < i + 4; j++) {
        if (!IsDominator(g_SpawnsArray.Get(j))) {
            allDominators = false;
            break;
        }
    }
    if (allDominators) potentialQuadCaps++;
}
```