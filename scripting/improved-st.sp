#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <clientprefs>
#include <output_info_plugin>

#define PLUGIN_NAME "Show Triggers (Brushes) Redux Redux"
#define PLUGIN_AUTHOR "JoinedSenses, edited by Blank, further edited by jessetooler"
#define PLUGIN_DESCRIPTION "Toggle brush visibility with search functionality"
#define PLUGIN_VERSION "0.3.0"
#define PLUGIN_URL "http://github.com/JoinedSenses"

#define EF_NODRAW 32

public Plugin myinfo =
{
    name = PLUGIN_NAME,
    author = PLUGIN_AUTHOR,
    description = PLUGIN_DESCRIPTION,
    version = PLUGIN_VERSION,
    url = PLUGIN_URL
}

#define ENABLE_ALL                -2
#define DISABLE_ALL               -1
#define TRIGGER_MULTIPLE           0
#define TRIGGER_PUSH               1
#define TRIGGER_TELEPORT           2
#define TRIGGER_TELEPORT_RELATIVE  3
#define MAX_TYPES                  4

static const char g_NAMES[][] =
{
    "trigger_multiple",
    "trigger_push",
    "trigger_teleport",
    "trigger_teleport_relative"
};

// Which brush types does the player have enabled?
bool g_bTypeEnabled[MAXPLAYERS+1][MAX_TYPES];
// Offset for brush effects
int g_iOffsetMFEffects = -1;
// Store visibility state for individual triggers
bool g_bTriggerEnabled[2049][MAXPLAYERS+1];

// Main menu
Menu g_Menu;

// Array to store search results
ArrayList g_SearchResults;

// Color-related global variables
int g_Colors[MAXPLAYERS+1][MAX_TYPES][3];
int g_ColorsSpecial[MAXPLAYERS+1][3][3];
Handle g_ColorCookie[MAX_TYPES];
Handle g_ColorCookieSpecial[3];

public void OnPluginStart()
{
    g_iOffsetMFEffects = FindSendPropInfo("CBaseEntity", "m_fEffects");
    if (g_iOffsetMFEffects == -1)
    {
        SetFailState("[Show Triggers] Could not find CBaseEntity:m_fEffects");
    }

    CreateConVar("sm_showtriggers_version", PLUGIN_VERSION, PLUGIN_DESCRIPTION, FCVAR_SPONLY|FCVAR_NOTIFY|FCVAR_DONTRECORD).SetString(PLUGIN_VERSION);

    RegConsoleCmd("sm_showtriggerssettings", cmdShowTriggersSettings, "Toggle trigger settings menu");
    RegConsoleCmd("sm_stsettings", cmdShowTriggersSettings, "Toggle trigger settings menu");
    RegConsoleCmd("sm_sts", cmdShowTriggersSettings, "Toggle trigger settings menu");
    RegConsoleCmd("sm_showtriggers", cmdShowTriggers, "Toggles brush visibility");
    RegConsoleCmd("sm_st", cmdShowTriggers, "Toggles brush visibility");

    // Command for color settings
    RegConsoleCmd("sm_triggercolors", cmdTriggerColors, "Open trigger color settings menu");
    
    // Command for searching triggers
    RegConsoleCmd("sm_searchtriggers", cmdSearchTriggers, "Search for specific triggers");

    Menu menu = new Menu(menuHandler_Main, MenuAction_DrawItem|MenuAction_DisplayItem);
    menu.SetTitle("Toggle Visibility");
    menu.AddItem("-2", "Enable All Triggers");
    menu.AddItem("-1", "Disable All Triggers\n\n");
    for (int i = 0; i < MAX_TYPES; i++)
    {
        menu.AddItem(IntToStringEx(i), g_NAMES[i]);
    }
    g_Menu = menu;

    // Initialize search results array
    g_SearchResults = new ArrayList(ByteCountToCells(128));

    // Initialize trigger visibility states
    for (int ent = MaxClients + 1; ent <= 2048; ent++)
    {
        for (int client = 1; client <= MaxClients; client++)
        {
            g_bTriggerEnabled[ent][client] = false;
        }
    }
    
    // Create cookies for saving color preferences
    for (int i = 0; i < MAX_TYPES; i++)
    {
        char cookieName[32];
        FormatEx(cookieName, sizeof(cookieName), "showtriggers_color_%s", g_NAMES[i]);
        g_ColorCookie[i] = RegClientCookie(cookieName, "Color preference for trigger type", CookieAccess_Protected);
    }

    // Create cookies for special trigger_multiple colors
    g_ColorCookieSpecial[0] = RegClientCookie("showtriggers_color_multiple_gravity", "Color preference for trigger_multiple gravity", CookieAccess_Protected);
    g_ColorCookieSpecial[1] = RegClientCookie("showtriggers_color_multiple_antigravity", "Color preference for trigger_multiple antigravity", CookieAccess_Protected);
    g_ColorCookieSpecial[2] = RegClientCookie("showtriggers_color_multiple_basevelocity", "Color preference for trigger_multiple basevelocity", CookieAccess_Protected);

    // Initialize default colors for all clients
    for (int client = 1; client <= MaxClients; client++)
    {
        if (IsClientInGame(client))
        {
            InitClientColors(client);
        }
    }

    // Load colors for all in-game clients
    for (int client = 1; client <= MaxClients; client++)
    {
        if (IsClientInGame(client) && AreClientCookiesCached(client))
        {
            LoadClientColors(client);
        }
    }

    // Late load support
    for (int client = 1; client <= MaxClients; client++)
    {
        if (IsClientInGame(client))
        {
            OnClientPutInServer(client);
        }
    }
}

public Action cmdShowTriggersHelp(int client, int args)
{
	if (IsValidClient(client))
	{
		PrintToChat(client, "!showtriggers (!st) -> Toggles visibility for trigger_teleport triggers.");
		PrintToChat(client, "!showtriggerssettings (!stsettings, !sts) -> Displays menu to toggle certain trigger visibility.");
		PrintToChat(client, "!searchtriggers -> Search for individual triggers to toggle visibility.");
		PrintToChat(client, "!triggercolors -> Customizable colour settings for triggers.");
	}
	
	return Plugin_Handled;
}

public Action cmdShowTriggers(int client, int args)
{
	if (IsValidClient(client))
	{
		for (int i = 0; i < MAX_TYPES; i++)
		{
			continue;
		}
		if (!g_bTypeEnabled[client][2])
		{
			for (int j = 0; j < MAX_TYPES; j++)
			{
				g_bTypeEnabled[client][2] = true;
			}
			CheckBrushes(ShouldRender());
			PrintToChat(client, "Showtriggers toggled: ON");
			PrintToChat(client, "Consider using !stsettings(!sts) for more options.");
		}
		else
		{
			for (int k = 0; k < MAX_TYPES; k++)
			{
				g_bTypeEnabled[client][2] = false;
			}
			CheckBrushes(ShouldRender());
			PrintToChat(client, "Showtriggers toggled: OFF");
		}
	}

	return Plugin_Handled;
}

// Display trigger menu
public Action cmdShowTriggersSettings(int client, int args)
{
	if (IsValidClient(client))
	{
		if (client)
		{
			g_Menu.Display(client, MENU_TIME_FOREVER);
		}
	}

	return Plugin_Handled;
}

public int menuHandler_Main(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char info[8];
			menu.GetItem(param2, info, sizeof info);

			int type = StringToInt(info);
			switch (type)
			{
				case ENABLE_ALL:
				{
					// Loop through all types and enable
					for (int i = 0; i < MAX_TYPES; i++)
					{
						g_bTypeEnabled[param1][i] = true;
					}
				}
				case DISABLE_ALL:
				{
					// Loop through all types and disable
					for (int i = 0; i < MAX_TYPES; i++)
					{
						g_bTypeEnabled[param1][i] = false;
					}
				}
				default:
				{
					// Toggle selected type
					g_bTypeEnabled[param1][type] = !g_bTypeEnabled[param1][type];
				}
			}
			
			CheckBrushes(ShouldRender());

			menu.DisplayAt(param1, menu.Selection, MENU_TIME_FOREVER);
		}
		// Check *_ALL items to see if they should be disabled
		case MenuAction_DrawItem:
		{
			char info[8];
			menu.GetItem(param2, info, sizeof info);
			switch (StringToInt(info))
			{
				case ENABLE_ALL:
				{
					for (int i = 0; i < MAX_TYPES; i++)
					{
						if (!g_bTypeEnabled[param1][i])
						{
							return ITEMDRAW_DEFAULT;
						}
					}

					return ITEMDRAW_DISABLED;
				}
				case DISABLE_ALL:
				{
					for (int i = 0; i < MAX_TYPES; i++)
					{
						if (g_bTypeEnabled[param1][i])
						{
							return ITEMDRAW_DEFAULT;
						}
					}

					return ITEMDRAW_DISABLED;
				}
			}

			return ITEMDRAW_DEFAULT;
		}
		// Check which items are enabled.
		case MenuAction_DisplayItem:
		{
			char info[8];
			char text[64];
			menu.GetItem(param2, info, sizeof info, _, text, sizeof text);

			int type = StringToInt(info);
			if (type >= 0)
			{
				if (g_bTypeEnabled[param1][type])
				{
					StrCat(text, sizeof text, ": [ON]");
					return RedrawMenuItem(text);
				}
				else
				{
					StrCat(text, sizeof text, ": [OFF]");
				}
			}
		}
	}

	return 0;
}

public void OnClientDisconnect(int client)
{
	for (int i = 0; i < MAX_TYPES; i++)
	{
		g_bTypeEnabled[client][i] = false;
	}

	CheckBrushes(ShouldRender());
}

public void OnPluginEnd()
{
	CheckBrushes(false);
}

public void OnClientPutInServer(int client)
{
    InitClientColors(client);
    
    // Initialize trigger visibility states for the new client
    for (int ent = MaxClients + 1; ent <= 2048; ent++)
    {
        g_bTriggerEnabled[ent][client] = false;
    }

    // If client cookies are already cached, load the colors
    if (AreClientCookiesCached(client))
    {
        LoadClientColors(client);
    }
}

public void OnClientCookiesCached(int client)
{
    if (IsValidClient(client))
    {
        LoadClientColors(client);
    }
}

// ======================== Normal Functions ========================


/**
 * If transmit state has changed, iterates through each brush type
 * to modify entity flags and to (un)hook as needed.
 * 
 * @param transmit    Should we attempt to transmit these brushes?
 */
void CheckBrushes(bool transmit)
{
	static bool hooked = false;

	// If transmit state has not changed, do nothing
	if (hooked == transmit)
	{
		return;
	}

	hooked = !hooked;

	char className[32];
	for (int ent = MaxClients + 1; ent <= 2048; ent++)
	{
		if (!IsValidEntity(ent))
		{
			continue;
		}

		GetEntityClassname(ent, className, sizeof className);
		if (StrContains(className, "func_") != 0 && StrContains(className, "trigger_") != 0)
		{
			continue;
		}

		for (int i = 0; i < MAX_TYPES; i++)
		{
			if (!StrEqual(className, g_NAMES[i]))
			{
				continue;
			}

			SDKHookCB f = INVALID_FUNCTION;
			switch (i)
			{
				case TRIGGER_MULTIPLE:          f = hookST_triggerMultiple;
				case TRIGGER_PUSH:              f = hookST_triggerPush;
				case TRIGGER_TELEPORT:          f = hookST_triggerTeleport;
				case TRIGGER_TELEPORT_RELATIVE: f = hookST_triggerTeleportRelative;
				// somehow got an invalid index. this shouldnt happen unless someone modifies this plugin and fucks up.
				default: break;
			}

			if (hooked)
			{
				SetEntData(ent, g_iOffsetMFEffects, GetEntData(ent, g_iOffsetMFEffects) & ~EF_NODRAW);
				ChangeEdictState(ent, g_iOffsetMFEffects);
				SetEdictFlags(ent, GetEdictFlags(ent) & ~FL_EDICT_DONTSEND);
				SDKHook(ent, SDKHook_SetTransmit, f);
			}
			else
			{
				SetEntData(ent, g_iOffsetMFEffects, GetEntData(ent, g_iOffsetMFEffects) | EF_NODRAW);
				ChangeEdictState(ent, g_iOffsetMFEffects);
				SetEdictFlags(ent, GetEdictFlags(ent) | FL_EDICT_DONTSEND);
				SDKUnhook(ent, SDKHook_SetTransmit, f);
			}

			break;
		}
	}
}

/**
 * Function to return the int value as a string directly.
 * 
 * @param value    The integer value to convert to string
 * @return         String value of passed integer
 */
char[] IntToStringEx(int value)
{
	char result[11];
	IntToString(value, result, sizeof result);
	return result;
}

/**
 * Function to check if we should be attempting to render any of the brush types.
 * Meant to be passed to CheckTriggers() and used for optimizing SetTransmit hooking.
 * 
 * @return        True if any client has any brush types enabled, else false
 */
bool ShouldRender()
{
	for (int client = 1; client <= MaxClients; client++)
	{
		if (IsClientInGame(client))
		{
			for (int i = 0; i < MAX_TYPES; i++)
			{
				if (g_bTypeEnabled[client][i])
				{
					return true;
				}
			}
		}
	}

	return false;
}

// ======================== SetTransmit Hooks ========================

// Modified: SetTransmit hooks to check individual trigger visibility and set colors

public Action hookST_triggerMultiple(int entity, int client)
{
    if (g_bTriggerEnabled[entity][client] || g_bTypeEnabled[client][TRIGGER_MULTIPLE])
    {
        char buffer[32];
        int count = GetOutputCount(entity, "m_OnStartTouch");
        for(int i = 0; i < count; i++)
        {
            GetOutputParameter(entity, "m_OnStartTouch", i, buffer, sizeof(buffer));
            if(StrEqual(buffer, "gravity 40"))
            {
                SetEntityRenderColor(entity, g_ColorsSpecial[client][0][0], g_ColorsSpecial[client][0][1], g_ColorsSpecial[client][0][2], 255);
                return Plugin_Continue;
            }
        }
        count = GetOutputCount(entity, "m_OnEndTouch");
        for(int i = 0; i < count; i++)
        {
            GetOutputParameter(entity, "m_OnEndTouch", i, buffer, sizeof(buffer));
            if(StrContains(buffer, "gravity -") != -1)
            {
                SetEntityRenderColor(entity, g_ColorsSpecial[client][1][0], g_ColorsSpecial[client][1][1], g_ColorsSpecial[client][1][2], 255);
                return Plugin_Continue;
            }
            if(StrContains(buffer, "basevelocity") != -1)
            {
                SetEntityRenderColor(entity, g_ColorsSpecial[client][2][0], g_ColorsSpecial[client][2][1], g_ColorsSpecial[client][2][2], 255);
                return Plugin_Continue;
            }
        }
        // Default color if no specific condition is met
        SetEntityRenderColor(entity, g_Colors[client][TRIGGER_MULTIPLE][0], g_Colors[client][TRIGGER_MULTIPLE][1], g_Colors[client][TRIGGER_MULTIPLE][2], 255);
        return Plugin_Continue;
    }
    return Plugin_Handled;
}

public Action hookST_triggerPush(int entity, int client)
{
    if (g_bTriggerEnabled[entity][client] || g_bTypeEnabled[client][TRIGGER_PUSH])
    {
        SetEntityRenderColor(entity, g_Colors[client][TRIGGER_PUSH][0], g_Colors[client][TRIGGER_PUSH][1], g_Colors[client][TRIGGER_PUSH][2], 255);
        return Plugin_Continue;
    }
    return Plugin_Handled;
}

public Action hookST_triggerTeleport(int entity, int client)
{
    if (g_bTriggerEnabled[entity][client] || g_bTypeEnabled[client][TRIGGER_TELEPORT])
    {
        SetEntityRenderColor(entity, g_Colors[client][TRIGGER_TELEPORT][0], g_Colors[client][TRIGGER_TELEPORT][1], g_Colors[client][TRIGGER_TELEPORT][2], 255);
        return Plugin_Continue;
    }
    return Plugin_Handled;
}

public Action hookST_triggerTeleportRelative(int entity, int client)
{
    if (g_bTriggerEnabled[entity][client] || g_bTypeEnabled[client][TRIGGER_TELEPORT_RELATIVE])
    {
        SetEntityRenderColor(entity, g_Colors[client][TRIGGER_TELEPORT_RELATIVE][0], g_Colors[client][TRIGGER_TELEPORT_RELATIVE][1], g_Colors[client][TRIGGER_TELEPORT_RELATIVE][2], 255);
        return Plugin_Continue;
    }
    return Plugin_Handled;
}

SDKHookCB GetTransmitHook(int type)
{
    switch (type)
    {
        case TRIGGER_MULTIPLE:          return hookST_triggerMultiple;
        case TRIGGER_PUSH:              return hookST_triggerPush;
        case TRIGGER_TELEPORT:          return hookST_triggerTeleport;
        case TRIGGER_TELEPORT_RELATIVE: return hookST_triggerTeleportRelative;
    }
    return INVALID_FUNCTION;
}

stock bool IsValidClient(int client, bool nobots = true)
{ 
    if (client <= 0 || client > MaxClients || !IsClientConnected(client) || (nobots && IsFakeClient(client)))
    {
        return false; 
    }
    return IsClientInGame(client); 
} 

// ======================== New: Search / Individual Trigger Display ========================

// Command handler for searching triggers
public Action cmdSearchTriggers(int client, int args)
{
    if (!IsValidClient(client))
        return Plugin_Handled;

    if (args < 1)
    {
        ReplyToCommand(client, "Usage: sm_searchtriggers <search term>");
        return Plugin_Handled;
    }

    char searchTerm[64];
    GetCmdArgString(searchTerm, sizeof(searchTerm));

    SearchTriggers(client, searchTerm);

    return Plugin_Handled;
}

// Search function to include classname and targetname
void SearchTriggers(int client, const char[] searchTerm)
{
    g_SearchResults.Clear();

    char className[32], targetname[64];
    for (int ent = MaxClients + 1; ent <= 2048; ent++)
    {
        if (!IsValidEntity(ent))
            continue;

        GetEntityClassname(ent, className, sizeof(className));
        if (StrContains(className, "trigger_") != 0)
            continue;

        GetEntPropString(ent, Prop_Data, "m_iName", targetname, sizeof(targetname));
        
        if (StrContains(targetname, searchTerm, false) != -1 || StrContains(className, searchTerm, false) != -1)
        {
            g_SearchResults.Push(ent);
        }
    }

    if (g_SearchResults.Length > 0)
    {
        DisplaySearchResultsMenu(client, 0);
    }
    else
    {
        PrintToChat(client, "No triggers found matching the search term: %s", searchTerm);
    }
}

// Display search results with pagination
void DisplaySearchResultsMenu(int client, int startItem)
{
    Menu menu = new Menu(menuHandler_SearchResults);
    menu.SetTitle("Search Results");

    char entIndex[8], displayName[64], className[32], targetname[64];
    int totalItems = g_SearchResults.Length;
    int endItem = startItem + 6 > totalItems ? totalItems : startItem + 6;

    for (int i = startItem; i < endItem; i++)
    {
        int ent = g_SearchResults.Get(i);
        IntToString(ent, entIndex, sizeof(entIndex));
        GetEntityClassname(ent, className, sizeof(className));
        GetEntPropString(ent, Prop_Data, "m_iName", targetname, sizeof(targetname));
        
        FormatEx(displayName, sizeof(displayName), "%s (%s) [%s]", targetname, className, g_bTriggerEnabled[ent][client] ? "ON" : "OFF");
        menu.AddItem(entIndex, displayName);
    }

    if (startItem > 0)
    {
        menu.AddItem("prev", "Previous Page");
    }

    if (endItem < totalItems)
    {
        menu.AddItem("next", "Next Page");
    }

    menu.ExitButton = true;
    menu.DisplayAt(client, startItem, MENU_TIME_FOREVER);
}

// Menu handler for search results
public int menuHandler_SearchResults(Menu menu, MenuAction action, int param1, int param2)
{
    switch (action)
    {
        case MenuAction_Select:
        {
            char info[8];
            menu.GetItem(param2, info, sizeof(info));
            
            if (StrEqual(info, "prev"))
            {
                int newStart = menu.Selection - 6;
                if (newStart < 0) newStart = 0;
                DisplaySearchResultsMenu(param1, newStart);
            }
            else if (StrEqual(info, "next"))
            {
                DisplaySearchResultsMenu(param1, menu.Selection + 1);
            }
            else
            {
                int ent = StringToInt(info);
                ToggleTriggerVisibility(param1, ent);
                DisplaySearchResultsMenu(param1, menu.Selection);
            }
        }
        case MenuAction_End:
        {
            delete menu;
        }
    }
    return 0;
}

// Toggle visibility for a specific trigger
void ToggleTriggerVisibility(int client, int ent)
{
    char className[32];
    GetEntityClassname(ent, className, sizeof(className));

    int type = -1;
    for (int i = 0; i < MAX_TYPES; i++)
    {
        if (StrEqual(className, g_NAMES[i]))
        {
            type = i;
            break;
        }
    }

    if (type != -1)
    {
        g_bTriggerEnabled[ent][client] = !g_bTriggerEnabled[ent][client];
        
        if (g_bTriggerEnabled[ent][client])
        {
            SetEntData(ent, g_iOffsetMFEffects, GetEntData(ent, g_iOffsetMFEffects) & ~EF_NODRAW);
            SetEdictFlags(ent, GetEdictFlags(ent) & ~FL_EDICT_DONTSEND);
            SDKHook(ent, SDKHook_SetTransmit, GetTransmitHook(type));
        }
        else
        {
            SetEntData(ent, g_iOffsetMFEffects, GetEntData(ent, g_iOffsetMFEffects) | EF_NODRAW);
            SetEdictFlags(ent, GetEdictFlags(ent) | FL_EDICT_DONTSEND);
            SDKUnhook(ent, SDKHook_SetTransmit, GetTransmitHook(type));
        }
        
        ChangeEdictState(ent, g_iOffsetMFEffects);
        
        char targetname[64];
        GetEntPropString(ent, Prop_Data, "m_iName", targetname, sizeof(targetname));
        PrintToChat(client, "Toggled visibility for %s (%s): %s", targetname, className, g_bTriggerEnabled[ent][client] ? "ON" : "OFF");
    }
}

// ======================== New: Customizable trigger colours ========================

// Default colors
int g_DefaultColors[MAX_TYPES][3] = {
    {255, 255, 0},  // TRIGGER_MULTIPLE
    {0, 255, 0},    // TRIGGER_PUSH
    {255, 0, 0},    // TRIGGER_TELEPORT
    {255, 0, 0}     // TRIGGER_TELEPORT_RELATIVE
};

int g_DefaultColorsSpecial[3][3] = {
    {255, 100, 0},  // Gravity
    {0, 255, 185},  // Anti-gravity
    {0, 255, 0}     // Base velocity
};

void InitClientColors(int client)
{
    for (int i = 0; i < MAX_TYPES; i++)
    {
        for (int j = 0; j < 3; j++)
        {
            g_Colors[client][i][j] = g_DefaultColors[i][j];
        }
    }
    
    for (int i = 0; i < 3; i++)
    {
        for (int j = 0; j < 3; j++)
        {
            g_ColorsSpecial[client][i][j] = g_DefaultColorsSpecial[i][j];
        }
    }
}

void LoadClientColors(int client)
{
    char cookieValue[12];
    for (int i = 0; i < MAX_TYPES; i++)
    {
        if (g_ColorCookie[i] != null)
        {
            GetClientCookie(client, g_ColorCookie[i], cookieValue, sizeof(cookieValue));
            if (strlen(cookieValue) > 0)
            {
                char colorStrings[3][4];
                ExplodeString(cookieValue, ",", colorStrings, 3, 4);
                for (int j = 0; j < 3; j++)
                {
                    g_Colors[client][i][j] = StringToInt(colorStrings[j]);
                }
            }
        }
    }
    
    for (int i = 0; i < 3; i++)
    {
        if (g_ColorCookieSpecial[i] != null)
        {
            GetClientCookie(client, g_ColorCookieSpecial[i], cookieValue, sizeof(cookieValue));
            if (strlen(cookieValue) > 0)
            {
                char colorStrings[3][4];
                ExplodeString(cookieValue, ",", colorStrings, 3, 4);
                for (int j = 0; j < 3; j++)
                {
                    g_ColorsSpecial[client][i][j] = StringToInt(colorStrings[j]);
                }
            }
        }
    }
}

void SaveClientColor(int client, int triggerType)
{
    if (triggerType < 0 || triggerType >= MAX_TYPES)
    {
        LogError("Attempted to save invalid trigger type color: %d", triggerType);
        return;
    }

    char cookieValue[12];
    FormatEx(cookieValue, sizeof(cookieValue), "%d,%d,%d", g_Colors[client][triggerType][0], g_Colors[client][triggerType][1], g_Colors[client][triggerType][2]);
    SetClientCookie(client, g_ColorCookie[triggerType], cookieValue);
}

void SaveClientSpecialColor(int client, int colorType)
{
    char cookieValue[12];
    FormatEx(cookieValue, sizeof(cookieValue), "%d,%d,%d", g_ColorsSpecial[client][colorType][0], g_ColorsSpecial[client][colorType][1], g_ColorsSpecial[client][colorType][2]);
    SetClientCookie(client, g_ColorCookieSpecial[colorType], cookieValue);
}

public Action cmdTriggerColors(int client, int args)
{
    if (IsValidClient(client))
    {
        DisplayColorSettingsMenu(client);
    }
    return Plugin_Handled;
}

void ResetClientColors(int client)
{
    InitClientColors(client);
    for (int i = 0; i < MAX_TYPES; i++)
    {
        SaveClientColor(client, i);
    }
    for (int i = 0; i < 3; i++)
    {
        SaveClientSpecialColor(client, i);
    }
    PrintToChat(client, "[Show Triggers] All colors have been reset to default.");
}

void DisplayColorSettingsMenu(int client)
{
    Menu menu = new Menu(menuHandler_ColorSettings);
    menu.SetTitle("Trigger Color Settings");

    for (int i = 0; i < MAX_TYPES; i++)
    {
        char info[8], display[64];
        IntToString(i, info, sizeof(info));
        FormatEx(display, sizeof(display), "%s - [%d,%d,%d]", g_NAMES[i], g_Colors[client][i][0], g_Colors[client][i][1], g_Colors[client][i][2]);
        menu.AddItem(info, display);
    }
    
    menu.AddItem("special", "Special Trigger Multiple Colors");
    menu.AddItem("reset", "Reset All Colors to Default");

    menu.ExitButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int menuHandler_ColorSettings(Menu menu, MenuAction action, int param1, int param2)
{
    switch (action)
    {
        case MenuAction_Select:
        {
            char info[8];
            menu.GetItem(param2, info, sizeof(info));
            if (StrEqual(info, "special"))
            {
                DisplaySpecialColorSettingsMenu(param1);
            }
            else if (StrEqual(info, "reset"))
            {
                ResetClientColors(param1);
                DisplayColorSettingsMenu(param1);
            }
            else
            {
                int triggerType = StringToInt(info);
                DisplayColorComponentMenu(param1, triggerType);
            }
        }
        case MenuAction_End:
        {
            delete menu;
        }
    }
    return 0;
}

void DisplayColorComponentMenu(int client, int triggerType)
{
    Menu menu = new Menu(menuHandler_ColorComponent);
    menu.SetTitle("Edit Color for %s", g_NAMES[triggerType]);

    char info[16], display[32];
    for (int i = 0; i < 3; i++)
    {
        FormatEx(info, sizeof(info), "%d_%d", triggerType, i);
        FormatEx(display, sizeof(display), "%s: %d", (i == 0) ? "Red" : (i == 1) ? "Green" : "Blue", g_Colors[client][triggerType][i]);
        menu.AddItem(info, display);
    }

    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int menuHandler_ColorComponent(Menu menu, MenuAction action, int param1, int param2)
{
    switch (action)
    {
        case MenuAction_Select:
        {
            char info[16];
            menu.GetItem(param2, info, sizeof(info));
            char parts[2][8];
            ExplodeString(info, "_", parts, 2, 8);
            int triggerType = StringToInt(parts[0]);
            int colorComponent = StringToInt(parts[1]);
            DisplayColorValueMenu(param1, triggerType, colorComponent);
        }
        case MenuAction_Cancel:
        {
            if (param2 == MenuCancel_ExitBack)
            {
                DisplayColorSettingsMenu(param1);
            }
        }
        case MenuAction_End:
        {
            delete menu;
        }
    }
    return 0;
}

void DisplayColorValueMenu(int client, int triggerType, int colorComponent)
{
    Menu menu = new Menu(menuHandler_ColorValue);
    menu.SetTitle("Set %s value for %s", (colorComponent == 0) ? "Red" : (colorComponent == 1) ? "Green" : "Blue", g_NAMES[triggerType]);

    char info[32], display[8];
    for (int i = 0; i <= 255; i += 51)
    {
        FormatEx(info, sizeof(info), "%d_%d_%d", triggerType, colorComponent, i);
        IntToString(i, display, sizeof(display));
        menu.AddItem(info, display);
    }

    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int menuHandler_ColorValue(Menu menu, MenuAction action, int param1, int param2)
{
    switch (action)
    {
        case MenuAction_Select:
        {
            char info[32];
            menu.GetItem(param2, info, sizeof(info));
            char parts[3][8];
            ExplodeString(info, "_", parts, 3, 8);
            int triggerType = StringToInt(parts[0]);
            int colorComponent = StringToInt(parts[1]);
            int colorValue = StringToInt(parts[2]);

            g_Colors[param1][triggerType][colorComponent] = colorValue;
            SaveClientColor(param1, triggerType);
            PrintToChat(param1, "Color updated for %s", g_NAMES[triggerType]);
            DisplayColorComponentMenu(param1, triggerType);
        }
        case MenuAction_Cancel:
        {
            if (param2 == MenuCancel_ExitBack)
            {
                char info[16];
                menu.GetItem(0, info, sizeof(info));
                char parts[2][8];
                ExplodeString(info, "_", parts, 2, 8);
                int triggerType = StringToInt(parts[0]);
                DisplayColorComponentMenu(param1, triggerType);
            }
        }
        case MenuAction_End:
        {
            delete menu;
        }
    }
    return 0;
}

void DisplaySpecialColorSettingsMenu(int client)
{
    Menu menu = new Menu(menuHandler_SpecialColorSettings);
    menu.SetTitle("Special Trigger Multiple Color Settings");

    char display[64];
    FormatEx(display, sizeof(display), "Gravity - [%d,%d,%d]", g_ColorsSpecial[client][0][0], g_ColorsSpecial[client][0][1], g_ColorsSpecial[client][0][2]);
    menu.AddItem("0", display);
    FormatEx(display, sizeof(display), "Anti-gravity - [%d,%d,%d]", g_ColorsSpecial[client][1][0], g_ColorsSpecial[client][1][1], g_ColorsSpecial[client][1][2]);
    menu.AddItem("1", display);
    FormatEx(display, sizeof(display), "Base velocity - [%d,%d,%d]", g_ColorsSpecial[client][2][0], g_ColorsSpecial[client][2][1], g_ColorsSpecial[client][2][2]);
    menu.AddItem("2", display);

    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int menuHandler_SpecialColorSettings(Menu menu, MenuAction action, int param1, int param2)
{
    switch (action)
    {
        case MenuAction_Select:
        {
            char info[8];
            menu.GetItem(param2, info, sizeof(info));
            int colorType = StringToInt(info);
            DisplaySpecialColorComponentMenu(param1, colorType);
        }
        case MenuAction_Cancel:
        {
            if (param2 == MenuCancel_ExitBack)
            {
                DisplayColorSettingsMenu(param1);
            }
        }
        case MenuAction_End:
        {
            delete menu;
        }
    }
    return 0;
}

void DisplaySpecialColorComponentMenu(int client, int colorType)
{
    Menu menu = new Menu(menuHandler_SpecialColorComponent);
    menu.SetTitle("Edit Special Color");

    char info[16], display[32];
    for (int i = 0; i < 3; i++)
    {
        FormatEx(info, sizeof(info), "%d_%d", colorType, i);
        FormatEx(display, sizeof(display), "%s: %d", (i == 0) ? "Red" : (i == 1) ? "Green" : "Blue", g_ColorsSpecial[client][colorType][i]);
        menu.AddItem(info, display);
    }

    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int menuHandler_SpecialColorComponent(Menu menu, MenuAction action, int param1, int param2)
{
    switch (action)
    {
        case MenuAction_Select:
        {
            char info[16];
            menu.GetItem(param2, info, sizeof(info));
            char parts[2][8];
            ExplodeString(info, "_", parts, 2, 8);
            int colorType = StringToInt(parts[0]);
            int colorComponent = StringToInt(parts[1]);
            DisplaySpecialColorValueMenu(param1, colorType, colorComponent);
        }
        case MenuAction_Cancel:
        {
            if (param2 == MenuCancel_ExitBack)
            {
                DisplaySpecialColorSettingsMenu(param1);
            }
        }
        case MenuAction_End:
        {
            delete menu;
        }
    }
    return 0;
}

void DisplaySpecialColorValueMenu(int client, int colorType, int colorComponent)
{
    Menu menu = new Menu(menuHandler_SpecialColorValue);
    menu.SetTitle("Set %s value for Special Color", (colorComponent == 0) ? "Red" : (colorComponent == 1) ? "Green" : "Blue");

    char info[32], display[8];
    for (int i = 0; i <= 255; i += 51)
    {
        FormatEx(info, sizeof(info), "%d_%d_%d", colorType, colorComponent, i);
        IntToString(i, display, sizeof(display));
        menu.AddItem(info, display);
    }

    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int menuHandler_SpecialColorValue(Menu menu, MenuAction action, int param1, int param2)
{
    switch (action)
    {
        case MenuAction_Select:
        {
            char info[32];
            menu.GetItem(param2, info, sizeof(info));
            char parts[3][8];
            ExplodeString(info, "_", parts, 3, 8);
            int colorType = StringToInt(parts[0]);
            int colorComponent = StringToInt(parts[1]);
            int colorValue = StringToInt(parts[2]);

            g_ColorsSpecial[param1][colorType][colorComponent] = colorValue;
            SaveClientSpecialColor(param1, colorType);
            PrintToChat(param1, "Special color updated");
            DisplaySpecialColorComponentMenu(param1, colorType);
        }
        case MenuAction_Cancel:
        {
            if (param2 == MenuCancel_ExitBack)
            {
                char info[16];
                menu.GetItem(0, info, sizeof(info));
                char parts[2][8];
                ExplodeString(info, "_", parts, 2, 8);
                int colorType = StringToInt(parts[0]);
                DisplaySpecialColorComponentMenu(param1, colorType);
            }
        }
        case MenuAction_End:
        {
            delete menu;
        }
    }
    return 0;
}