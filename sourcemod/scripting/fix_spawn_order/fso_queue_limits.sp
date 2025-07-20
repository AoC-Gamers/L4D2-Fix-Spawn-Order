#if defined _fso_queue_limits_included
	#endinput
#endif
#define _fso_queue_limits_included

// ====================================================================================================
// QUEUE MANAGEMENT
// ====================================================================================================

/**
 * Queues a Special Infected (SI) type into the spawn array.
 *
 * @param SI        The integer representing the Special Infected type to queue.
 * @param front     If true, the SI is queued at the front of the array; otherwise, it is queued at the end.
 */
void QueueSI(int SI, bool front)
{
	int oldSize = g_SpawnsArray.Length;
	
	if (front && g_SpawnsArray.Length)
	{
		g_SpawnsArray.ShiftUp(0);
		g_SpawnsArray.Set(0, SI);
	}
	else
	{
		g_SpawnsArray.Push(SI);
	}
	
	// Fire OnQueueUpdated forward
	if (g_fwdOnQueueUpdated != null)
	{
		Call_StartForward(g_fwdOnQueueUpdated);
		Call_PushCell(g_SpawnsArray.Length);
		Call_PushCell(oldSize);
		Call_Finish();
	}
	
	char zombieClassName[32];
	GetSafeZombieClassName(SI, zombieClassName, sizeof(zombieClassName));
	SOLog.Queue("Queuing (\x05%s\x01) to \x04%s", zombieClassName, front ? "the front" : "the end");
}

/**
 * Queue a player's SI class based on their stored class and spawn state
 * This is the main function that connects player events to the queue system
 */
void QueuePlayerSI(int client)
{
	if (!IsValidClientIndex(client))
		return;
		
	int SI = GetPlayerStoredClass(client);
	if (!g_SIConfig.IsValidSpawnableClass(SI))
		return;
	
	// Check if this class can be queued based on initial limits
	if (IsAbleToQueue(SI, client))
	{
		QueueSI(SI, !g_gameState.players[client].hasSpawned);
	}
	
	// Reset player state
	g_gameState.players[client].storedClass = SI_None;
	g_gameState.players[client].hasSpawned = false;
}

/**
 * Attempts to pop a valid Special Infected (SI) class from the spawn queue
 * 
 * @param skip_client   The client index to skip when checking spawn limits.
 * @return              The SI class index that was popped from the queue, or SI_None if none is available.
 */
int PopQueuedSI(int skip_client)
{
	int size = g_SpawnsArray.Length;
	if (!size)
	{
		SOLog.Queue("Queue is empty, attempting emergency refill");
		
		// Fire OnQueueEmptied forward
		FireQueueEmptiedForward(0, GetGameTime());
		
		// Emergency refill if queue is empty but round is live
		if (g_gameState.isLive)
		{
			BuildOptimalQueue();
			size = g_SpawnsArray.Length;
			if (!size)
			{
				SOLog.Queue("Emergency refill failed - no valid classes available");
				return SI_None;
			}
			
			// Fire OnQueueRefilled forward for emergency refill
			FireQueueRefilledForward(size, FSO_REFILL_EMERGENCY);
		}
		else
		{
			return SI_None;
		}
	}
	
	for (int i = 0; i < size; ++i)
	{
		int QueuedSI = g_SpawnsArray.Get(i);
		
		OverLimitReason status = IsClassOverLimit(QueuedSI, skip_client);
		if (status == OverLimit_OK)
		{
			int oldSize = g_SpawnsArray.Length;
			g_SpawnsArray.Erase(i);
			
			// Fire OnQueueUpdated forward
			if (g_fwdOnQueueUpdated != null)
			{
				Call_StartForward(g_fwdOnQueueUpdated);
				Call_PushCell(g_SpawnsArray.Length);
				Call_PushCell(oldSize);
				Call_Finish();
			}
			
			char zombieClassName[32];
			GetSafeZombieClassName(QueuedSI, zombieClassName, sizeof(zombieClassName));
			SOLog.Queue("Popped (\x05%s\x01) [%s] after \x04%i \x01%s", 
				zombieClassName, 
				IsDominator(QueuedSI) ? "DOMINATOR" : "NON-DOMINATOR",
				i+1, i+1 > 1 ? "tries" : "try");
			
			return QueuedSI;
		}
		else
		{
			char reasonText[32];
			char zombieClassName[32];
			GetOverLimitReasonText(status, reasonText, sizeof(reasonText));
			GetSafeZombieClassName(QueuedSI, zombieClassName, sizeof(zombieClassName));
			SOLog.Limits("Popping (\x05%s\x01) but \x03over limit \x01(\x03reason: %s\x01)", zombieClassName, reasonText);
		}
	}
	
	SOLog.Queue("\x04Failed to pop queued SI! \x01(size = \x05%i\x01) - Trying fallback", size);
	
	// Try to add a fallback SI that's under basic limit
	for (int SI = g_SIConfig.genericBegin; SI < g_SIConfig.genericEnd; ++SI)
	{
		OverLimitReason status = IsClassOverLimit(SI, skip_client);
		if (status == OverLimit_OK)
		{
			char zombieClassName[32];
			GetSafeZombieClassName(SI, zombieClassName, sizeof(zombieClassName));
			SOLog.Queue("Adding fallback class: %s", zombieClassName);
			return SI;
		}
	}
	
	SOLog.Queue("\x04Complete failure to provide any SI class!");
	return SI_None;
}

/**
 * Build an optimal queue based on current game state with natural rotation
 */
void BuildOptimalQueue()
{
	int currentZombies[SI_MAX_SIZE] = {0};
	int queuedZombies[SI_MAX_SIZE] = {0};
	
	// Collect current state
	CollectZombies(currentZombies, -1);
	
	char classString[80] = "";  // Optimized: was 255, now 80 (sufficient for all class names)
	int totalAdded = 0;
	
	// Clear queue before building
	g_SpawnsArray.Clear();
	
	// Add missing classes to reach minimum representation (natural order, no priority)
	for (int SI = g_SIConfig.genericBegin; SI < g_SIConfig.genericEnd; ++SI)
	{
		if (g_SpawnConfig.adjustedLimits[SI] <= 0)
			continue;
			
		int needed = g_SpawnConfig.adjustedLimits[SI] - currentZombies[SI];
		
		for (int j = 0; j < needed; ++j)
		{
			g_SpawnsArray.Push(SI);
			queuedZombies[SI]++;
			totalAdded++;
			
			StrCat(classString, sizeof(classString), L4D2ZombieClassname[SI - 1]);
			StrCat(classString, sizeof(classString), STRING_SEPARATOR);
		}
		
		SOLog.Queue("Class %s: current=%d, limit=%d, added=%d", 
			L4D2ZombieClassname[SI - 1], currentZombies[SI], g_SpawnConfig.adjustedLimits[SI], needed);
	}
	
	// Add rotation classes if queue is too small (natural representation)
	int teamBasedQueueSize = z_max_player_zombies.IntValue + 2; // +2 for backup classes
	int minQueueSize = (teamBasedQueueSize > MIN_QUEUE_SIZE) ? teamBasedQueueSize : MIN_QUEUE_SIZE;
	if (totalAdded < minQueueSize)
	{
		AddRotationClasses(queuedZombies, minQueueSize - totalAdded);
	}
	
	// Light shuffle for better distribution without destroying natural quad-cap opportunities
	LightShuffleQueue();
	
	int idx = strlen(classString) - 2;
	if (idx < 0) idx = 0;
	classString[idx] = '\0';
	
	SOLog.Queue("Built natural queue (%s) - Total: %d classes", classString, totalAdded);
}

/**
 * Add rotation classes to ensure minimum queue size (legacy function)
 */
void AddRotationClasses(int queuedZombies[SI_MAX_SIZE], int needed)
{
	for (int i = 0; i < needed; ++i)
	{
		int bestClass = SI_None;
		int minCount = 999;
		
		// Find class with lowest current representation
		for (int SI = g_SIConfig.genericBegin; SI < g_SIConfig.genericEnd; ++SI)
		{
			if (g_SpawnConfig.adjustedLimits[SI] <= 0)
				continue;
				
			int totalCount = queuedZombies[SI];
			if (totalCount < minCount)
			{
				minCount = totalCount;
				bestClass = SI;
			}
		}
		
		if (bestClass != SI_None)
		{
			g_SpawnsArray.Push(bestClass);
			queuedZombies[bestClass]++;
			SOLog.Queue("Added rotation class: %s", L4D2ZombieClassname[bestClass - 1]);
		}
		else
		{
			break; // No valid classes available
		}
	}
}

/**
 * Light shuffle to improve distribution while preserving natural quad-cap opportunities
 * This only shuffles within small segments to avoid forcing artificial patterns
 */
void LightShuffleQueue()
{
	int size = g_SpawnsArray.Length;
	if (size <= 3) return; // Don't shuffle very small queues
	
	// Shuffle in small segments of 2-3 classes to maintain some natural flow
	// This allows for quad-caps to develop naturally without forcing them
	int segmentSize = 3;
	for (int start = 0; start < size - 1; start += segmentSize)
	{
		int end = (start + segmentSize < size) ? start + segmentSize : size;
		
		// Mini Fisher-Yates shuffle within segment
		for (int i = end - 1; i > start; i--)
		{
			int j = GetRandomInt(start, i);
			
			int temp = g_SpawnsArray.Get(i);
			g_SpawnsArray.Set(i, g_SpawnsArray.Get(j));
			g_SpawnsArray.Set(j, temp);
		}
	}
	
	SOLog.Queue("Light shuffle applied - preserving natural rotation patterns");
}

/**
 * Fill queue based on z_versus_*_limit ConVars
 * Queue length is determined by the sum of all z_versus_*_limit values
 * Spawn capacity is determined by z_max_player_zombies
 */
void FillQueue()
{
	int oldSize = g_SpawnsArray.Length;
	int zombies[SI_MAX_SIZE] = {0};
	CollectZombies(zombies);
	
	char classString[255] = "";
	
	// Calculate how many of each class should be in the queue based on z_versus_*_limit
	for (int SI = g_SIConfig.genericBegin; SI < g_SIConfig.genericEnd; ++SI)
	{
		if (!g_gameState.cvSILimits[SI])
			continue;
			
		// Use z_versus_*_limit values to determine queue composition
		int queueLimit = g_gameState.cvSILimits[SI].IntValue;
		
		// Add each class to the queue according to its z_versus_*_limit
		for (int j = 0; j < queueLimit; ++j)
		{
			g_SpawnsArray.Push(SI);
			
			StrCat(classString, sizeof(classString), L4D2ZombieClassname[SI - 1]);
			StrCat(classString, sizeof(classString), STRING_SEPARATOR);
		}
		
		SOLog.Queue("Added %d %s to queue (z_versus_%s_limit)", 
			queueLimit, L4D2ZombieClassname[SI - 1], L4D2ZombieClassname[SI - 1]);
	}
	
	int idx = strlen(classString) - 2;
	if (idx < 0) idx = 0;
	classString[idx] = '\0';
	
	// Calculate total queue length and current spawn capacity
	int totalQueueLength = CalculateQueueLength(); // Sum of all z_versus_*_limit
	int maxSpawnCapacity = z_max_player_zombies.IntValue; // Current spawn limit
	
	SOLog.Queue("Queue filled: %d total classes, %d max concurrent spawns", 
		totalQueueLength, maxSpawnCapacity);
	
	// Fire OnQueueUpdated forward
	if (g_fwdOnQueueUpdated != null)
	{
		Call_StartForward(g_fwdOnQueueUpdated);
		Call_PushCell(g_SpawnsArray.Length);
		Call_PushCell(oldSize);
		Call_Finish();
	}
	
	// Fire OnQueueRefilled forward
	FireQueueRefilledForward(g_SpawnsArray.Length, FSO_REFILL_AUTOMATIC);
	
	SOLog.Queue("Filled queue (%s)", classString);
}

/**
 * Check if specific class can be queued based on dynamic adjusted limits
 * This uses adjusted limits from rebalance instead of static limits
 */
bool IsAbleToQueue(int SI, int skip_client)
{
	if (!g_SIConfig.IsValidSpawnableClass(SI))
		return false;
	
	int counts[SI_MAX_SIZE] = {0};
	
	// NOTE: We're checking after player actually spawns, it's necessary to ignore his class.
	CollectZombies(counts, skip_client);
	CollectQueuedZombies(counts);
	
	// Use adjusted limits from rebalance, not static limits
	int maxAllowed = g_SpawnConfig.adjustedLimits[SI];
	if (counts[SI] < maxAllowed)
	{
		return true;
	}
	else
	{
		SOLog.Limits("Cannot queue \x05%s\x01 (count=\x04%d\x01 >= adjusted limit=\x04%d\x01)", 
			L4D2ZombieClassname[SI - 1], counts[SI], maxAllowed);
		return false;
	}
}

/**
 * Collect queued zombie class distribution for limit checking
 */
int CollectQueuedZombies(int zombies[SI_MAX_SIZE])
{
	int size = g_SpawnsArray.Length;
	char classString[128] = "";
	
	for (int i = 0; i < size; ++i)
	{
		int SI = g_SpawnsArray.Get(i);
		if (g_SIConfig.IsValidSpawnableClass(SI))
		{
			zombies[SI]++;
			StrCat(classString, sizeof(classString), L4D2ZombieClassname[SI - 1]);
			StrCat(classString, sizeof(classString), STRING_SEPARATOR);
		}
	}
	
	int idx = strlen(classString) - 2;
	if (idx < 0) idx = 0;
	classString[idx] = '\0';
	SOLog.Queue("Collect queued zombies (%s)", classString);
	
	return size;
}

// ====================================================================================================
// LIMIT CHECKING SYSTEM
// ====================================================================================================

/**
 * Checks if a Special Infected (SI) class exceeds its spawn limit
 *
 * @param SI           The SI class to check
 * @param skip_client  Client to skip in calculations
 * @return             OverLimitReason indicating if and why the class is over limit
 */
OverLimitReason IsClassOverLimit(int SI, int skip_client)
{
	if (!g_gameState.cvSILimits[SI])
		return OverLimit_OK;
	
	int counts[SI_MAX_SIZE] = {0};
	
	// NOTE: We're checking after player actually spawns, it's necessary to ignore his class.
	CollectZombies(counts, skip_client);
	
	// Log detailed limit checking parameters
	SOLog.Limits("Checking OverLimit for \x05%s\x01: current=\x04%d\x01, staticLimit=\x04%d\x01, adjustedLimit=\x04%d\x01", 
		L4D2ZombieClassname[SI-1], counts[SI], 
		g_gameState.cvSILimits[SI].IntValue, g_SpawnConfig.adjustedLimits[SI]);
	
	if (counts[SI] >= g_gameState.cvSILimits[SI].IntValue)
	{
		// Fire OnClassLimitHit forward
		FireClassLimitHitForward(SI, counts[SI], g_gameState.cvSILimits[SI].IntValue);
		return OverLimit_Class;
	}
	
	if (!IsDominator(SI))
		return OverLimit_OK;
	
	int dominatorCount = 0;
	for (int i = g_SIConfig.genericBegin; i < g_SIConfig.genericEnd; ++i)
		if (IsDominator(i)) dominatorCount += counts[i];
	
	// Log dominator checking parameters
	SOLog.Limits("Dominator check for \x05%s\x01: dominatorCount=\x04%d\x01, maxDefault=\x043\x01", 
		L4D2ZombieClassname[SI-1], dominatorCount);
	
	// Call forward to allow dominator limit override
	int maxDominatorCount = 3;
	int newLimit = maxDominatorCount;
	Action limitResult = FireLimitExceededForward(FSO_LIMIT_DOMINATOR, dominatorCount, maxDominatorCount, newLimit);
	if (limitResult == Plugin_Handled)
	{
		maxDominatorCount = newLimit;
		SOLog.Limits("Forward overrode dominator limit: \x04%d -> %d\x01", 3, maxDominatorCount);
	}
	
	if (dominatorCount >= maxDominatorCount)
	{
		SOLog.Limits("Dominator limit exceeded for \x05%s\x01: count=\x04%d\x01 >= limit=\x04%d\x01", 
			L4D2ZombieClassname[SI-1], dominatorCount, maxDominatorCount);
		// Fire OnDominatorLimitHit forward
		FireDominatorLimitHitForward(SI, dominatorCount, maxDominatorCount);
		return OverLimit_Dominator;
	}
	
	SOLog.Limits("Class \x05%s\x01 passed all limit checks", L4D2ZombieClassname[SI-1]);
	return OverLimit_OK;
}

/**
 * Check if a class is a dominator (Tank, Witch, etc.)
 */
bool IsDominator(int SI)
{
	return (g_Dominators & (1 << (SI-1))) > 0;
}

// ====================================================================================================
// DATA COLLECTION
// ====================================================================================================

/**
 * Collect current zombie class distribution
 */
int CollectZombies(int zombies[SI_MAX_SIZE], int skip_client = -1)
{
	int count = 0;
	char classString[128] = "";
	
	for (int i = 1; i <= MaxClients; ++i)
	{
		if (i == skip_client || !IsClientInGame(i) || !IsClientInfected(i))
			continue;
		
		int SI = GetPlayerStoredClass(i);
		if (!g_SIConfig.IsValidSpawnableClass(SI))
		{
			// Check if player is actually alive with a different class
			if (IsPlayerAlive(i))
			{
				SI = view_as<int>(L4D2_GetPlayerZombieClass(i));
				if (g_SIConfig.IsValidSpawnableClass(SI))
				{
					// Update stored class to match actual class
					SetPlayerClass(i, SI);
				}
			}
		}
		
		if (g_SIConfig.IsValidSpawnableClass(SI))
		{
			zombies[SI]++;
			count++;
			StrCat(classString, sizeof(classString), L4D2ZombieClassname[SI - 1]);
			StrCat(classString, sizeof(classString), STRING_SEPARATOR);
		}
		else if (IsPlayerAlive(i))
		{
			// Player is alive but has no valid class - this indicates a problem
			SOLog.Debug("Warning: Player %N alive but no valid class (stored: %d, current: %d)", 
				i, SI, view_as<int>(L4D2_GetPlayerZombieClass(i)));
		}
	}
	
	int idx = strlen(classString) - 2;
	if (idx < 0) idx = 0;
	classString[idx] = '\0';
	SOLog.Debug("Collect zombies (%s) - Total: %d", classString, count);
	
	return count;
}

/**
 * Get total infected players (human only or including bots)
 */
int GetTotalInfectedPlayers(bool humanOnly = false)
{
	int count = 0;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && GetClientTeam(i) == 3)
		{
			if (!humanOnly || !IsFakeClient(i))
				count++;
		}
	}
	return count;
}

/**
 * Get count of specific SI class
 */

