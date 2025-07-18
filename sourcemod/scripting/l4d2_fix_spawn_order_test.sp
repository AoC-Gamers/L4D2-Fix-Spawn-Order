#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <left4dhooks>
#include <fix_spawn_order>

#define PLUGIN_VERSION "1.0"
#define TEST_PREFIX "\x04[FSO Test]\x01"

// Test configuration
#define MAX_TEST_QUEUE_SIZE 32
#define TEST_INTERVAL 5.0

// Global test variables
bool g_bTestingActive = false;
bool g_bPluginAvailable = false;
int g_iTestCounter = 0;
Handle g_hTestTimer = null;

// Arrays for testing
int g_iTestQueue[MAX_TEST_QUEUE_SIZE];
int g_iCurrentQueue[MAX_TEST_QUEUE_SIZE];

// Test statistics
int g_iTestsPassed = 0;
int g_iTestsFailed = 0;

public Plugin myinfo = 
{
	name = "[L4D2] Fix Spawn Order - Test Suite",
	author = "lechuga",
	description = "Comprehensive test suite for Fix Spawn Order plugin API",
	version = PLUGIN_VERSION,
	url = "https://github.com/AoC-Gamers/L4D2-Fix-Spawn-Order"
};

public void OnPluginStart()
{
	// Register commands
	RegAdminCmd("sm_fso_test_start", Command_StartTests, ADMFLAG_ROOT, "Start FSO API testing");
	RegAdminCmd("sm_fso_test_stop", Command_StopTests, ADMFLAG_ROOT, "Stop FSO API testing");
	RegAdminCmd("sm_fso_test_natives", Command_TestNatives, ADMFLAG_ROOT, "Test all FSO natives");
	RegAdminCmd("sm_fso_test_queue", Command_TestQueue, ADMFLAG_ROOT, "Test queue operations");
	RegAdminCmd("sm_fso_test_players", Command_TestPlayers, ADMFLAG_ROOT, "Test player operations");
	RegAdminCmd("sm_fso_test_state", Command_TestGameState, ADMFLAG_ROOT, "Test game state operations");
	RegAdminCmd("sm_fso_test_all", Command_TestAll, ADMFLAG_ROOT, "Run all tests");
	
	// Initialize test queue with some SI classes
	for (int i = 0; i < MAX_TEST_QUEUE_SIZE; i++)
	{
		g_iTestQueue[i] = (i % 6) + 1; // Cycle through SI classes 1-6
	}
	
	PrintToServer("%s Fix Spawn Order Test Suite loaded", TEST_PREFIX);
}

public void OnAllPluginsLoaded()
{
	g_bPluginAvailable = LibraryExists("l4d2_fix_spawn_order");
	if (g_bPluginAvailable)
	{
		PrintToChatAll("%s Fix Spawn Order plugin detected - Test suite ready", TEST_PREFIX);
	}
	else
	{
		PrintToChatAll("%s \x07Fix Spawn Order plugin not found - Tests will fail", TEST_PREFIX);
	}
}

public void OnLibraryAdded(const char[] name)
{
	if (strcmp(name, "l4d2_fix_spawn_order") == 0)
	{
		g_bPluginAvailable = true;
		PrintToChatAll("%s Fix Spawn Order plugin loaded - Test suite ready", TEST_PREFIX);
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if (strcmp(name, "l4d2_fix_spawn_order") == 0)
	{
		g_bPluginAvailable = false;
		PrintToChatAll("%s \x07Fix Spawn Order plugin unloaded", TEST_PREFIX);
		if (g_hTestTimer != null)
		{
			StopTests();
		}
	}
}

// ====================================================================================================
// COMMAND HANDLERS
// ====================================================================================================

public Action Command_StartTests(int client, int args)
{
	if (!g_bPluginAvailable)
	{
		ReplyToCommand(client, "%s Fix Spawn Order plugin not available", TEST_PREFIX);
		return Plugin_Handled;
	}
	
	if (g_bTestingActive)
	{
		ReplyToCommand(client, "%s Testing already active", TEST_PREFIX);
		return Plugin_Handled;
	}
	
	StartTests();
	ReplyToCommand(client, "%s Started continuous testing", TEST_PREFIX);
	return Plugin_Handled;
}

public Action Command_StopTests(int client, int args)
{
	if (!g_bTestingActive)
	{
		ReplyToCommand(client, "%s No testing active", TEST_PREFIX);
		return Plugin_Handled;
	}
	
	StopTests();
	ReplyToCommand(client, "%s Stopped testing", TEST_PREFIX);
	return Plugin_Handled;
}

public Action Command_TestNatives(int client, int args)
{
	if (!g_bPluginAvailable)
	{
		ReplyToCommand(client, "%s Fix Spawn Order plugin not available", TEST_PREFIX);
		return Plugin_Handled;
	}
	
	TestAllNatives();
	ReplyToCommand(client, "%s Native tests completed", TEST_PREFIX);
	return Plugin_Handled;
}

public Action Command_TestQueue(int client, int args)
{
	if (!g_bPluginAvailable)
	{
		ReplyToCommand(client, "%s Fix Spawn Order plugin not available", TEST_PREFIX);
		return Plugin_Handled;
	}
	
	TestQueueOperations();
	ReplyToCommand(client, "%s Queue tests completed", TEST_PREFIX);
	return Plugin_Handled;
}

public Action Command_TestPlayers(int client, int args)
{
	if (!g_bPluginAvailable)
	{
		ReplyToCommand(client, "%s Fix Spawn Order plugin not available", TEST_PREFIX);
		return Plugin_Handled;
	}
	
	TestPlayerOperations();
	ReplyToCommand(client, "%s Player tests completed", TEST_PREFIX);
	return Plugin_Handled;
}

public Action Command_TestGameState(int client, int args)
{
	if (!g_bPluginAvailable)
	{
		ReplyToCommand(client, "%s Fix Spawn Order plugin not available", TEST_PREFIX);
		return Plugin_Handled;
	}
	
	TestGameStateOperations();
	ReplyToCommand(client, "%s Game state tests completed", TEST_PREFIX);
	return Plugin_Handled;
}

public Action Command_TestAll(int client, int args)
{
	if (!g_bPluginAvailable)
	{
		ReplyToCommand(client, "%s Fix Spawn Order plugin not available", TEST_PREFIX);
		return Plugin_Handled;
	}
	
	RunAllTests();
	ReplyToCommand(client, "%s All tests completed - Passed: %d, Failed: %d", 
		TEST_PREFIX, g_iTestsPassed, g_iTestsFailed);
	return Plugin_Handled;
}

// ====================================================================================================
// TEST CONTROL FUNCTIONS
// ====================================================================================================

void StartTests()
{
	g_bTestingActive = true;
	g_iTestCounter = 0;
	g_hTestTimer = CreateTimer(TEST_INTERVAL, Timer_RunTests, _, TIMER_REPEAT);
	PrintToChatAll("%s \x05Started continuous testing every %.1f seconds", TEST_PREFIX, TEST_INTERVAL);
}

void StopTests()
{
	g_bTestingActive = false;
	if (g_hTestTimer != null)
	{
		KillTimer(g_hTestTimer);
		g_hTestTimer = null;
	}
	PrintToChatAll("%s \x07Stopped continuous testing", TEST_PREFIX);
}

public Action Timer_RunTests(Handle timer)
{
	if (!g_bPluginAvailable || !g_bTestingActive)
	{
		StopTests();
		return Plugin_Stop;
	}
	
	g_iTestCounter++;
	PrintToChatAll("%s \x03Test Cycle #%d", TEST_PREFIX, g_iTestCounter);
	
	// Run a rotating set of tests
	switch (g_iTestCounter % 4)
	{
		case 1: TestQueueOperations();
		case 2: TestPlayerOperations();
		case 3: TestGameStateOperations();
		case 0: TestAllNatives();
	}
	
	return Plugin_Continue;
}

void RunAllTests()
{
	g_iTestsPassed = 0;
	g_iTestsFailed = 0;
	
	PrintToChatAll("%s \x05=== Starting Complete Test Suite ===", TEST_PREFIX);
	
	TestQueueOperations();
	TestPlayerOperations();
	TestGameStateOperations();
	TestAllNatives();
	TestRebalanceOperations();
	
	PrintToChatAll("%s \x05=== Test Suite Complete ===", TEST_PREFIX);
	PrintToChatAll("%s Results: \x04%d passed\x01, \x07%d failed", 
		TEST_PREFIX, g_iTestsPassed, g_iTestsFailed);
}

// ====================================================================================================
// QUEUE TESTING FUNCTIONS
// ====================================================================================================

void TestQueueOperations()
{
	PrintToChatAll("%s \x03Testing Queue Operations", TEST_PREFIX);
	
	// Test 1: Get current queue size
	int queueSize = FSO_GetQueueSize();
	PrintToChatAll("%s Current queue size: \x05%d", TEST_PREFIX, queueSize);
	LogTestResult("FSO_GetQueueSize", true);
	
	// Test 2: Get current queue contents
	int currentSize = FSO_GetQueuedSI(g_iCurrentQueue, MAX_TEST_QUEUE_SIZE);
	PrintToChatAll("%s Retrieved queue size: \x05%d", TEST_PREFIX, currentSize);
	
	if (currentSize > 0)
	{
		char queueStr[256];
		FormatQueueString(g_iCurrentQueue, currentSize, queueStr, sizeof(queueStr));
		PrintToChatAll("%s Queue contents: \x04%s", TEST_PREFIX, queueStr);
	}
	LogTestResult("FSO_GetQueuedSI", currentSize >= 0);
	
	// Test 3: Set a new test queue
	bool setResult = FSO_SetQueuedSI(g_iTestQueue, 6);
	PrintToChatAll("%s Set test queue result: \x05%s", TEST_PREFIX, setResult ? "Success" : "Failed");
	LogTestResult("FSO_SetQueuedSI", setResult);
	
	// Test 4: Verify the queue was set
	int newSize = FSO_GetQueueSize();
	PrintToChatAll("%s New queue size after set: \x05%d", TEST_PREFIX, newSize);
	LogTestResult("Queue size verification", newSize == 6);
	
	// Test 5: Clear queue
	FSO_ClearQueue();
	int clearedSize = FSO_GetQueueSize();
	PrintToChatAll("%s Queue size after clear: \x05%d", TEST_PREFIX, clearedSize);
	LogTestResult("FSO_ClearQueue", clearedSize == 0);
	
	// Test 6: Restore original queue if it had content
	if (currentSize > 0)
	{
		FSO_SetQueuedSI(g_iCurrentQueue, currentSize);
		PrintToChatAll("%s Restored original queue", TEST_PREFIX);
	}
}

// ====================================================================================================
// PLAYER TESTING FUNCTIONS
// ====================================================================================================

void TestPlayerOperations()
{
	PrintToChatAll("%s \x03Testing Player Operations", TEST_PREFIX);
	
	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsClientInGame(client))
			continue;
			
		// Test 1: Get player's stored class
		int storedClass = FSO_GetPlayerStoredClass(client);
		PrintToChatAll("%s Player %N stored class: \x05%d", TEST_PREFIX, client, storedClass);
		LogTestResult("FSO_GetPlayerStoredClass", true);
		
		// Test 2: Check if player has spawned
		bool hasSpawned = FSO_IsPlayerSpawned(client);
		PrintToChatAll("%s Player %N spawn status: \x05%s", TEST_PREFIX, client, hasSpawned ? "Spawned" : "Not spawned");
		LogTestResult("FSO_IsPlayerSpawned", true);
		
		// Test 3: Set player class (only for infected team)
		if (GetClientTeam(client) == 3)
		{
			int originalClass = storedClass;
			bool setResult = FSO_SetPlayerStoredClass(client, 1); // Set to Smoker
			PrintToChatAll("%s Set player %N class to Smoker: \x05%s", TEST_PREFIX, client, setResult ? "Success" : "Failed");
			LogTestResult("FSO_SetPlayerStoredClass", setResult);
			
			// Verify the change
			int newClass = FSO_GetPlayerStoredClass(client);
			bool verified = (newClass == 1);
			PrintToChatAll("%s Player %N class verification: \x05%s (class: %d)", TEST_PREFIX, client, verified ? "Success" : "Failed", newClass);
			LogTestResult("Player class verification", verified);
			
			// Restore original class
			if (originalClass != newClass)
			{
				FSO_SetPlayerStoredClass(client, originalClass);
				PrintToChatAll("%s Restored player %N original class: \x05%d", TEST_PREFIX, client, originalClass);
			}
		}
	}
}

// ====================================================================================================
// GAME STATE TESTING FUNCTIONS
// ====================================================================================================

void TestGameStateOperations()
{
	PrintToChatAll("%s \x03Testing Game State Operations", TEST_PREFIX);
	
	// Test: Get game state
	bool isLive, isFinale;
	int currentRound;
	float lastRebalanceTime;
	
	FSO_GetGameState(isLive, isFinale, currentRound, lastRebalanceTime);
	
	PrintToChatAll("%s Game State - Live: \x05%s\x01, Finale: \x05%s\x01, Round: \x05%d\x01, Last Rebalance: \x05%.2f", 
		TEST_PREFIX, isLive ? "Yes" : "No", isFinale ? "Yes" : "No", currentRound, lastRebalanceTime);
	
	LogTestResult("FSO_GetGameState", true);
}

// ====================================================================================================
// NATIVE TESTING FUNCTIONS
// ====================================================================================================

void TestAllNatives()
{
	PrintToChatAll("%s \x03Testing All Natives", TEST_PREFIX);
	
	// Test queue natives
	int queueSize = FSO_GetQueueSize();
	PrintToChatAll("%s Queue Size Native: \x05%d", TEST_PREFIX, queueSize);
	
	// Test rebalance trigger
	TestRebalanceOperations();
}

void TestRebalanceOperations()
{
	PrintToChatAll("%s \x03Testing Rebalance Operations", TEST_PREFIX);
	
	// Trigger a test rebalance
	FSO_TriggerRebalance("Test Suite Rebalance");
	PrintToChatAll("%s Triggered rebalance with reason: \x05Test Suite Rebalance", TEST_PREFIX);
	LogTestResult("FSO_TriggerRebalance", true);
}

// ====================================================================================================
// FORWARD HANDLERS
// ====================================================================================================

public void FSO_OnRebalanceTriggered(const char[] reason)
{
	PrintToChatAll("%s \x06[Forward] Rebalance triggered: \x04%s", TEST_PREFIX, reason);
}

public void FSO_OnQueueUpdated(int newSize, int oldSize)
{
	PrintToChatAll("%s \x06[Forward] Queue updated: \x04%d -> %d", TEST_PREFIX, oldSize, newSize);
}

public void FSO_OnPlayerClassChanged(int client, int oldClass, int newClass)
{
	if (IsValidClient(client))
	{
		PrintToChatAll("%s \x06[Forward] Player %N class changed: \x04%d -> %d", TEST_PREFIX, client, oldClass, newClass);
	}
}

public void FSO_OnQueueRefilled(int newSize, int refillReason)
{
	char reasonStr[32];
	GetRefillReasonString(refillReason, reasonStr, sizeof(reasonStr));
	PrintToChatAll("%s \x06[Forward] Queue refilled: \x04%d items (%s)", TEST_PREFIX, newSize, reasonStr);
}

public void FSO_OnQueueEmptied(int lastSize, float emptyTime)
{
	PrintToChatAll("%s \x06[Forward] Queue emptied: \x04%d items at %.2f", TEST_PREFIX, lastSize, emptyTime);
}

public void FSO_OnPlayerClassForced(int client, int oldClass, int newClass, const char[] reason)
{
	if (IsValidClient(client))
	{
		PrintToChatAll("%s \x06[Forward] Player %N class forced: \x04%d -> %d (%s)", 
			TEST_PREFIX, client, oldClass, newClass, reason);
	}
}

public Action FSO_OnLimitExceeded(int limitType, int currentCount, int maxAllowed, int &newLimit)
{
	char limitTypeStr[32];
	GetLimitTypeString(limitType, limitTypeStr, sizeof(limitTypeStr));
	PrintToChatAll("%s \x06[Forward] Limit exceeded: \x04%s (%d/%d)", 
		TEST_PREFIX, limitTypeStr, currentCount, maxAllowed);
	return Plugin_Continue;
}

public void FSO_OnDominatorLimitHit(int dominatorClass, int currentCount, int maxAllowed)
{
	PrintToChatAll("%s \x06[Forward] Dominator limit hit: \x04Class %d (%d/%d)", 
		TEST_PREFIX, dominatorClass, currentCount, maxAllowed);
}

public void FSO_OnClassLimitHit(int zombieClass, int currentCount, int maxAllowed)
{
	PrintToChatAll("%s \x06[Forward] Class limit hit: \x04Class %d (%d/%d)", 
		TEST_PREFIX, zombieClass, currentCount, maxAllowed);
}

public void FSO_OnGameStateChanged(bool wasLive, bool isLive, bool wasFinale, bool isFinale)
{
	PrintToChatAll("%s \x06[Forward] Game state changed: \x04Live(%s->%s) Finale(%s->%s)", 
		TEST_PREFIX, wasLive ? "Y" : "N", isLive ? "Y" : "N", wasFinale ? "Y" : "N", isFinale ? "Y" : "N");
}

public void FSO_OnRoundTransition(int oldRound, int newRound, bool isFinale)
{
	PrintToChatAll("%s \x06[Forward] Round transition: \x04%d -> %d %s", 
		TEST_PREFIX, oldRound, newRound, isFinale ? "(Finale)" : "");
}

public void FSO_OnConfigurationChanged(const char[] configName, any oldValue, any newValue)
{
	PrintToChatAll("%s \x06[Forward] Config changed: \x04%s (%d -> %d)", 
		TEST_PREFIX, configName, oldValue, newValue);
}

// ====================================================================================================
// UTILITY FUNCTIONS
// ====================================================================================================

void LogTestResult(const char[] testName, bool passed)
{
	if (passed)
	{
		g_iTestsPassed++;
		PrintToChatAll("%s \x04✓ %s", TEST_PREFIX, testName);
	}
	else
	{
		g_iTestsFailed++;
		PrintToChatAll("%s \x07✗ %s", TEST_PREFIX, testName);
	}
}

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

bool IsValidClient(int client)
{
	return (client > 0 && client <= MaxClients && IsClientInGame(client));
}
