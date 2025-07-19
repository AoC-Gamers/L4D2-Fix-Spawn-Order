#if defined _fso_api_included
	#endinput
#endif
#define _fso_api_included

// ====================================================================================================
// NATIVES AND FORWARDS DEFINITION
// ====================================================================================================

void RegisterNatives()
{
	CreateNative("FSO_GetQueuedSI", Native_GetQueuedSI);
	CreateNative("FSO_SetQueuedSI", Native_SetQueuedSI);
	CreateNative("FSO_GetPlayerStoredClass", Native_GetPlayerStoredClass);
	CreateNative("FSO_SetPlayerStoredClass", Native_SetPlayerStoredClass);
	CreateNative("FSO_IsPlayerSpawned", Native_IsPlayerSpawned);
	CreateNative("FSO_GetQueueSize", Native_GetQueueSize);
	CreateNative("FSO_ClearQueue", Native_ClearQueue);
	CreateNative("FSO_TriggerRebalance", Native_TriggerRebalance);
	CreateNative("FSO_GetGameState", Native_GetGameState);
}

void RegisterForwards()
{
	g_fwdOnRebalanceTriggered = new GlobalForward("FSO_OnRebalanceTriggered", ET_Event, Param_String);
	g_fwdOnQueueUpdated = new GlobalForward("FSO_OnQueueUpdated", ET_Event, Param_Cell, Param_Cell);
	g_fwdOnPlayerClassChanged = new GlobalForward("FSO_OnPlayerClassChanged", ET_Event, Param_Cell, Param_Cell, Param_Cell);
	g_fwdOnQueueRefilled = new GlobalForward("FSO_OnQueueRefilled", ET_Event, Param_Cell, Param_Cell);
	g_fwdOnQueueEmptied = new GlobalForward("FSO_OnQueueEmptied", ET_Event, Param_Cell, Param_Float);
	g_fwdOnPlayerClassForced = new GlobalForward("FSO_OnPlayerClassForced", ET_Event, Param_Cell, Param_Cell, Param_Cell, Param_String);
	g_fwdOnLimitExceeded = new GlobalForward("FSO_OnLimitExceeded", ET_Hook, Param_Cell, Param_Cell, Param_Cell, Param_CellByRef);
	g_fwdOnDominatorLimitHit = new GlobalForward("FSO_OnDominatorLimitHit", ET_Event, Param_Cell, Param_Cell, Param_Cell);
	g_fwdOnClassLimitHit = new GlobalForward("FSO_OnClassLimitHit", ET_Event, Param_Cell, Param_Cell, Param_Cell);
	g_fwdOnGameStateChanged = new GlobalForward("FSO_OnGameStateChanged", ET_Event, Param_Cell, Param_Cell, Param_Cell, Param_Cell);
	g_fwdOnRoundTransition = new GlobalForward("FSO_OnRoundTransition", ET_Event, Param_Cell, Param_Cell, Param_Cell);
	g_fwdOnConfigurationChanged = new GlobalForward("FSO_OnConfigurationChanged", ET_Event, Param_String, Param_Any, Param_Any);
}



// ====================================================================================================
// NATIVE IMPLEMENTATIONS
// ====================================================================================================

/**
 * Get the current queued SI array
 * native int FSO_GetQueuedSI(int[] buffer, int maxsize)
 */
public int Native_GetQueuedSI(Handle plugin, int numParams)
{
	int maxsize = GetNativeCell(2);
	if (maxsize <= 0)
		return 0;
	
	int queueSize = g_SpawnsArray.Length;
	int size = (queueSize < maxsize) ? queueSize : maxsize;
	
	if (size > 0)
	{
		int[] buffer = new int[size];
		for (int i = 0; i < size; i++)
		{
			buffer[i] = g_SpawnsArray.Get(i);
		}
		SetNativeArray(1, buffer, size);
	}
	
	return queueSize;
}

/**
 * Set the queued SI array
 * native bool FSO_SetQueuedSI(const int[] queue, int size)
 */
public int Native_SetQueuedSI(Handle plugin, int numParams)
{
	int size = GetNativeCell(2);
	
	if (size < 0 || size > MAX_SI_ARRAY_SIZE)
	{
		ThrowNativeError(SP_ERROR_NATIVE, "Invalid queue size: %d (max: %d)", size, MAX_SI_ARRAY_SIZE);
		return false;
	}
	
	// Store old size for forward
	int oldSize = g_SpawnsArray.Length;
	
	// Clear current queue
	g_SpawnsArray.Clear();
	
	if (size > 0)
	{
		int[] newQueue = new int[size];
		GetNativeArray(1, newQueue, size);
		
		// Validate and copy queue
		for (int i = 0; i < size; i++)
		{
			if (!g_SIConfig.IsValidSpawnableClass(newQueue[i]))
			{
				ThrowNativeError(SP_ERROR_NATIVE, "Invalid SI class in queue at index %d: %d", i, newQueue[i]);
				return false;
			}
			
			g_SpawnsArray.Push(newQueue[i]);
		}
	}
	
	// Fire forward
	Call_StartForward(g_fwdOnQueueUpdated);
	Call_PushCell(g_SpawnsArray.Length);
	Call_PushCell(oldSize);
	Call_Finish();
	
	SOLog.Debug("External plugin set queue to %d items", size);
	return true;
}

/**
 * Get player's stored class
 * native int FSO_GetPlayerStoredClass(int client)
 */
public int Native_GetPlayerStoredClass(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	
	if (!IsValidClientIndex(client))
	{
		ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index: %d", client);
		return SI_None;
	}
	
	return GetPlayerStoredClass(client);
}

/**
 * Set player's stored class
 * native bool FSO_SetPlayerStoredClass(int client, int zombieClass)
 */
public int Native_SetPlayerStoredClass(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	int zombieClass = GetNativeCell(2);
	
	if (!IsValidClientIndex(client))
	{
		ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index: %d", client);
		return false;
	}
	
	if (zombieClass != SI_None && !g_SIConfig.IsValidSpawnableClass(zombieClass))
	{
		ThrowNativeError(SP_ERROR_NATIVE, "Invalid zombie class: %d", zombieClass);
		return false;
	}
	
	// SetPlayerClass already handles the forward
	bool result = SetPlayerClass(client, zombieClass);
	return result;
}

/**
 * Check if player has spawned
 * native bool FSO_IsPlayerSpawned(int client)
 */
public int Native_IsPlayerSpawned(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	
	if (!IsValidClientIndex(client))
	{
		ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index: %d", client);
		return false;
	}
	
	return g_gameState.players[client].hasSpawned;
}

/**
 * Get current queue size
 * native int FSO_GetQueueSize()
 */
public int Native_GetQueueSize(Handle plugin, int numParams)
{
	return g_SpawnsArray.Length;
}

/**
 * Clear the entire queue
 * native void FSO_ClearQueue()
 */
public int Native_ClearQueue(Handle plugin, int numParams)
{
	int oldSize = g_SpawnsArray.Length;
	g_SpawnsArray.Clear();
	
	// Fire forward
	Call_StartForward(g_fwdOnQueueUpdated);
	Call_PushCell(0);
	Call_PushCell(oldSize);
	Call_Finish();
	
	SOLog.Debug("External plugin cleared queue (was %d items)", oldSize);
	return 0;
}

/**
 * Trigger a rebalance
 * native void FSO_TriggerRebalance(const char[] reason)
 */
public int Native_TriggerRebalance(Handle plugin, int numParams)
{
	char reason[64];
	GetNativeString(1, reason, sizeof(reason));
	
	ScheduleRebalance(reason);
	
	// Fire forward
	Call_StartForward(g_fwdOnRebalanceTriggered);
	Call_PushString(reason);
	Call_Finish();
	
	return 0;
}

/**
 * Get current game state information
 * native void FSO_GetGameState(bool &isLive, bool &isFinale, int &currentRound, float &lastRebalanceTime)
 */
public int Native_GetGameState(Handle plugin, int numParams)
{
	SetNativeCellRef(1, g_gameState.isLive);
	SetNativeCellRef(2, g_gameState.isFinale);
	SetNativeCellRef(3, g_gameState.currentRound);
	SetNativeCellRef(4, g_gameState.lastRebalanceTime);
	
	return 0;
}

// ====================================================================================================
// FORWARD HELPER FUNCTIONS
// ====================================================================================================

/**
 * Fire forward when queue is refilled
 */
void FireQueueRefilledForward(int newSize, int refillReason)
{
	Call_StartForward(g_fwdOnQueueRefilled);
	Call_PushCell(newSize);
	Call_PushCell(refillReason);
	Call_Finish();
}

/**
 * Fire forward when queue becomes empty
 */
void FireQueueEmptiedForward(int lastSize, float emptyTime)
{
	Call_StartForward(g_fwdOnQueueEmptied);
	Call_PushCell(lastSize);
	Call_PushFloat(emptyTime);
	Call_Finish();
}

/**
 * Fire forward when player class is forced by system
 */
void FirePlayerClassForcedForward(int client, int oldClass, int newClass, const char[] reason)
{
	Call_StartForward(g_fwdOnPlayerClassForced);
	Call_PushCell(client);
	Call_PushCell(oldClass);
	Call_PushCell(newClass);
	Call_PushString(reason);
	Call_Finish();
}

/**
 * Fire forward when a limit is exceeded (hookable)
 * @return Plugin_Continue to allow, Plugin_Handled to block
 */
Action FireLimitExceededForward(int limitType, int currentCount, int maxAllowed, int &newLimit)
{
	Action result = Plugin_Continue;
	Call_StartForward(g_fwdOnLimitExceeded);
	Call_PushCell(limitType);
	Call_PushCell(currentCount);
	Call_PushCell(maxAllowed);
	Call_PushCellRef(newLimit);
	Call_Finish(result);
	return result;
}

/**
 * Fire forward when dominator limit is hit
 */
void FireDominatorLimitHitForward(int dominatorClass, int currentCount, int maxAllowed)
{
	Call_StartForward(g_fwdOnDominatorLimitHit);
	Call_PushCell(dominatorClass);
	Call_PushCell(currentCount);
	Call_PushCell(maxAllowed);
	Call_Finish();
}

/**
 * Fire forward when class limit is hit
 */
void FireClassLimitHitForward(int zombieClass, int currentCount, int maxAllowed)
{
	Call_StartForward(g_fwdOnClassLimitHit);
	Call_PushCell(zombieClass);
	Call_PushCell(currentCount);
	Call_PushCell(maxAllowed);
	Call_Finish();
}

/**
 * Fire forward when game state changes
 */
void FireGameStateChangedForward(bool wasLive, bool isLive, bool wasFinale, bool isFinale)
{
	Call_StartForward(g_fwdOnGameStateChanged);
	Call_PushCell(wasLive);
	Call_PushCell(isLive);
	Call_PushCell(wasFinale);
	Call_PushCell(isFinale);
	Call_Finish();
}

/**
 * Fire forward during round transitions
 */
void FireRoundTransitionForward(int oldRound, int newRound, bool isFinale)
{
	Call_StartForward(g_fwdOnRoundTransition);
	Call_PushCell(oldRound);
	Call_PushCell(newRound);
	Call_PushCell(isFinale);
	Call_Finish();
}

/**
 * Fire forward when configuration changes
 */
void FireConfigurationChangedForward(const char[] configName, any oldValue, any newValue)
{
	Call_StartForward(g_fwdOnConfigurationChanged);
	Call_PushString(configName);
	Call_PushCell(oldValue);
	Call_PushCell(newValue);
	Call_Finish();
}