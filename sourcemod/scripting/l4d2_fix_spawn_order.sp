#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <left4dhooks>
#include <colors>

#define DEBUG 0
#define DEBUG_QUEUE		0	// Queue operations and spawning
#define DEBUG_LIMITS	0	// Limit checking and validation
#define DEBUG_REBALANCE	0	// Rebalancing and configuration changes
#define DEBUG_EVENTS	0	// Player events and state changes
#define DEBUG_LOG_FILE	"logs/FixSpawnOrder.log"

#define PLUGIN_VERSION "4.5"
#define STRING_SEPARATOR ", "
#define STRING_SACK_ORDER "[Sack Order]"
#define FSO_PREFIX "[{olive}FSO{default}]"

/* These class numbers are the same ones used internally in L4D2 */
#define SI_GENERIC_BEGIN 1 // L4D2Infected_Smoker  
#define SI_GENERIC_END 7   // L4D2Infected_Witch
#define SI_MAX_SIZE 10     // Total size including all classes
#define SI_None 0          // No class assigned

#define MAX_SI_ARRAY_SIZE 128
#define NUM_SI_CLASSES 6  // Smoker, Boomer, Hunter, Spitter, Jockey, Charger
#define REBALANCE_THROTTLE_TIME 2.0  // Minimum time between rebalances
#define MIN_QUEUE_SIZE 2  // Minimum queue size for proper rotation
#define DEFAULT_TEAM_SIZE 4  // Default infected team size

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

// Safe area tracking for bot spawn control
bool g_bSurvivorsLeftSafeArea = false;

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

char g_sLogPath[PLATFORM_MAX_PATH];

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
	 * CPrintToChatAll to display it to all players with colors. The prefix colorizes and
	 * categorizes the message for easier identification in chat.
	 */
	public static void WriteLog(SOLogCategory category, const char[] message, any...)
	{
		static char sFormat[256];  // Optimized for SourceMod chat limit
		static char sPrefix[64];   // Increased size for colored prefix
		
		VFormat(sFormat, sizeof(sFormat), message, 3);
		
		switch (category)
		{
			case SOLog_General: 
				strcopy(sPrefix, sizeof(sPrefix), FSO_PREFIX);
			case SOLog_Queue: 
				Format(sPrefix, sizeof(sPrefix), "%s[{blue}Queue{default}]", FSO_PREFIX);
			case SOLog_Limits: 
				Format(sPrefix, sizeof(sPrefix), "%s[{red}Limits{default}]", FSO_PREFIX);
			case SOLog_Rebalance: 
				Format(sPrefix, sizeof(sPrefix), "%s[{orange}Rebalance{default}]", FSO_PREFIX);
			case SOLog_Events: 
				Format(sPrefix, sizeof(sPrefix), "%s[{lightgreen}Events{default}]", FSO_PREFIX);
			default: 
				Format(sPrefix, sizeof(sPrefix), "%s[{red}Unknown{default}]", FSO_PREFIX);
		}
		
		char sColoredMessage[512];
		Format(sColoredMessage, sizeof(sColoredMessage), "%s %s", sPrefix, sFormat);
		
		CPrintToChatAll("%s", sColoredMessage);
		CRemoveTags(sColoredMessage, sizeof(sColoredMessage));
		LogToFileEx(g_sLogPath, "%s", sColoredMessage);
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
	public static void Debug(const char[] message, any...) {
		#pragma unused message
	}
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
	public static void Queue(const char[] message, any...) {
		#pragma unused message
	}
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
	public static void Limits(const char[] message, any...) {
		#pragma unused message
	}
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
	public static void Rebalance(const char[] message, any...) {
		#pragma unused message
	}
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
	public static void Events(const char[] message, any...) {
		#pragma unused message
	}
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

public APLRes AskPluginLoad2(Handle hMyself, bool bLate, char[] sError, int iErr_max)
{
	RegisterNatives();
	RegisterForwards();
	RegPluginLibrary("l4d2_fix_spawn_order");
	return APLRes_Success;
}

public void OnPluginStart()
{
	BuildPath(Path_SM, g_sLogPath, sizeof(g_sLogPath), DEBUG_LOG_FILE);
	g_SIConfig.Init();
	InitSpawnConfiguration();
	
	g_SpawnsArray = new ArrayList();
	g_ZombieClass = SI_None;
	
	HookEvent("round_start", Event_RoundStart);
	HookEvent("round_end", Event_RoundEnd);
	
	HookEvent("versus_round_start", Event_RealRoundStart);
	HookEvent("scavenge_round_start", Event_RealRoundStart);
	
	HookEvent("player_death", Event_PlayerDeath);
	
	z_max_player_zombies = FindConVar("z_max_player_zombies");
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	g_gameState.isLive = false;
	g_SpawnsArray.Clear();
	g_bSurvivorsLeftSafeArea = false; // Reset safe area status
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
	
	// Check if survivors have already left safe area (in case of late plugin load)
	g_bSurvivorsLeftSafeArea = L4D_HasAnySurvivorLeftSafeArea();
	
	FillQueue();
	FireQueueRefilledForward(g_SpawnsArray.Length, FSO_REFILL_ROUND_START);
	
	SOLog.Events("Round started - Survivors left safe area: {olive}%s{default}", g_bSurvivorsLeftSafeArea ? "Yes" : "No");
}

/**
 * Called when the first survivor leaves the safe area
 * This triggers bot spawning to begin
 */
public void L4D_OnFirstSurvivorLeftSafeArea_Post(int client)
{
	if (!g_gameState.isLive)
		return;
	
	g_bSurvivorsLeftSafeArea = true;
	
	SOLog.Events("First survivor {olive}%N{default} left safe area - Bot spawning now enabled", client);
	
	// Fire our custom forward to notify other plugins
	if (g_fwdOnGameStateChanged != null)
	{
		Call_StartForward(g_fwdOnGameStateChanged);
		Call_PushCell(false); // wasLive - doesn't change
		Call_PushCell(true);  // isLive - doesn't change  
		Call_PushCell(false); // wasFinale - doesn't change
		Call_PushCell(g_gameState.isFinale); // isFinale - doesn't change
		Call_Finish();
	}
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
		default: FormatEx(buffer, maxlen, "Unknown reason ({olive}%d{default})", reason);
	}
}

// ====================================================================================================
// SAFE ZOMBIE CLASS NAME UTILITY
// ====================================================================================================

/**
 * Get zombie class name safely, handling invalid indices
 */
stock void GetSafeZombieClassName(int zombieClass, char[] buffer, int maxlen)
{
	if (zombieClass == SI_None)
	{
		strcopy(buffer, maxlen, "None");
		return;
	}
	
	if (zombieClass < g_SIConfig.genericBegin || zombieClass >= g_SIConfig.genericEnd)
	{
		FormatEx(buffer, maxlen, "Invalid({olive}%d{default})", zombieClass);
		return;
	}
	
	strcopy(buffer, maxlen, L4D2ZombieClassname[zombieClass - 1]);
}

// ====================================================================================================
// UTILITY FUNCTIONS
// ====================================================================================================


/**
 * Checks if the given client index is valid.
 *
 * @param iClient      The client index to validate.
 * @return             True if the client index is greater than 0 and less than or equal to MaxClients, false otherwise.
 */
bool IsValidClientIndex(int iClient)
{
	return (iClient > 0 && iClient <= MaxClients);
}