#if defined _fso_config_included
	#endinput
#endif
#define _fso_config_included


/**
 * SIConfig struct for managing Special Infected (SI) configuration.
 */
enum struct SIConfig {
    int genericBegin;
    int genericEnd;
    
    // Queue management
    int queueIndex;
    int queuedSITypes[MAX_SI_ARRAY_SIZE];
    
    // Limits configuration
    int limits[SI_MAX_SIZE];
    int initialLimits[SI_MAX_SIZE];
    int adjustedLimits[SI_MAX_SIZE];
    
    // Scaling configuration
    bool useScaling;
    float scalingFactor;
    
    void Init() {
        this.genericBegin = view_as<int>(L4D2ZombieClass_Smoker);
        this.genericEnd = view_as<int>(L4D2ZombieClass_Witch);
        this.queueIndex = 0;
        this.useScaling = false;
        this.scalingFactor = 1.0;
        
        // Initialize arrays
        for (int i = 0; i < MAX_SI_ARRAY_SIZE; i++) {
            this.queuedSITypes[i] = 0;
        }
        for (int i = 0; i < SI_MAX_SIZE; i++) {
            this.limits[i] = 0;
            this.initialLimits[i] = 0;
            this.adjustedLimits[i] = 0;
        }
    }
    
    bool IsValidSpawnableClass(int class) {
        return (class >= this.genericBegin && class < this.genericEnd);
    }
    
    int GetClassCount() {
        return this.genericEnd - this.genericBegin;
    }
}

/**
 * Player State Management
 */
enum struct PlayerState {
	int storedClass;
	bool hasSpawned;
	float lastClassChangeTime;
	bool isReconnecting;
}

/**
 * Game State Management
 */
enum struct GameState {
	bool isLive;
	bool isRebalancing;
	bool isFinale;
	float lastRebalanceTime;
	int currentPlayerCount;
	int expectedPlayerCount;
	int currentRound;
	
	// Configuration nested in GameState
	ConVar cvSILimits[SI_MAX_SIZE];
	int iSILimit[SI_MAX_SIZE];
	int iInitialSILimits[SI_MAX_SIZE];
	int maxInfected;
	PlayerState players[MAXPLAYERS+1];
}

/**
 * Spawn Configuration - Dynamic scaling and limits
 */
enum struct SpawnConfig {
	int limits[SI_MAX_SIZE];
	int initialLimits[SI_MAX_SIZE];
	int adjustedLimits[SI_MAX_SIZE];
	bool isDynamic;
	float scalingFactor;
}

// Rebalance timing control
static float g_fLastRebalanceAttempt = 0.0;

// Configuration ConVars
static ConVar g_cvSIDynamicScaling;
static ConVar g_cvSIMaxCapacity;

/**
 * Initialize spawn configuration system
 */
void InitSpawnConfiguration()
{
	// Initialize dynamic scaling ConVar
	g_cvSIDynamicScaling = CreateConVar("spawn_order_dynamic_scaling", "1", 
		"Enable dynamic SI limit scaling based on player count", 
		FCVAR_SPONLY, true, 0.0, true, 1.0);
	g_cvSIDynamicScaling.AddChangeHook(OnPluginConVarChanged);
	
	g_cvSIMaxCapacity = CreateConVar("spawn_order_max_capacity", "8", 
		"Maximum SI capacity for scaling calculations", 
		FCVAR_SPONLY, true, 4.0, true, 12.0);
	g_cvSIMaxCapacity.AddChangeHook(OnPluginConVarChanged);
	
	// Find and hook SI limit ConVars
	InitializeSILimitConVars();
	
	// Initialize spawn config with defaults
	ResetSpawnConfiguration();
	
	SOLog.Rebalance("Spawn configuration system initialized");
}

/**
 * Initialize SI limit ConVars
 */
void InitializeSILimitConVars()
{
	// Map SI classes to their ConVar names
	static const char sConVarNames[][] = {
		"", // SI_None placeholder
		"z_smoker_limit",
		"z_boomer_limit", 
		"z_hunter_limit",
		"z_spitter_limit",
		"z_jockey_limit",
		"z_charger_limit",
		"z_witch_limit",
		"z_tank_limit"
	};
	
	for (int i = g_SIConfig.genericBegin; i < g_SIConfig.genericEnd; i++)
	{
		g_gameState.cvSILimits[i] = FindConVar(sConVarNames[i]);
		if (g_gameState.cvSILimits[i])
		{
			g_gameState.cvSILimits[i].AddChangeHook(OnSILimitChanged);
			g_gameState.iSILimit[i] = g_gameState.cvSILimits[i].IntValue;
			g_gameState.iInitialSILimits[i] = g_gameState.iSILimit[i];
			
			SOLog.Rebalance("Hooked %s limit: %d", sConVarNames[i], g_gameState.iSILimit[i]);
		}
	}
}

/**
 * Reset spawn configuration to defaults
 */
void ResetSpawnConfiguration()
{
	g_SpawnConfig.isDynamic = g_cvSIDynamicScaling.BoolValue;
	g_SpawnConfig.scalingFactor = 1.0;
	
	// Copy initial limits
	for (int i = 0; i < SI_MAX_SIZE; i++)
	{
		g_SpawnConfig.limits[i] = g_gameState.iInitialSILimits[i];
		g_SpawnConfig.initialLimits[i] = g_gameState.iInitialSILimits[i];
		g_SpawnConfig.adjustedLimits[i] = g_gameState.iInitialSILimits[i];
	}
}

/**
 * Update spawn configuration based on current game state
 */
void UpdateSpawnConfiguration()
{
	int humanInfected = GetInfectedPlayerCount();
	int totalInfected = GetTotalInfectedPlayers(); // From fso_queue_limits.sp
	int maxPlayers = g_cvSIMaxCapacity.IntValue;
	
	g_gameState.currentPlayerCount = humanInfected;
	g_gameState.expectedPlayerCount = maxPlayers;
	
	// Calculate scaling factor if dynamic scaling is enabled
	if (g_SpawnConfig.isDynamic && maxPlayers > 0)
	{
		g_SpawnConfig.scalingFactor = float(humanInfected) / float(maxPlayers);
		
		// Apply minimum scaling threshold
		if (g_SpawnConfig.scalingFactor < 0.5)
			g_SpawnConfig.scalingFactor = 0.5;
	}
	else
	{
		g_SpawnConfig.scalingFactor = 1.0;
	}
	
	// Update adjusted limits
	UpdateAdjustedLimits();
	
	// Create detailed status message
	char queueInfo[256];
	GetQueueCompositionString(queueInfo, sizeof(queueInfo));
	
	SOLog.Rebalance("Configuration updated - Infected: %d humans + %d bots = %d/%d, Scaling: %.2f", 
		humanInfected, totalInfected - humanInfected, totalInfected, maxPlayers, g_SpawnConfig.scalingFactor);
	SOLog.Rebalance("Queue composition: %s", queueInfo);
}

/**
 * Update adjusted limits based on scaling factor
 */
void UpdateAdjustedLimits()
{
	for (int i = g_SIConfig.genericBegin; i < g_SIConfig.genericEnd; i++)
	{
		if (g_gameState.cvSILimits[i])
		{
			int baseLimit = g_SpawnConfig.initialLimits[i];
			int scaledLimit = RoundToNearest(float(baseLimit) * g_SpawnConfig.scalingFactor);
			
			// Ensure minimum of 1 for any non-zero limit
			if (baseLimit > 0 && scaledLimit < 1)
				scaledLimit = 1;
			
			g_SpawnConfig.adjustedLimits[i] = scaledLimit;
			g_SpawnConfig.limits[i] = scaledLimit;
			
			SOLog.Rebalance("Class %d: base=%d, scaled=%d (factor=%.2f)", 
				i, baseLimit, scaledLimit, g_SpawnConfig.scalingFactor);
		}
	}
}

/**
 * Schedule a rebalance operation with throttling
 */
void ScheduleRebalance(const char[] reason)
{
	float currentTime = GetGameTime();
	
	// Throttle rebalance requests
	if (currentTime - g_fLastRebalanceAttempt < REBALANCE_THROTTLE_TIME)
	{
		SOLog.Rebalance("Rebalance throttled (reason: %s)", reason);
		return;
	}
	
	g_fLastRebalanceAttempt = currentTime;
	g_gameState.lastRebalanceTime = currentTime;
	
	SOLog.Rebalance("Rebalance scheduled (reason: %s)", reason);
	
	// Execute rebalance on next frame to avoid recursion
	RequestFrame(UpdateSpawnConfiguration);
}

/**
 * Handle SI limit ConVar changes
 */
public void OnSILimitChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	// Find which SI limit was changed
	for (int i = g_SIConfig.genericBegin; i < g_SIConfig.genericEnd; i++)
	{
		if (g_gameState.cvSILimits[i] == convar)
		{
			int oldLimit = StringToInt(oldValue);
			int newLimit = StringToInt(newValue);
			g_gameState.iSILimit[i] = newLimit;
			g_SpawnConfig.initialLimits[i] = newLimit;
			
			// Get ConVar name for the forward
			char convarName[64];
			convar.GetName(convarName, sizeof(convarName));
			
			// Fire OnConfigurationChanged forward
			FireConfigurationChangedForward(convarName, oldLimit, newLimit);
			
			SOLog.Rebalance("SI limit changed for class %d: %s -> %s", i, oldValue, newValue);
			
			ScheduleRebalance("SI limit change");
			break;
		}
	}
}

/**
 * Handle configs executed event
 */
public void OnConfigsExecuted()
{
	// Initialize dominators from ConVar or use default (53 = Smoker + Hunter + Jockey + Charger)
	g_Dominators = 53;
	ConVar hDominators = FindConVar("l4d2_dominators");
	if (hDominators != null) 
		g_Dominators = hDominators.IntValue;
	
	// Update configuration after all configs are loaded
	UpdateSpawnConfiguration();
	ScheduleRebalance("configs executed");
}

/**
 * Get current infected player count
 */
int GetInfectedPlayerCount()
{
	int count = 0;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(i) == 3)
		{
			count++;
		}
	}
	return count;
}

/**
 * Handle plugin ConVar changes (dynamic scaling and max capacity)
 */
public void OnPluginConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	char convarName[64];
	convar.GetName(convarName, sizeof(convarName));
	
	if (convar == g_cvSIDynamicScaling)
	{
		bool oldScaling = StringToInt(oldValue) != 0;
		bool newScaling = StringToInt(newValue) != 0;
		
		// Fire OnConfigurationChanged forward
		FireConfigurationChangedForward(convarName, oldScaling, newScaling);
		
		SOLog.Rebalance("Dynamic scaling changed: %s -> %s", oldValue, newValue);
		
		if (oldScaling != newScaling)
		{
			ScheduleRebalance("Dynamic scaling toggle");
		}
	}
	else if (convar == g_cvSIMaxCapacity)
	{
		int oldCapacity = StringToInt(oldValue);
		int newCapacity = StringToInt(newValue);
		
		// Fire OnConfigurationChanged forward
		FireConfigurationChangedForward(convarName, oldCapacity, newCapacity);
		
		SOLog.Rebalance("Max capacity changed: %s -> %s", oldValue, newValue);
		
		if (oldCapacity != newCapacity)
		{
			ScheduleRebalance("Max capacity change");
		}
	}
}

// ====================================================================================================
// QUEUE COMPOSITION UTILITIES
// ====================================================================================================

/**
 * Get a formatted string showing current queue composition by SI types
 */
void GetQueueCompositionString(char[] buffer, int maxlen)
{
	// Get current queue size
	int queueSize = g_SpawnsArray.Length;
	
	if (queueSize == 0)
	{
		strcopy(buffer, maxlen, "Empty");
		return;
	}
	
	// Count each SI type in queue
	int counts[7]; // 0=none, 1=smoker, 2=boomer, 3=hunter, 4=spitter, 5=jockey, 6=charger
	for (int i = 0; i < queueSize; i++)
	{
		int siClass = g_SpawnsArray.Get(i);
		if (siClass >= 1 && siClass <= 6)
		{
			counts[siClass]++;
		}
	}
	
	// Build composition string
	buffer[0] = '\0';
	bool hasAny = false;
	
	for (int i = 1; i <= 6; i++)
	{
		if (counts[i] > 0)
		{
			char className[16];
			GetSIClassName(i, className, sizeof(className));
			
			if (hasAny)
			{
				Format(buffer, maxlen, "%s, ", buffer);
			}
			
			Format(buffer, maxlen, "%s%dx%s", buffer, counts[i], className);
			hasAny = true;
		}
	}
	
	if (!hasAny)
	{
		strcopy(buffer, maxlen, "No valid SI in queue");
	}
}

/**
 * Get SI class name by index
 */
void GetSIClassName(int classIndex, char[] buffer, int maxlen)
{
	switch (classIndex)
	{
		case 1: strcopy(buffer, maxlen, "Smoker");
		case 2: strcopy(buffer, maxlen, "Boomer");
		case 3: strcopy(buffer, maxlen, "Hunter");
		case 4: strcopy(buffer, maxlen, "Spitter");
		case 5: strcopy(buffer, maxlen, "Jockey");
		case 6: strcopy(buffer, maxlen, "Charger");
		default: Format(buffer, maxlen, "Unknown(%d)", classIndex);
	}
}


