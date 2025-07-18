#if defined _fso_events_included
	#endinput
#endif
#define _fso_events_included

/**
 * Update player class with validation
 */
bool SetPlayerClass(int client, int newClass)
{
	if (client < 1 || client > MaxClients || !IsClientInGame(client))
		return false;
		
	if (newClass != SI_None && (newClass < g_SIConfig.genericBegin || newClass >= g_SIConfig.genericEnd))
		return false;
	
	int oldClass = g_gameState.players[client].storedClass;
	g_gameState.players[client].storedClass = newClass;
	g_gameState.players[client].lastClassChangeTime = GetGameTime();
	
	// Use safe class name getter for debug output
	char oldClassName[32], newClassName[32];
	char noneString[] = "None";  // Local variable instead of global constant
	
	if (oldClass == SI_None)
		strcopy(oldClassName, sizeof(oldClassName), noneString);
	else
		strcopy(oldClassName, sizeof(oldClassName), L4D2ZombieClassname[oldClass - 1]);
		
	if (newClass == SI_None)
		strcopy(newClassName, sizeof(newClassName), noneString);
	else
		strcopy(newClassName, sizeof(newClassName), L4D2ZombieClassname[newClass - 1]);
	
	SOLog.Events("Player %N class changed: %s -> %s", client, oldClassName, newClassName);
	
	// Fire OnPlayerClassChanged forward
	if (g_fwdOnPlayerClassChanged != null)
	{
		Call_StartForward(g_fwdOnPlayerClassChanged);
		Call_PushCell(client);
		Call_PushCell(oldClass);
		Call_PushCell(newClass);
		Call_Finish();
	}
	
	return true;
}

/**
 * Get player's stored class
 */
int GetPlayerStoredClass(int client)
{
	if (client < 1 || client > MaxClients)
		return SI_None;
		
	return g_gameState.players[client].storedClass;
}

/**
 * Reset player state to defaults
 */
void ResetPlayerState(int client)
{
	if (client < 1 || client > MaxClients)
		return;
		
	g_gameState.players[client].storedClass = SI_None;
	g_gameState.players[client].hasSpawned = false;
	g_gameState.players[client].lastClassChangeTime = 0.0;
	g_gameState.players[client].isReconnecting = false;
}

// ====================================================================================================
// CLIENT CONNECTION EVENTS
// ====================================================================================================

/**
 * Handle client joining server
 */
public void OnClientPutInServer(int client)
{
	ResetPlayerState(client);
	
	if (IsFakeClient(client) || !IsClientInfected(client))
		return;
	
	// Check if we need to trigger rebalance for new human player
	if (g_gameState.isLive)
	{
		SOLog.Rebalance("Player %N joined infected team - triggering rebalance", client);
		ScheduleRebalance("player joined");
	}
}

/**
 * Handle client leaving server
 */
public void OnClientDisconnect(int client)
{
	if (!IsClientInGame(client))
		return;
		
	// Store disconnection state for potential reconnection
	g_gameState.players[client].isReconnecting = true;
	
	// Schedule rebalance if infected player left
	if (IsClientInfected(client) && g_gameState.isLive)
	{
		ScheduleRebalance("player disconnected");
	}
	
	// Clean up player state after delay
	CreateTimer(5.0, Timer_CleanupPlayerState, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
}

/**
 * Cleanup player state after disconnection
 */
public Action Timer_CleanupPlayerState(Handle timer, int userid)
{
	int client = GetClientOfUserId(userid);
	if (client > 0)
	{
		ResetPlayerState(client);
	}
	return Plugin_Stop;
}

// ====================================================================================================
// L4D2 SPAWN EVENTS
// ====================================================================================================

/**
 * Handle player materializing from ghost
 */
public void L4D_OnMaterializeFromGhost_PostHandled(int client)
{
	if (!IsClientInGame(client) || !IsClientInfected(client))
		return;
	
	// Update player state
	g_gameState.players[client].hasSpawned = true;
	
	// Get and store the materialized class
	int zombieClass = view_as<int>(L4D2_GetPlayerZombieClass(client));
	if (g_SIConfig.IsValidSpawnableClass(zombieClass))
	{
		SetPlayerClass(client, zombieClass);
		SOLog.Events("\x05%N \x05materialized \x01as (\x04%s\x01)", client, L4D2ZombieClassname[zombieClass - 1]);
	}
	else
	{
		SOLog.Events("\x05%N \x05got de-materialized because of other plugins' handling.", client);
	}
	
	// Check for capacity overflow and handle culling
	HandleCapacityOverflow(client);
}

/**
 * Handle capacity overflow with bot culling
 */
void HandleCapacityOverflow(int client)
{
	int maxInfected = z_max_player_zombies.IntValue;
	int currentInfected = GetTotalInfectedPlayers();
	
	if (currentInfected > maxInfected)
	{
		SOLog.Events("Infected Team is \x04going over capacity \x01after \x05%N \x01joined", client);
		
		// Find and cull the oldest bot
		int lastBot = -1;
		float oldestTime = GetGameTime();
		
		for (int i = 1; i <= MaxClients; i++)
		{
			if (i == client || !IsClientInGame(i) || !IsFakeClient(i) || !IsClientInfected(i))
				continue;
				
			if (!IsPlayerAlive(i))
				continue;
				
			float spawnTime = g_gameState.players[i].lastClassChangeTime;
			if (spawnTime < oldestTime)
			{
				oldestTime = spawnTime;
				lastBot = i;
			}
		}
		
		if (lastBot > 0)
		{
			SOLog.Events("\x05%N is selected to cull", lastBot);
			ForcePlayerSuicide(lastBot);
		}
	}
}

/**
 * Handle player leaving infected team
 */
public void L4D_OnEnterGhostState(int client)
{
	if (!IsClientInGame(client) || !IsClientInfected(client))
		return;
		
	if (IsPlayerAlive(client))
	{
		SOLog.Events("\x05%N \x01left Infected Team \x01as (\x04%s\x01)", client, L4D2ZombieClassname[view_as<int>(L4D2_GetPlayerZombieClass(client)) - 1]);
		
		// Use the centralized queue system
		QueuePlayerSI(client);
	}
	else
	{
		ResetPlayerState(client);
	}
}

/**
 * Handle player death
 */
public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	
	if (!IsClientInGame(client) || !IsClientInfected(client))
		return;
		
	SOLog.Events("\x05%N \x01died \x01as (\x04%s\x01)", client, L4D2ZombieClassname[view_as<int>(L4D2_GetPlayerZombieClass(client)) - 1]);
	
	// Queue the player's class back using centralized system
	QueuePlayerSI(client);
}

// ====================================================================================================
// TANK REPLACEMENT SYSTEM
// ====================================================================================================

/**
 * Handle tank replacement between players
 */
public void L4D_OnReplaceTank(int tank, int newtank)
{
	if (!IsClientInGame(tank) || !IsClientInGame(newtank))
		return;
	
	// Transfer stored class from old tank to new tank
	int tankClass = GetPlayerStoredClass(tank);
	
	// Fire OnPlayerClassForced forward for tank replacement
	if (tankClass != SI_None)
		FirePlayerClassForcedForward(newtank, SI_None, tankClass, "Tank replacement");
	
	SetPlayerClass(newtank, tankClass);
	SetPlayerClass(tank, SI_None);
	
	// Handle AI tank replacement
	if (IsFakeClient(tank))
	{
		SOLog.Events("\x05%N \x01replaced \x05%N \x01as (\x04%s\x01)", newtank, tank, L4D2ZombieClassname[view_as<int>(L4D2_GetPlayerZombieClass(newtank)) - 1]);
		
		if (tankClass != SI_None)
		{
			SOLog.Events("\x05%N \x01(\x04%s\x01) \x01replaced an \x04AI Tank", newtank, L4D2ZombieClassname[GetPlayerStoredClass(newtank) - 1]);
		}
	}
	else
	{
		SOLog.Events("\x05%N \x01(\x04%s\x01) \x01is going to replace \x05%N\x01's \x04Tank", newtank, L4D2ZombieClassname[view_as<int>(L4D2_GetPlayerZombieClass(newtank)) - 1], tank);
	}
}

// ====================================================================================================
// SPAWN SYSTEM INTEGRATION
// ====================================================================================================

/**
 * Handle special infected spawn assignment
 */
public void L4D_OnSpawnSpecial_Post(int client, int zombieClass, const float vecPos[3], const float vecAng[3])
{
	if (!IsClientInGame(client) || !IsClientInfected(client))
		return;
		
	// Update stored class and spawn state
	SetPlayerClass(client, zombieClass);
	g_gameState.players[client].hasSpawned = true;
	
	SOLog.Events("%N %s \x01as (\x04%s\x01)", client, isCulling ? "\x05respawned" : "\x01spawned", L4D2ZombieClassname[zombieClass - 1]);
}

/**
 * Handle director spawn attempts
 */
public Action L4D_OnSpawnSpecial(int &zombieClass, const float vecPos[3], const float vecAng[3])
{
	SOLog.Events("Director attempting to spawn (\x04%s\x01)", L4D2ZombieClassname[zombieClass - 1]);
	
	// Check if we're over the player limit
	if (GetTotalInfectedPlayers() >= z_max_player_zombies.IntValue)
	{
		SOLog.Limits("Blocking director spawn for \x03going over player limit\x01.");
		return Plugin_Handled;
	}
	
	// Get queued SI class
	g_ZombieClass = PopQueuedSI(-1);
	if (g_ZombieClass == SI_None)
	{
		SOLog.Limits("Blocking director spawn for \x04running out of available SI\x01.");
		return Plugin_Handled;
	}
	
	zombieClass = g_ZombieClass;
	SOLog.Events("Overriding director spawn to (\x04%s\x01)", L4D2ZombieClassname[g_ZombieClass - 1]);
	
	return Plugin_Changed;
}

/**
 * Handle post spawn validation
 */
public void L4D_OnSpawnSpecial_PostHandled(int client, int zombieClass, const float vecPos[3], const float vecAng[3])
{
	if (g_ZombieClass != SI_None)
	{
		SOLog.Events("Director spawned a bot (expected \x05%s\x01, got %s%s\x01)", L4D2ZombieClassname[g_ZombieClass - 1], g_ZombieClass == zombieClass ? "\x05" : "\x04", L4D2ZombieClassname[zombieClass - 1]);
		
		if (g_ZombieClass != zombieClass)
		{
			// Queue back the expected class since director spawned something else
			QueueSI(g_ZombieClass, true);
		}
		
		g_ZombieClass = SI_None;
	}
	else
	{
		SOLog.Events("Director's spawn was \x04blocked \x01(expected \x05%s\x01, got %s%s\x01)", L4D2ZombieClassname[g_ZombieClass - 1], g_ZombieClass == zombieClass ? "\x05" : "\x04", L4D2ZombieClassname[zombieClass - 1]);
	}
}

// ====================================================================================================
// UTILITY FUNCTIONS
// ====================================================================================================

/**
 * Check if a client is on the infected team
 */
bool IsClientInfected(int client)
{
	if (!IsClientInGame(client))
		return false;
	
	return L4D_GetClientTeam(client) == L4DTeam_Infected;
}
