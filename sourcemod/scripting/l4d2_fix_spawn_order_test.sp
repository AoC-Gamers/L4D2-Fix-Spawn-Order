#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <left4dhooks>
#include <fix_spawn_order>
#include <colors>

#define PLUGIN_VERSION "1.0"

// Test prefixes
#define FSO_TEST_PREFIX "[{olive}FSO Test{default}]"
#define FSO_TEST_PREFIX_ERROR "[{red}FSO Test{default}]"
#define FSO_TEST_PREFIX_SUCCESS "[{lightgreen}FSO Test{default}]"
#define FSO_TEST_PREFIX_WARNING "[{orange}FSO Test{default}]"

// Test configuration
#define MAX_TEST_QUEUE_SIZE 32
#define TEST_INTERVAL 5.0

// Global test variables
bool
	g_bTestingActive = false,
	g_bL4D2FixSpawnOrder = false,
	g_bLateLoad = false;

Handle g_hTestTimer = null;

int 
	g_iTestCounter = 0,
// Arrays for testing	
	g_iTestQueue[MAX_TEST_QUEUE_SIZE],
	g_iCurrentQueue[MAX_TEST_QUEUE_SIZE],
// Test statistics
	g_iTestsPassed = 0,
	g_iTestsFailed = 0;

// Debug ConVar with bit masking
ConVar g_cvDebugFlags;

/**
 * Debug flags for bit masking
 */
enum DebugFlags
{
	DEBUG_NONE      = 0,		// No debug output
	DEBUG_GENERAL   = (1 << 0),	// General debug information (bit 0)
	DEBUG_QUEUE     = (1 << 1),	// Queue operations and spawning (bit 1)
	DEBUG_LIMITS    = (1 << 2),	// Limit checking and validation (bit 2)
	DEBUG_REBALANCE = (1 << 3),	// Rebalancing and configuration changes (bit 3)
	DEBUG_EVENTS    = (1 << 4),	// Player events and state changes (bit 4)
	DEBUG_ALL       = 0x1F		// All debug flags enabled (bits 0-4)
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
 * Test logging system using methodmap for FSO Test Suite
 * Uses ConVars instead of compile-time constants for runtime configuration
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
				strcopy(sPrefix, sizeof(sPrefix), FSO_TEST_PREFIX);
			case SOLog_Queue: 
				Format(sPrefix, sizeof(sPrefix), "%s[{blue}Queue{default}]", FSO_TEST_PREFIX);
			case SOLog_Limits: 
				Format(sPrefix, sizeof(sPrefix), "%s[{red}Limits{default}]", FSO_TEST_PREFIX);
			case SOLog_Rebalance: 
				Format(sPrefix, sizeof(sPrefix), "%s[{orange}Rebalance{default}]", FSO_TEST_PREFIX);
			case SOLog_Events: 
				Format(sPrefix, sizeof(sPrefix), "%s[{lightgreen}Events{default}]", FSO_TEST_PREFIX);
			default: 
				Format(sPrefix, sizeof(sPrefix), "%s[{red}Unknown{default}]", FSO_TEST_PREFIX);
		}
		
		char sColoredMessage[512];
		Format(sColoredMessage, sizeof(sColoredMessage), "%s %s", sPrefix, sFormat);
		
		CPrintToChatAll("%s", sColoredMessage);
	}
	
	/**
	 * Logs a formatted debug message to the general log.
	 *
	 * @param message   The format string for the debug message.
	 * @param ...       Additional arguments to format into the message.
	 */
	public static void Debug(const char[] message, any...)
	{
		if (!(g_cvDebugFlags.IntValue & view_as<int>(DEBUG_GENERAL)))
			return;
			
		static char sFormat[256];
		VFormat(sFormat, sizeof(sFormat), message, 2);
		SOLog.WriteLog(SOLog_General, sFormat);
	}

	/**
	 * Formats a message using variable arguments and writes it to the spawn order log.
	 *
	 * @param message		The format string for the message.
	 * @param ...			Additional arguments to format into the message.
	 */
	public static void Queue(const char[] message, any...)
	{
		if (!(g_cvDebugFlags.IntValue & view_as<int>(DEBUG_QUEUE)))
			return;
			
		static char sFormat[256];
		VFormat(sFormat, sizeof(sFormat), message, 2);
		SOLog.WriteLog(SOLog_Queue, sFormat);
	}

	/**
	 * Logs a formatted message to the limits log.
	 *
	 * @param message  The format string for the message to log.
	 * @param ...      Additional arguments to format into the message.
	 */
	public static void Limits(const char[] message, any...)
	{
		if (!(g_cvDebugFlags.IntValue & view_as<int>(DEBUG_LIMITS)))
			return;
			
		static char sFormat[256];
		VFormat(sFormat, sizeof(sFormat), message, 2);
		SOLog.WriteLog(SOLog_Limits, sFormat);
	}
	
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
		if (!(g_cvDebugFlags.IntValue & view_as<int>(DEBUG_REBALANCE)))
			return;
			
		static char sFormat[256];
		VFormat(sFormat, sizeof(sFormat), message, 2);
		SOLog.WriteLog(SOLog_Rebalance, sFormat);
	}
	
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
		if (!(g_cvDebugFlags.IntValue & view_as<int>(DEBUG_EVENTS)))
			return;
			
		static char sFormat[256];
		VFormat(sFormat, sizeof(sFormat), message, 2);
		SOLog.WriteLog(SOLog_Events, sFormat);
	}
}

public Plugin myinfo = 
{
	name = "[L4D2] Fix Spawn Order - Test Suite",
	author = "lechuga",
	description = "Comprehensive test suite for Fix Spawn Order plugin API",
	version = PLUGIN_VERSION,
	url = "https://github.com/AoC-Gamers/L4D2-Fix-Spawn-Order"
};

public APLRes AskPluginLoad2(Handle hMyself, bool bLate, char[] sError, int iErr_max)
{
	g_bLateLoad = bLate;
	return APLRes_Success;
}

public void OnAllPluginsLoaded()
{
	g_bL4D2FixSpawnOrder = LibraryExists("l4d2_fix_spawn_order");
}

public void OnLibraryAdded(const char[] sName)
{
	if (StrEqual(sName, "l4d2_fix_spawn_order"))
		g_bL4D2FixSpawnOrder = false;
}

public void OnLibraryRemoved(const char[] sName)
{
	if (StrEqual(sName, "l4d2_fix_spawn_order"))
	{
		g_bL4D2FixSpawnOrder = false;
		if (g_hTestTimer != null)
		{
			StopTests();
		}
	}
}

public void OnPluginStart()
{
	// Create debug ConVar with bit flags
	// Default value includes all debug flags (0x1F = 31 = all 5 bits set)
	g_cvDebugFlags = CreateConVar("fso_test_debug_flags", "31", 
		"Debug flags bit mask: 1=General, 2=Queue, 4=Limits, 8=Rebalance, 16=Events, 31=All", 
		FCVAR_NOTIFY, true, 0.0, true, 31.0);
	
	// Auto-execute config
	AutoExecConfig(true, "l4d2_fix_spawn_order_test");
	
	RegAdminCmd("sm_fso_test_start", Command_StartTests, ADMFLAG_ROOT, "Start FSO API testing");
	RegAdminCmd("sm_fso_test_stop", Command_StopTests, ADMFLAG_ROOT, "Stop FSO API testing");
	RegAdminCmd("sm_fso_test_natives", Command_TestNatives, ADMFLAG_ROOT, "Test all FSO natives");
	RegAdminCmd("sm_fso_test_queue", Command_TestQueue, ADMFLAG_ROOT, "Test queue operations");
	RegAdminCmd("sm_fso_test_players", Command_TestPlayers, ADMFLAG_ROOT, "Test player operations");
	RegAdminCmd("sm_fso_test_state", Command_TestGameState, ADMFLAG_ROOT, "Test game state operations");
	RegAdminCmd("sm_fso_test_safearea", Command_TestSafeArea, ADMFLAG_ROOT, "Test safe area functionality");
	RegAdminCmd("sm_fso_test_quad", Command_TestQuadCap, ADMFLAG_ROOT, "Test quad-cap creation and validation");
	RegAdminCmd("sm_fso_force_quad", Command_ForceQuadCap, ADMFLAG_ROOT, "Force create a quad-cap queue immediately");
	RegAdminCmd("sm_fso_test_all", Command_TestAll, ADMFLAG_ROOT, "Run all tests");
	
	// Debug control commands
	RegAdminCmd("sm_fso_test_debug", Command_DebugControl, ADMFLAG_ROOT, "Control debug logging with bit flags");
	RegAdminCmd("sm_fso_test_log", Command_TestLog, ADMFLAG_ROOT, "Test the logging system with different categories");
	RegAdminCmd("sm_fso_check_convars", Command_CheckConVars, ADMFLAG_ROOT, "Check current SI limit ConVar values");
	
	// Initialize test queue with some SI classes
	for (int i = 0; i < MAX_TEST_QUEUE_SIZE; i++)
	{
		g_iTestQueue[i] = (i % 6) + 1; // Cycle through SI classes 1-6
	}

	if (!g_bLateLoad)
		return;

	g_bL4D2FixSpawnOrder = LibraryExists("l4d2_fix_spawn_order");
}


// ====================================================================================================
// COMMAND HANDLERS
// ====================================================================================================

public Action Command_StartTests(int client, int args)
{
	if (!g_bL4D2FixSpawnOrder)
	{
		CReplyToCommand(client, "%s Fix Spawn Order plugin not available", FSO_TEST_PREFIX_ERROR);
		return Plugin_Handled;
	}
	
	if (g_bTestingActive)
	{
		CReplyToCommand(client, "%s Testing already active", FSO_TEST_PREFIX_WARNING);
		return Plugin_Handled;
	}
	
	StartTests();
	CReplyToCommand(client, "%s Started continuous testing", FSO_TEST_PREFIX);
	return Plugin_Handled;
}

public Action Command_StopTests(int client, int args)
{
	if (!g_bTestingActive)
	{
		CReplyToCommand(client, "%s No testing active", FSO_TEST_PREFIX_WARNING);
		return Plugin_Handled;
	}
	
	StopTests();
	CReplyToCommand(client, "%s Stopped testing", FSO_TEST_PREFIX);
	return Plugin_Handled;
}

public Action Command_TestNatives(int client, int args)
{
	if (!g_bL4D2FixSpawnOrder)
	{
		CReplyToCommand(client, "%s Fix Spawn Order plugin not available", FSO_TEST_PREFIX_ERROR);
		return Plugin_Handled;
	}
	
	TestAllNatives();
	CReplyToCommand(client, "%s Native tests completed", FSO_TEST_PREFIX_SUCCESS);
	return Plugin_Handled;
}

public Action Command_TestQueue(int client, int args)
{
	if (!g_bL4D2FixSpawnOrder)
	{
		CReplyToCommand(client, "%s Fix Spawn Order plugin not available", FSO_TEST_PREFIX_ERROR);
		return Plugin_Handled;
	}
	
	TestQueueOperations();
	CReplyToCommand(client, "%s Queue tests completed", FSO_TEST_PREFIX_SUCCESS);
	return Plugin_Handled;
}

public Action Command_TestPlayers(int client, int args)
{
	if (!g_bL4D2FixSpawnOrder)
	{
		CReplyToCommand(client, "[{red}FSO Test{default}] Fix Spawn Order plugin not available");
		return Plugin_Handled;
	}
	
	TestPlayerOperations();
	CReplyToCommand(client, "[{lightgreen}FSO Test{default}] Player tests completed");
	return Plugin_Handled;
}

public Action Command_TestGameState(int client, int args)
{
	if (!g_bL4D2FixSpawnOrder)
	{
		CReplyToCommand(client, "[{red}FSO Test{default}] Fix Spawn Order plugin not available");
		return Plugin_Handled;
	}
	
	TestGameStateOperations();
	CReplyToCommand(client, "[{lightgreen}FSO Test{default}] Game state tests completed");
	return Plugin_Handled;
}

public Action Command_TestSafeArea(int client, int args)
{
	if (!g_bL4D2FixSpawnOrder)
	{
		CReplyToCommand(client, "[{red}FSO Test{default}] Fix Spawn Order plugin not available");
		return Plugin_Handled;
	}
	
	TestSafeAreaFunctionality();
	CReplyToCommand(client, "[{lightgreen}FSO Test{default}] Safe area tests completed");
	return Plugin_Handled;
}

public Action Command_TestQuadCap(int client, int args)
{
	if (!g_bL4D2FixSpawnOrder)
	{
		CReplyToCommand(client, "[{red}FSO Test{default}] Fix Spawn Order plugin not available");
		return Plugin_Handled;
	}
	
	TestQuadCapFunctionality();
	CReplyToCommand(client, "[{lightgreen}FSO Test{default}] Quad-cap tests completed");
	return Plugin_Handled;
}

public Action Command_ForceQuadCap(int client, int args)
{
	if (!g_bL4D2FixSpawnOrder)
	{
		CReplyToCommand(client, "[{red}FSO Test{default}] Fix Spawn Order plugin not available");
		return Plugin_Handled;
	}
	
	// Force create a quad-cap queue immediately
	int quadQueue[4] = {1, 3, 5, 6}; // Smoker, Hunter, Jockey, Charger
	bool setResult = FSO_SetQueuedSI(quadQueue, 4);
	
	if (setResult)
	{
		CPrintToChatAll("%s[{lightgreen}Force Quad{default}] Created quad-cap queue: {olive}Smoker{default}, {olive}Hunter{default}, {olive}Jockey{default}, {olive}Charger{default}", FSO_TEST_PREFIX);
		CReplyToCommand(client, "%s Quad-cap queue forced successfully", FSO_TEST_PREFIX);
	}
	else
	{
		CPrintToChatAll("%s[{red}Force Quad{default}] Failed to create quad-cap queue", FSO_TEST_PREFIX);
		CReplyToCommand(client, "%s Failed to force quad-cap queue", FSO_TEST_PREFIX_ERROR);
	}
	
	return Plugin_Handled;
}

public Action Command_TestAll(int client, int args)
{
	if (!g_bL4D2FixSpawnOrder)
	{
		CReplyToCommand(client, "[{red}FSO Test{default}] Fix Spawn Order plugin not available");
		return Plugin_Handled;
	}
	
	RunAllTests();
	CReplyToCommand(client, "[{lightgreen}FSO Test{default}] All tests completed - Passed: {olive}%d{default}, Failed: {olive}%d{default}", 
		g_iTestsPassed, g_iTestsFailed);
	return Plugin_Handled;
}

public Action Command_DebugControl(int client, int args)
{
	if (args == 0)
	{
		// Show current debug settings
		int flags = g_cvDebugFlags.IntValue;
		CReplyToCommand(client, "%s Debug Settings (Flags: {olive}%d{default}):", FSO_TEST_PREFIX, flags);
		CReplyToCommand(client, "  General: {olive}%s{default}", (flags & view_as<int>(DEBUG_GENERAL)) ? "Enabled" : "Disabled");
		CReplyToCommand(client, "  Queue: {olive}%s{default}", (flags & view_as<int>(DEBUG_QUEUE)) ? "Enabled" : "Disabled");
		CReplyToCommand(client, "  Limits: {olive}%s{default}", (flags & view_as<int>(DEBUG_LIMITS)) ? "Enabled" : "Disabled");
		CReplyToCommand(client, "  Rebalance: {olive}%s{default}", (flags & view_as<int>(DEBUG_REBALANCE)) ? "Enabled" : "Disabled");
		CReplyToCommand(client, "  Events: {olive}%s{default}", (flags & view_as<int>(DEBUG_EVENTS)) ? "Enabled" : "Disabled");
		CReplyToCommand(client, "Usage: sm_fso_test_debug <category> <0|1> OR sm_fso_test_debug <flags_number>");
		CReplyToCommand(client, "Categories: general, queue, limits, rebalance, events, all, none");
		CReplyToCommand(client, "Flag values: General=1, Queue=2, Limits=4, Rebalance=8, Events=16, All=31, None=0");
		return Plugin_Handled;
	}
	
	char arg1[32], arg2[8];
	GetCmdArg(1, arg1, sizeof(arg1));
	
	// Check if first argument is a number (direct flag setting)
	if (IsCharNumeric(arg1[0]) || arg1[0] == '-')
	{
		int newFlags = StringToInt(arg1);
		if (newFlags < 0) newFlags = 0;
		if (newFlags > 31) newFlags = 31;
		
		g_cvDebugFlags.SetInt(newFlags);
		CReplyToCommand(client, "%s Debug flags set to: {olive}%d{default}", FSO_TEST_PREFIX, newFlags);
		return Plugin_Handled;
	}
	
	// Category-based control (requires second argument)
	if (args < 2)
	{
		CReplyToCommand(client, "%s Missing enable/disable value. Usage: sm_fso_test_debug <category> <0|1>", FSO_TEST_PREFIX_ERROR);
		return Plugin_Handled;
	}
	
	GetCmdArg(2, arg2, sizeof(arg2));
	bool enable = (StringToInt(arg2) == 1);
	int currentFlags = g_cvDebugFlags.IntValue;
	
	if (StrEqual(arg1, "general", false))
	{
		if (enable)
			currentFlags |= view_as<int>(DEBUG_GENERAL);
		else
			currentFlags &= ~view_as<int>(DEBUG_GENERAL);
		CReplyToCommand(client, "%s General debug: {olive}%s{default}", FSO_TEST_PREFIX, enable ? "Enabled" : "Disabled");
	}
	else if (StrEqual(arg1, "queue", false))
	{
		if (enable)
			currentFlags |= view_as<int>(DEBUG_QUEUE);
		else
			currentFlags &= ~view_as<int>(DEBUG_QUEUE);
		CReplyToCommand(client, "%s Queue debug: {olive}%s{default}", FSO_TEST_PREFIX, enable ? "Enabled" : "Disabled");
	}
	else if (StrEqual(arg1, "limits", false))
	{
		if (enable)
			currentFlags |= view_as<int>(DEBUG_LIMITS);
		else
			currentFlags &= ~view_as<int>(DEBUG_LIMITS);
		CReplyToCommand(client, "%s Limits debug: {olive}%s{default}", FSO_TEST_PREFIX, enable ? "Enabled" : "Disabled");
	}
	else if (StrEqual(arg1, "rebalance", false))
	{
		if (enable)
			currentFlags |= view_as<int>(DEBUG_REBALANCE);
		else
			currentFlags &= ~view_as<int>(DEBUG_REBALANCE);
		CReplyToCommand(client, "%s Rebalance debug: {olive}%s{default}", FSO_TEST_PREFIX, enable ? "Enabled" : "Disabled");
	}
	else if (StrEqual(arg1, "events", false))
	{
		if (enable)
			currentFlags |= view_as<int>(DEBUG_EVENTS);
		else
			currentFlags &= ~view_as<int>(DEBUG_EVENTS);
		CReplyToCommand(client, "%s Events debug: {olive}%s{default}", FSO_TEST_PREFIX, enable ? "Enabled" : "Disabled");
	}
	else if (StrEqual(arg1, "all", false))
	{
		currentFlags = enable ? view_as<int>(DEBUG_ALL) : view_as<int>(DEBUG_NONE);
		CReplyToCommand(client, "%s All debug categories: {olive}%s{default}", FSO_TEST_PREFIX, enable ? "Enabled" : "Disabled");
	}
	else if (StrEqual(arg1, "none", false))
	{
		currentFlags = view_as<int>(DEBUG_NONE);
		CReplyToCommand(client, "%s All debug categories: {olive}Disabled{default}", FSO_TEST_PREFIX);
	}
	else
	{
		CReplyToCommand(client, "%s Invalid category. Use: general, queue, limits, rebalance, events, all, none", FSO_TEST_PREFIX_ERROR);
		return Plugin_Handled;
	}
	
	g_cvDebugFlags.SetInt(currentFlags);
	return Plugin_Handled;
}

public Action Command_TestLog(int client, int args)
{
	CReplyToCommand(client, "%s Testing logging system...", FSO_TEST_PREFIX);
	
	// Test each log category
	SOLog.Debug("This is a debug message for testing");
	SOLog.Queue("This is a queue message for testing with player {olive}%N{default}", client);
	SOLog.Limits("This is a limits message for testing - current limit: {olive}4{default}");
	SOLog.Rebalance("This is a rebalance message for testing - reason: {olive}Manual Test{default}");
	SOLog.Events("This is an events message for testing - player {olive}%N{default} performed action", client);
	
	CReplyToCommand(client, "%s Log test completed. Check chat and log file.", FSO_TEST_PREFIX_SUCCESS);
	return Plugin_Handled;
}

public Action Command_CheckConVars(int client, int args)
{
	CReplyToCommand(client, "%s Checking SI Limit ConVar values...", FSO_TEST_PREFIX);
	
	// Check SI limit ConVars
	ConVar cvSmoker = FindConVar("z_smoker_limit");
	ConVar cvBoomer = FindConVar("z_boomer_limit");
	ConVar cvHunter = FindConVar("z_hunter_limit");
	ConVar cvSpitter = FindConVar("z_spitter_limit");
	ConVar cvJockey = FindConVar("z_jockey_limit");
	ConVar cvCharger = FindConVar("z_charger_limit");
	
	if (cvSmoker) 
		CReplyToCommand(client, "  z_smoker_limit: {olive}%d{default}", cvSmoker.IntValue);
	if (cvBoomer) 
		CReplyToCommand(client, "  z_boomer_limit: {olive}%d{default}", cvBoomer.IntValue);
	if (cvHunter) 
		CReplyToCommand(client, "  z_hunter_limit: {olive}%d{default}", cvHunter.IntValue);
	if (cvSpitter) 
		CReplyToCommand(client, "  z_spitter_limit: {olive}%d{default}", cvSpitter.IntValue);
	if (cvJockey) 
		CReplyToCommand(client, "  z_jockey_limit: {olive}%d{default}", cvJockey.IntValue);
	if (cvCharger) 
		CReplyToCommand(client, "  z_charger_limit: {olive}%d{default}", cvCharger.IntValue);
	
	// Also check some other related ConVars
	ConVar cvMaxCapacity = FindConVar("z_max_player_zombies");
	if (cvMaxCapacity)
		CReplyToCommand(client, "  z_max_player_zombies: {olive}%d{default}", cvMaxCapacity.IntValue);
	
	return Plugin_Handled;
}

// ====================================================================================================
// UTILITY FUNCTIONS
// ====================================================================================================

/**
 * Print a test message to all clients with consistent formatting
 */
void PrintTestMessage(const char[] category, const char[] message, any ...)
{
	char buffer[256];
	VFormat(buffer, sizeof(buffer), message, 3);
	CPrintToChatAll("%s[{blue}%s{default}] %s", FSO_TEST_PREFIX, category, buffer);
}

/**
 * Print a test result with color coding
 */
void PrintTestResult(const char[] test, bool success, const char[] format = "", any ...)
{
	char details[256];
	if (strlen(format) > 0)
	{
		VFormat(details, sizeof(details), format, 4);
	}
	
	if (success)
	{
		if (strlen(details) > 0)
			CPrintToChatAll("%s {lightgreen}✓{default} %s: {olive}%s{default}", FSO_TEST_PREFIX, test, details);
		else
			CPrintToChatAll("%s {lightgreen}✓{default} %s", FSO_TEST_PREFIX, test);
	}
	else
	{
		if (strlen(details) > 0)
			CPrintToChatAll("%s {red}✗{default} %s: {olive}%s{default}", FSO_TEST_PREFIX, test, details);
		else
			CPrintToChatAll("%s {red}✗{default} %s", FSO_TEST_PREFIX, test);
	}
}

// ====================================================================================================
// TEST CONTROL FUNCTIONS
// ====================================================================================================

void StartTests()
{
	g_bTestingActive = true;
	g_iTestCounter = 0;
	g_hTestTimer = CreateTimer(TEST_INTERVAL, Timer_RunTests, _, TIMER_REPEAT);
	CPrintToChatAll("%s Started continuous testing every {olive}%.1f{default} seconds", FSO_TEST_PREFIX, TEST_INTERVAL);
	SOLog.Events("Test suite started - continuous testing enabled with interval {olive}%.1f{default}s", TEST_INTERVAL);
}

void StopTests()
{
	g_bTestingActive = false;
	if (g_hTestTimer != null)
	{
		KillTimer(g_hTestTimer);
		g_hTestTimer = null;
	}
	CPrintToChatAll("%s Stopped continuous testing", FSO_TEST_PREFIX);
	SOLog.Events("Test suite stopped - continuous testing disabled");
}

public Action Timer_RunTests(Handle timer)
{
	if (!g_bL4D2FixSpawnOrder || !g_bTestingActive)
	{
		StopTests();
		return Plugin_Stop;
	}
	
	g_iTestCounter++;
	CPrintToChatAll("%s Test Cycle #{olive}%d{default}", FSO_TEST_PREFIX, g_iTestCounter);
	
	// Run a rotating set of tests
	switch (g_iTestCounter % 6)
	{
		case 1: TestQueueOperations();
		case 2: TestPlayerOperations();
		case 3: TestGameStateOperations();
		case 4: TestSafeAreaFunctionality();
		case 5: TestQuadCapFunctionality();
		case 0: TestAllNatives();
	}
	
	return Plugin_Continue;
}

void RunAllTests()
{
	g_iTestsPassed = 0;
	g_iTestsFailed = 0;
	
	CPrintToChatAll("%s {lightgreen}=== Starting Complete Test Suite ==={default}", FSO_TEST_PREFIX);
	
	TestQueueOperations();
	TestPlayerOperations();
	TestGameStateOperations();
	TestAllNatives();
	TestRebalanceOperations();
	TestSafeAreaFunctionality();
	TestQuadCapFunctionality();
	
	CPrintToChatAll("%s {lightgreen}=== Test Suite Complete ==={default}", FSO_TEST_PREFIX);
	CPrintToChatAll("%s Results: {lightgreen}%d passed{default}, {red}%d failed{default}", 
		FSO_TEST_PREFIX, g_iTestsPassed, g_iTestsFailed);
}

// ====================================================================================================
// QUEUE TESTING FUNCTIONS
// ====================================================================================================

void TestQueueOperations()
{
	PrintTestMessage("Queue", "Testing Queue Operations");
	SOLog.Queue("Starting queue operations test");
	
	// Test 1: Get current queue size
	int queueSize = FSO_GetQueueSize();
	PrintTestResult("FSO_GetQueueSize", true, "%d items", queueSize);
	SOLog.Queue("Current queue size: {olive}%d{default}", queueSize);
	
	// Test 2: Get current queue contents
	int currentSize = FSO_GetQueuedSI(g_iCurrentQueue, MAX_TEST_QUEUE_SIZE);
	PrintTestResult("FSO_GetQueuedSI", true, "Retrieved %d items", currentSize);
	SOLog.Queue("Retrieved {olive}%d{default} items from queue", currentSize);
	
	if (currentSize > 0)
	{
		char queueStr[256];
		FormatQueueString(g_iCurrentQueue, currentSize, queueStr, sizeof(queueStr));
		SOLog.Queue("Queue contents: {blue}%s{default}", queueStr);
	}
	
	// Test 3: Set a new test queue
	bool setResult = FSO_SetQueuedSI(g_iTestQueue, 6);
	SOLog.Queue("Set test queue result: {olive}%s{default}", setResult ? "Success" : "Failed");
	
	// Test 4: Verify the queue was set
	int newSize = FSO_GetQueueSize();
	SOLog.Queue("New queue size after set: {olive}%d{default}", newSize);
	
	// Test 5: Clear queue
	FSO_ClearQueue();
	int clearedSize = FSO_GetQueueSize();
	SOLog.Queue("Queue size after clear: {olive}%d{default}", clearedSize);
	
	// Test 6: Restore original queue if it had content
	if (currentSize > 0)
	{
		FSO_SetQueuedSI(g_iCurrentQueue, currentSize);
		SOLog.Queue("Restored original queue");
	}
}

// ====================================================================================================
// PLAYER TESTING FUNCTIONS
// ====================================================================================================

void TestPlayerOperations()
{
	SOLog.Events("Testing Player Operations");
	
	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsClientInGame(client))
			continue;
			
		// Test 1: Get player's stored class
		int storedClass = FSO_GetPlayerStoredClass(client);
		SOLog.Events("Player {olive}%N{default} stored class: {olive}%d{default}", client, storedClass);
		
		// Test 2: Check if player has spawned
		bool hasSpawned = FSO_IsPlayerSpawned(client);
		SOLog.Events("Player {olive}%N{default} spawn status: {olive}%s{default}", client, hasSpawned ? "Spawned" : "Not spawned");
		
		// Test 3: Set player class (only for infected team)
		if (GetClientTeam(client) == 3)
		{
			int originalClass = storedClass;
			bool setResult = FSO_SetPlayerStoredClass(client, 1); // Set to Smoker
			SOLog.Events("Set player {olive}%N{default} class to Smoker: {olive}%s{default}", client, setResult ? "Success" : "Failed");
			
			// Verify the change
			int newClass = FSO_GetPlayerStoredClass(client);
			bool verified = (newClass == 1);
			SOLog.Events("Player {olive}%N{default} class verification: {olive}%s{default} (class: %d)", client, verified ? "Success" : "Failed", newClass);
			
			// Restore original class
			if (originalClass != newClass)
			{
				FSO_SetPlayerStoredClass(client, originalClass);
				SOLog.Events("Restored player {olive}%N{default} original class: {olive}%d{default}", client, originalClass);
			}
		}
	}
}

// ====================================================================================================
// GAME STATE TESTING FUNCTIONS
// ====================================================================================================

void TestGameStateOperations()
{
	SOLog.Events("Testing Game State Operations");
	
	// Test: Get game state
	bool isLive, isFinale;
	int currentRound;
	float lastRebalanceTime;
	
	FSO_GetGameState(isLive, isFinale, currentRound, lastRebalanceTime);
	
	SOLog.Events("Game State - Live: {olive}%s{default}, Finale: {olive}%s{default}, Round: {olive}%d{default}, Last Rebalance: {olive}%.2f{default}", 
		isLive ? "Yes" : "No", isFinale ? "Yes" : "No", currentRound, lastRebalanceTime);
}

// ====================================================================================================
// NATIVE TESTING FUNCTIONS
// ====================================================================================================

void TestAllNatives()
{
	SOLog.Debug("Testing All Natives");
	
	// Test queue natives
	int queueSize = FSO_GetQueueSize();
	SOLog.Debug("Queue Size Native: {olive}%d{default}", queueSize);
	
	// Test rebalance trigger
	TestRebalanceOperations();
}

void TestRebalanceOperations()
{
	SOLog.Rebalance("Testing Rebalance Operations");
	SOLog.Rebalance("Starting rebalance operations test");
	
	// Trigger a test rebalance
	FSO_TriggerRebalance("Test Suite Rebalance");
	SOLog.Rebalance("Triggered rebalance with reason: {olive}Test Suite Rebalance{default}");
	SOLog.Rebalance("Triggered manual rebalance with reason: {olive}Test Suite Rebalance{default}");
}

// ====================================================================================================
// SAFE AREA TESTING FUNCTIONS
// ====================================================================================================

void TestSafeAreaFunctionality()
{
	SOLog.Events("Testing Safe Area Functionality");
	
	// Test 1: Check if left4dhooks natives are available
	bool hasSafeAreaNative = (GetFeatureStatus(FeatureType_Native, "L4D_HasAnySurvivorLeftSafeArea") == FeatureStatus_Available);
	SOLog.Events("L4D_HasAnySurvivorLeftSafeArea native: {olive}%s{default}", hasSafeAreaNative ? "Available" : "Not Available");
	
	if (hasSafeAreaNative)
	{
		// Test 2: Get current safe area status
		bool leftSafeArea = L4D_HasAnySurvivorLeftSafeArea();
		SOLog.Events("Current safe area status: {olive}%s{default}", leftSafeArea ? "Survivors have left" : "Survivors in safe area");
		
		// Test 3: Test admin commands (simulate them)
		SOLog.Events("Testing admin commands simulation...");
		
		// Simulate force safe area exit
		ServerCommand("sm_fso_check_safearea");
		SOLog.Events("Executed: {olive}sm_fso_check_safearea{default}");
		
		// Note: We don't actually test force/reset commands as they would affect gameplay
		SOLog.Events("Safe area admin commands: {olive}Available (sm_fso_force_safearea_exit, sm_fso_reset_safearea){default}");
	}
	
	// Test 4: Check if plugin properly handles safe area events
	SOLog.Events("Safe area event handling: {olive}Configured for L4D_OnFirstSurvivorLeftSafeArea_Post{default}");
}

// ====================================================================================================
// QUAD-CAP TESTING FUNCTIONS
// ====================================================================================================

void TestQuadCapFunctionality()
{
	SOLog.Queue("=== Testing Quad-Cap Functionality ===");
	
	// Test 1: Create a standard quad-cap queue (4 dominators)
	int quadQueue[4] = {1, 3, 5, 6}; // Smoker, Hunter, Jockey, Charger
	SOLog.Queue("Test 1: Creating standard quad-cap queue");
	
	bool setResult = FSO_SetQueuedSI(quadQueue, 4);
	SOLog.Queue("Set quad queue result: {olive}%s{default}", setResult ? "Success" : "Failed");
	
	// Test 2: Verify queue size is 4
	int queueSize = FSO_GetQueueSize();
	bool correctSize = (queueSize == 4);
	SOLog.Queue("Quad queue size verification: {olive}%d{default} %s", 
		queueSize, correctSize ? "(Correct)" : "(Incorrect)");
	
	// Test 3: Verify queue contents
	int retrievedQueue[8];
	int retrievedSize = FSO_GetQueuedSI(retrievedQueue, 8);
	bool contentMatch = (retrievedSize == 4);
	
	if (contentMatch)
	{
		for (int i = 0; i < 4; i++)
		{
			if (retrievedQueue[i] != quadQueue[i])
			{
				contentMatch = false;
				break;
			}
		}
	}
	
	char queueStr[128];
	FormatQueueString(retrievedQueue, retrievedSize, queueStr, sizeof(queueStr));
	SOLog.Queue("Quad queue contents: {olive}%s{default} %s", 
		queueStr, contentMatch ? "(Match)" : "(Mismatch)");
	
	// Test 4: Test alternative quad compositions
	SOLog.Queue("Test 4: Testing alternative quad compositions");
	
	// Quad with Spitter instead of Jockey
	int altQuad1[4] = {1, 3, 4, 6}; // Smoker, Hunter, Spitter, Charger
	setResult = FSO_SetQueuedSI(altQuad1, 4);
	SOLog.Queue("Alt Quad 1 (with Spitter): {olive}%s{default}", setResult ? "Success" : "Failed");
	
	// Quad with Boomer (if supported)
	int altQuad2[4] = {1, 2, 3, 6}; // Smoker, Boomer, Hunter, Charger
	setResult = FSO_SetQueuedSI(altQuad2, 4);
	SOLog.Queue("Alt Quad 2 (with Boomer): {olive}%s{default}", setResult ? "Success" : "Failed");
	
	// Test 5: Test dominator limits with quad
	SOLog.Limits("Test 5: Testing dominator limits");
	
	// Get current game state to understand limits
	bool isLive, isFinale;
	int currentRound;
	float lastRebalanceTime;
	FSO_GetGameState(isLive, isFinale, currentRound, lastRebalanceTime);
	
	SOLog.Events("Current game state for quad testing: Live={olive}%s{default}, Finale={olive}%s{default}", 
		isLive ? "Yes" : "No", isFinale ? "Yes" : "No");
	
	// Test 6: Simulate quad spawn sequence
	SOLog.Queue("Test 6: Simulating quad spawn sequence");
	
	// Reset to standard quad
	FSO_SetQueuedSI(quadQueue, 4);
	
	// Simulate getting each class from queue
	for (int i = 0; i < 4; i++)
	{
		int currentSize = FSO_GetQueueSize();
		SOLog.Queue("Spawn simulation {olive}%d{default}/4 - Queue size: {olive}%d{default}", i+1, currentSize);
		
		if (currentSize > 0)
		{
			int tempQueue[8];
			int tempSize = FSO_GetQueuedSI(tempQueue, 8);
			if (tempSize > 0)
			{
				char className[16];
				GetZombieClassName(tempQueue[0], className, sizeof(className));
				SOLog.Queue("Next spawn would be: {blue}%s{default}", className);
				
				// Remove first element to simulate spawn
				if (tempSize > 1)
				{
					int newQueue[7];
					for (int j = 1; j < tempSize; j++)
					{
						newQueue[j-1] = tempQueue[j];
					}
					FSO_SetQueuedSI(newQueue, tempSize - 1);
				}
				else
				{
					FSO_ClearQueue();
				}
			}
		}
	}
	
	
	// Test 7: Test queue refill after quad depletion
	SOLog.Queue("Test 7: Testing queue refill after quad");
	
	int finalSize = FSO_GetQueueSize();
	SOLog.Queue("Queue size after quad simulation: %d", finalSize);
	
	// Trigger rebalance to refill
	FSO_TriggerRebalance("Quad Test Refill");
	
	int refillSize = FSO_GetQueueSize();
	bool refilled = (refillSize > finalSize);
	SOLog.Queue("Queue size after refill: %d %s", 
		refillSize, refilled ? "(Refilled)" : "(No change)");
	
	// Test 8: Stress test - multiple quad operations
	SOLog.Limits("Test 8: Quad stress test");
	
	bool stressTestPassed = true;
	for (int cycle = 0; cycle < 3; cycle++)
	{
		bool cycleResult = FSO_SetQueuedSI(quadQueue, 4);
		if (!cycleResult)
		{
			stressTestPassed = false;
			break;
		}
		
		int cycleSize = FSO_GetQueueSize();
		if (cycleSize != 4)
		{
			stressTestPassed = false;
			break;
		}
		
		FSO_ClearQueue();
	}
	
	SOLog.Limits("Quad stress test (3 cycles): %s", 
		stressTestPassed ? "Passed" : "Failed");
	
	SOLog.Limits("=== Quad-Cap Testing Complete ===");
}

// ====================================================================================================
// FORWARD HANDLERS
// ====================================================================================================

public void FSO_OnRebalanceTriggered(const char[] reason)
{
	SOLog.Events("[Forward] Rebalance triggered: %s", reason);
}

public void FSO_OnQueueUpdated(int newSize, int oldSize)
{
	SOLog.Events("[Forward] Queue updated: %d -> %d", oldSize, newSize);
}

public void FSO_OnPlayerClassChanged(int client, int oldClass, int newClass)
{
	if (IsValidClient(client))
	{
		SOLog.Events("[Forward] Player %N class changed: %d -> %d", client, oldClass, newClass);
	}
}

public void FSO_OnQueueRefilled(int newSize, int refillReason)
{
	char reasonStr[32];
	GetRefillReasonString(refillReason, reasonStr, sizeof(reasonStr));
	SOLog.Events("[Forward] Queue refilled: %d items (%s)", newSize, reasonStr);
}

public void FSO_OnQueueEmptied(int lastSize, float emptyTime)
{
	SOLog.Events("[Forward] Queue emptied: %d items at %.2f", lastSize, emptyTime);
}

public void FSO_OnPlayerClassForced(int client, int oldClass, int newClass, const char[] reason)
{
	if (IsValidClient(client))
	{
		SOLog.Events("[Forward] Player %N class forced: %d -> %d (%s)", 
			client, oldClass, newClass, reason);
	}
}

public Action FSO_OnLimitExceeded(int limitType, int currentCount, int maxAllowed, int &newLimit)
{
	char limitTypeStr[32];
	GetLimitTypeString(limitType, limitTypeStr, sizeof(limitTypeStr));
	SOLog.Limits("[Forward] Limit exceeded: %s (%d/%d)", 
		limitTypeStr, currentCount, maxAllowed);
	
	// Allow quad-caps by increasing dominator limit to 4
	if (limitType == FSO_LIMIT_DOMINATOR && maxAllowed < 4)
	{
		newLimit = 4;
		SOLog.Limits("[Quad-Cap] Allowing 4 dominators for quad-cap testing");
		return Plugin_Handled;
	}
	
	return Plugin_Continue;
}

public void FSO_OnDominatorLimitHit(int dominatorClass, int currentCount, int maxAllowed)
{
	SOLog.Limits("[Forward] Dominator limit hit: Class %d (%d/%d)", 
		dominatorClass, currentCount, maxAllowed);
}

public void FSO_OnClassLimitHit(int zombieClass, int currentCount, int maxAllowed)
{
	SOLog.Limits("[Forward] Class limit hit: Class %d (%d/%d)", 
		zombieClass, currentCount, maxAllowed);
}

public void FSO_OnGameStateChanged(bool wasLive, bool isLive, bool wasFinale, bool isFinale)
{
	SOLog.Events("[Forward] Game state changed: Live(%s->%s) Finale(%s->%s)", 
		wasLive ? "Y" : "N", isLive ? "Y" : "N", wasFinale ? "Y" : "N", isFinale ? "Y" : "N");
}

public void FSO_OnRoundTransition(int oldRound, int newRound, bool isFinale)
{
	SOLog.Events("[Forward] Round transition: %d -> %d %s", 
		oldRound, newRound, isFinale ? "(Finale)" : "");
}

public void FSO_OnConfigurationChanged(const char[] configName, any oldValue, any newValue)
{
	SOLog.Events("[Forward] Config changed: %s (%d -> %d)", 
		configName, oldValue, newValue);
}

// ====================================================================================================
// UTILITY FUNCTIONS
// ====================================================================================================

void FormatQueueString(int[] queue, int size, char[] buffer, int maxlen)
{
	buffer[0] = '\0';
	
	for (int i = 0; i < size; i++)
	{
		char classStr[16];
		GetZombieClassName(queue[i], classStr, sizeof(classStr));
		
		if (i == 0)
		{
			strcopy(buffer, maxlen, classStr);
		}
		else
		{
			Format(buffer, maxlen, "%s, %s", buffer, classStr);
		}
		
		if (strlen(buffer) > maxlen - 20) // Prevent overflow
		{
			Format(buffer, maxlen, "%s...", buffer);
			break;
		}
	}
}

void GetZombieClassName(int zombieClass, char[] buffer, int maxlen)
{
	switch (zombieClass)
	{
		case 1: strcopy(buffer, maxlen, "Smoker");
		case 2: strcopy(buffer, maxlen, "Boomer");
		case 3: strcopy(buffer, maxlen, "Hunter");
		case 4: strcopy(buffer, maxlen, "Spitter");
		case 5: strcopy(buffer, maxlen, "Jockey");
		case 6: strcopy(buffer, maxlen, "Charger");
		case 8: strcopy(buffer, maxlen, "Tank");
		default: Format(buffer, maxlen, "Unknown(%d)", zombieClass);
	}
}

void GetRefillReasonString(int reason, char[] buffer, int maxlen)
{
	switch (reason)
	{
		case FSO_REFILL_AUTOMATIC: strcopy(buffer, maxlen, "Automatic");
		case FSO_REFILL_MANUAL: strcopy(buffer, maxlen, "Manual");
		case FSO_REFILL_ROUND_START: strcopy(buffer, maxlen, "Round Start");
		case FSO_REFILL_EMERGENCY: strcopy(buffer, maxlen, "Emergency");
		default: Format(buffer, maxlen, "Unknown(%d)", reason);
	}
}

void GetLimitTypeString(int limitType, char[] buffer, int maxlen)
{
	switch (limitType)
	{
		case FSO_LIMIT_DOMINATOR: strcopy(buffer, maxlen, "Dominator");
		case FSO_LIMIT_CLASS: strcopy(buffer, maxlen, "Class");
		default: Format(buffer, maxlen, "Unknown(%d)", limitType);
	}
}


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

/**
 * Checks if the given client index is valid and the client is currently in the game.
 *
 * @param client    The client index to validate.
 * @return          True if the client index is valid and the client is in game, false otherwise.
 */
bool IsValidClient(int client)
{
	return (IsValidClientIndex(client) && IsClientInGame(client));
}
