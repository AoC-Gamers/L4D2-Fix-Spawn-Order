#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <left4dhooks>

#define DEBUG 1
#define DEBUG_QUEUE		1	// Queue operations and spawning
#define DEBUG_LIMITS	1	// Limit checking and validation
#define DEBUG_REBALANCE	1	// Rebalancing and configuration changes
#define DEBUG_EVENTS	1	// Player events and state changes

#define PLUGIN_VERSION "4.5"
#define STRING_SEPARATOR ", "
#define STRING_SACK_ORDER "[Sack Order]"

/* These class numbers are the same ones used internally in L4D2 */
#define SI_GENERIC_BEGIN 1 // L4D2Infected_Smoker  
#define SI_GENERIC_END 7   // L4D2Infected_Witch
#define SI_MAX_SIZE 10     // Total size including all classes
#define SI_None 0          // No class assigned

#define MAX_SI_ARRAY_SIZE 128
#define NUM_SI_CLASSES 6  // Smoker, Boomer, Hunter, Spitter, Jockey, Charger
#define REBALANCE_THROTTLE_TIME 2.0  // Minimum time between rebalances

// Forward constants
#define FSO_REFILL_AUTOMATIC		0	// Queue refilled automatically
#define FSO_REFILL_MANUAL			1	// Queue refilled manually  
#define FSO_REFILL_ROUND_START		2	// Queue refilled at round start
#define FSO_REFILL_EMERGENCY		3	// Queue refilled due to empty state

#define FSO_LIMIT_DOMINATOR			0	// Dominator limit type
#define FSO_LIMIT_CLASS				1	// Individual class limit type

// Global instances (will be initialized in modules)
SIConfig g_SIConfig;
GameState g_gameState;
SpawnConfig g_SpawnConfig;

// Queue and configuration
ArrayList g_SpawnsArray;

int g_Dominators;

// Bot spawning state
int g_ZombieClass;

// Ghost state tracking
bool isCulling = false;

GlobalForward
	g_fwdOnRebalanceTriggered,
	g_fwdOnQueueUpdated,
	g_fwdOnPlayerClassChanged,
	g_fwdOnQueueRefilled,
	g_fwdOnQueueEmptied,
	g_fwdOnPlayerClassForced,
	g_fwdOnLimitExceeded,
	g_fwdOnDominatorLimitHit,
	g_fwdOnClassLimitHit,
	g_fwdOnGameStateChanged,
	g_fwdOnRoundTransition,
	g_fwdOnConfigurationChanged;

ConVar 
	z_max_player_zombies;

enum OverLimitReason
{
	OverLimit_OK = 0,
	OverLimit_Dominator,
	OverLimit_Class
}

/**
 * Enumeration for different log categories
 */
enum SOLogCategory
{
	SOLog_General   = 0,	// General debug information
	SOLog_Queue     = 1,	// Queue operations and spawning
	SOLog_Limits    = 2,	// Limit checking and validation
	SOLog_Rebalance = 3,	// Rebalancing and configuration changes
	SOLog_Events    = 4		// Player events and state changes
}

/**
 * Modern logging system using methodmap for Spawn Order plugin
 * Optimized with compile-time macros to eliminate overhead in production
 */
methodmap SOLog
{
	/**
	 * Logs a formatted message to all players in chat with a category-specific prefix.
	 *
	 * @param category  The log category to determine the message prefix (SOLogCategory enum).
	 * @param message   The format string for the log message.
	 * @param ...       Additional arguments for formatting the message.
	 *
	 * The function uses SourceMod's VFormat to format the message and
	 * PrintToChatAll to display it to all players. The prefix colorizes and
	 * categorizes the message for easier identification in chat.
	 */
	public static void WriteLog(SOLogCategory category, const char[] message, any...)
	{
		static char sFormat[256];  // Optimized for SourceMod chat limit
		static char sPrefix[24];
		
		VFormat(sFormat, sizeof(sFormat), message, 3);
		
		switch (category)
		{
			case SOLog_General: strcopy(sPrefix, sizeof(sPrefix), "\x04[SO]\x01");
			case SOLog_Queue: strcopy(sPrefix, sizeof(sPrefix), "\x04[SO][Queue]\x01");
			case SOLog_Limits: strcopy(sPrefix, sizeof(sPrefix), "\x04[SO][Limits]\x01");
			case SOLog_Rebalance: strcopy(sPrefix, sizeof(sPrefix), "\x04[SO][Rebalance]\x01");
			case SOLog_Events: strcopy(sPrefix, sizeof(sPrefix), "\x04[SO][Events]\x01");
			default: strcopy(sPrefix, sizeof(sPrefix), "\x04[SO][Unknown]\x01");
		}
		
		PrintToChatAll("%s %s", sPrefix, sFormat);
	}
	

	#if DEBUG
	/**
	 * Logs a formatted debug message to the general log.
	 *
	 * @param message   The format string for the debug message.
	 * @param ...       Additional arguments to format into the message.
	 */
	public static void Debug(const char[] message, any...)
	{
		static char sFormat[256];
		VFormat(sFormat, sizeof(sFormat), message, 2);
		SOLog.WriteLog(SOLog_General, sFormat);
	}
	#else
	public static void Debug(const char[] message, any...) {}
	#endif

	#if DEBUG && DEBUG_QUEUE
	/**
	 * Formats a message using variable arguments and writes it to the spawn order log.
	 *
	 * @param message		The format string for the message.
	 * @param ...			Additional arguments to format into the message.
	 */
	public static void Queue(const char[] message, any...)
	{
		static char sFormat[256];
		VFormat(sFormat, sizeof(sFormat), message, 2);
		SOLog.WriteLog(SOLog_Queue, sFormat);
	}
	#else
	public static void Queue(const char[] message, any...) {}
	#endif

	#if DEBUG && DEBUG_LIMITS
	/**
	 * Logs a formatted message to the limits log.
	 *
	 * @param message  The format string for the message to log.
	 * @param ...      Additional arguments to format into the message.
	 */
	public static void Limits(const char[] message, any...)
	{
		static char sFormat[256];
		VFormat(sFormat, sizeof(sFormat), message, 2);
		SOLog.WriteLog(SOLog_Limits, sFormat);
	}
	#else
	public static void Limits(const char[] message, any...) {}
	#endif
	
	#if DEBUG && DEBUG_REBALANCE
	/**
	 * Rebalances the spawn order and logs the action.
	 *
	 * Formats the provided message with additional arguments and writes it to the rebalance log.
	 *
	 * @param message   The format string for the log message.
	 * @param ...       Additional arguments to format into the message.
	 */
	public static void Rebalance(const char[] message, any...)
	{
		static char sFormat[256];
		VFormat(sFormat, sizeof(sFormat), message, 2);
		SOLog.WriteLog(SOLog_Rebalance, sFormat);
	}
	#else
	public static void Rebalance(const char[] message, any...) {}
	#endif
	
	#if DEBUG && DEBUG_EVENTS
	/**
	 * Logs an event message to the SOLog_Events log.
	 *
	 * Formats the input message using variable arguments and writes it to the event log.
	 *
	 * @param message   The format string for the event message.
	 * @param ...       Variable arguments to be formatted into the message.
	 */
	public static void Events(const char[] message, any...)
	{
		static char sFormat[256];
		VFormat(sFormat, sizeof(sFormat), message, 2);
		SOLog.WriteLog(SOLog_Events, sFormat);
	}
	#else
	public static void Events(const char[] message, any...) {}
	#endif
}

#include "fix_spawn_order/fso_config.sp"
#include "fix_spawn_order/fso_queue_limits.sp" 
#include "fix_spawn_order/fso_events.sp"
#include "fix_spawn_order/fso_api.sp"

public Plugin myinfo = 
{
	name = "[L4D2] Proper Sack Order",
	author = "Sir, Forgetest, lechuga",
	description = "Finally fix that pesky spawn rotation not being reliable",
	version = PLUGIN_VERSION,
	url = "https://github.com/AoC-Gamers/L4D2-Fix-Spawn-Order"
};

public void OnPluginStart()
{
	g_SIConfig.Init();
	g_ZombieClass = SI_None;

	InitializeAPI();
	
	HookEvent("round_start", Event_RoundStart);
	HookEvent("round_end", Event_RoundEnd);
	
	HookEvent("versus_round_start", Event_RealRoundStart);
	HookEvent("scavenge_round_start", Event_RealRoundStart);
	
	HookEvent("player_death", Event_PlayerDeath);
	
	InitSpawnConfiguration();
	z_max_player_zombies = FindConVar("z_max_player_zombies");
	
	g_SpawnsArray = new ArrayList();
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	g_gameState.isLive = false;
	g_SpawnsArray.Clear();
}

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	g_gameState.isLive = false;
}

public void Event_RealRoundStart(Event event, const char[] name, bool dontBroadcast)
{
	if (!L4D_HasPlayerControlledZombies())
		return;
	
	if (g_gameState.isLive)
		return;
	
	bool wasLive = g_gameState.isLive;
	int oldRound = g_gameState.currentRound;
	
	g_gameState.isLive = true;
	g_gameState.currentRound++;
	
	FireGameStateChangedForward(wasLive, g_gameState.isLive, g_gameState.isFinale, g_gameState.isFinale); 
	FireRoundTransitionForward(oldRound, g_gameState.currentRound, g_gameState.isFinale);
	
	FillQueue();
	FireQueueRefilledForward(g_SpawnsArray.Length, FSO_REFILL_ROUND_START);
}

/**
 * Retrieves a descriptive text explaining the reason for exceeding a limit.
 *
 * @param reason    The reason code indicating why the limit was exceeded.
 * @param buffer    The buffer to store the resulting reason text.
 * @param maxlen    The maximum length of the buffer.
 *
 * The function writes a human-readable explanation to 'buffer' based on the
 * provided 'reason'. If the reason is OverLimit_OK, the buffer is set to an
 * empty string. For other reasons, a corresponding predefined string is copied
 * to the buffer. If the reason is unknown, a formatted string with the reason
 * code is used.
 */
void GetOverLimitReasonText(OverLimitReason reason, char[] buffer, int maxlen)
{
	switch (reason)
	{
		case OverLimit_OK: buffer[0] = '\0';
		case OverLimit_Dominator: strcopy(buffer, maxlen, "Dominator limit");
		case OverLimit_Class: strcopy(buffer, maxlen, "Class limit");
		default: FormatEx(buffer, maxlen, "Unknown reason (%d)", reason);
	}
}