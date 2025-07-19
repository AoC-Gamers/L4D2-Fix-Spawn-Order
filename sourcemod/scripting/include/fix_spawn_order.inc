#if defined _fix_spawn_order_included
	#endinput
#endif
#define _fix_spawn_order_included

/**
 * Fix Spawn Order API Include File
 * 
 * This file contains all the natives and forwards available in the Fix Spawn Order plugin.
 * Include this file in your plugin to access the FSO API.
 */

// ====================================================================================================
// CONSTANTS
// ====================================================================================================

#define FSO_REFILL_AUTOMATIC		0	// Queue refilled automatically
#define FSO_REFILL_MANUAL			1	// Queue refilled manually
#define FSO_REFILL_ROUND_START		2	// Queue refilled at round start
#define FSO_REFILL_EMERGENCY		3	// Queue refilled due to empty state

#define FSO_LIMIT_DOMINATOR			0	// Dominator limit type
#define FSO_LIMIT_CLASS				1	// Individual class limit type

// ====================================================================================================
// NATIVES
// ====================================================================================================

/**
 * Get the current queued SI array
 * 
 * @param buffer		Array to store the queue
 * @param maxsize		Maximum size of the buffer
 * @return				Actual queue size
 */
native int FSO_GetQueuedSI(int[] buffer, int maxsize);

/**
 * Set the queued SI array
 * 
 * @param queue			Array containing the new queue
 * @param size			Size of the queue array
 * @return				True on success, false on failure
 */
native bool FSO_SetQueuedSI(const int[] queue, int size);

/**
 * Get player's stored class
 * 
 * @param client		Client index
 * @return				Zombie class or SI_None
 */
native int FSO_GetPlayerStoredClass(int client);

/**
 * Set player's stored class
 * 
 * @param client		Client index
 * @param zombieClass	Zombie class to assign
 * @return				True on success, false on failure
 */
native bool FSO_SetPlayerStoredClass(int client, int zombieClass);

/**
 * Check if player has spawned in current round
 * 
 * @param client		Client index
 * @return				True if spawned, false otherwise
 */
native bool FSO_IsPlayerSpawned(int client);

/**
 * Get current queue size
 * 
 * @return				Number of items in queue
 */
native int FSO_GetQueueSize();

/**
 * Clear the entire queue
 */
native void FSO_ClearQueue();

/**
 * Trigger a rebalance of the spawn system
 * 
 * @param reason		Reason for the rebalance
 */
native void FSO_TriggerRebalance(const char[] reason);

/**
 * Get current game state information
 * 
 * @param isLive			Reference to store live state
 * @param isFinale			Reference to store finale state
 * @param currentRound		Reference to store current round
 * @param lastRebalanceTime	Reference to store last rebalance time
 */
native void FSO_GetGameState(bool &isLive, bool &isFinale, int &currentRound, float &lastRebalanceTime);

// ====================================================================================================
// FORWARDS
// ====================================================================================================

/**
 * Called when a rebalance is triggered
 * 
 * @param reason		Reason for the rebalance
 */
forward void FSO_OnRebalanceTriggered(const char[] reason);

/**
 * Called when the queue is updated
 * 
 * @param newSize		New queue size
 * @param oldSize		Previous queue size
 */
forward void FSO_OnQueueUpdated(int newSize, int oldSize);

/**
 * Called when a player's class changes
 * 
 * @param client		Client index
 * @param oldClass		Previous zombie class
 * @param newClass		New zombie class
 */
forward void FSO_OnPlayerClassChanged(int client, int oldClass, int newClass);

/**
 * Called when the queue is refilled
 * 
 * @param newSize		New queue size after refill
 * @param refillReason	Reason for refill (FSO_REFILL_* constants)
 */
forward void FSO_OnQueueRefilled(int newSize, int refillReason);

/**
 * Called when the queue becomes empty
 * 
 * @param lastSize		Size before becoming empty
 * @param emptyTime		Time when queue became empty
 */
forward void FSO_OnQueueEmptied(int lastSize, float emptyTime);

/**
 * Called when system forces a player class change
 * 
 * @param client		Client index
 * @param oldClass		Previous zombie class
 * @param newClass		New zombie class
 * @param reason		Reason for forced change
 */
forward void FSO_OnPlayerClassForced(int client, int oldClass, int newClass, const char[] reason);

/**
 * Called when a limit is about to be exceeded (hookable)
 * 
 * @param limitType		Type of limit (FSO_LIMIT_* constants)
 * @param currentCount	Current count of the limited item
 * @param maxAllowed	Maximum allowed count
 * @param newLimit		Reference to modify the limit (by reference)
 * @return				Plugin_Continue to allow, Plugin_Handled to block
 */
forward Action FSO_OnLimitExceeded(int limitType, int currentCount, int maxAllowed, int &newLimit);

/**
 * Called when dominator limit is hit
 * 
 * @param dominatorClass	Dominator class that hit the limit
 * @param currentCount		Current count of dominators
 * @param maxAllowed		Maximum allowed dominators
 */
forward void FSO_OnDominatorLimitHit(int dominatorClass, int currentCount, int maxAllowed);

/**
 * Called when a specific class limit is hit
 * 
 * @param zombieClass		Zombie class that hit the limit
 * @param currentCount		Current count of this class
 * @param maxAllowed		Maximum allowed for this class
 */
forward void FSO_OnClassLimitHit(int zombieClass, int currentCount, int maxAllowed);

/**
 * Called when game state changes
 * 
 * @param wasLive		Previous live state
 * @param isLive		Current live state
 * @param wasFinale		Previous finale state
 * @param isFinale		Current finale state
 */
forward void FSO_OnGameStateChanged(bool wasLive, bool isLive, bool wasFinale, bool isFinale);

/**
 * Called during round transitions
 * 
 * @param oldRound		Previous round number
 * @param newRound		New round number
 * @param isFinale		Whether new round is finale
 */
forward void FSO_OnRoundTransition(int oldRound, int newRound, bool isFinale);

/**
 * Called when system configuration changes
 * 
 * @param configName	Name of the configuration that changed
 * @param oldValue		Previous value
 * @param newValue		New value
 */
forward void FSO_OnConfigurationChanged(const char[] configName, any oldValue, any newValue);

// ====================================================================================================
// PLUGIN INFORMATION
// ====================================================================================================

public SharedPlugin __pl_fix_spawn_order = 
{
	name = "l4d2_fix_spawn_order",
	file = "l4d2_fix_spawn_order.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_fix_spawn_order_SetNTVOptional()
{
	MarkNativeAsOptional("FSO_GetQueuedSI");
	MarkNativeAsOptional("FSO_SetQueuedSI");
	MarkNativeAsOptional("FSO_GetPlayerStoredClass");
	MarkNativeAsOptional("FSO_SetPlayerStoredClass");
	MarkNativeAsOptional("FSO_IsPlayerSpawned");
	MarkNativeAsOptional("FSO_GetQueueSize");
	MarkNativeAsOptional("FSO_ClearQueue");
	MarkNativeAsOptional("FSO_TriggerRebalance");
	MarkNativeAsOptional("FSO_GetGameState");
}
#endif
