#include <sourcemod>
#include <sdktools>

#define POINT_A 0
#define POINT_B 1
#define NUM_POINTS 2
#define PREVIEW_TIME 1.0
#define RING_START_RADIUS 7.0
#define RING_END_RADIUS 7.7

bool gPreview[MAXPLAYERS + 1];
int gCurrPoint[MAXPLAYERS + 1];
float gPointPos[MAXPLAYERS + 1][NUM_POINTS][3];
Handle gPreviewTimer[MAXPLAYERS + 1];

ConVar gCvarBeamMaterial;
int gModelIndex;
int gColorRed[4] = {255, 0, 0, 255};
int gColorGreen[4] = {0, 255, 0, 255};
int gColorWhite[4] = {255, 255, 255, 255};

public void OnPluginStart()
{
	RegConsoleCmd("sm_gap", ConCmd_Gap, "Activates the feature", .flags = 0)

	// sprites/laser.vmt
	// sprites/laserbeam.vmt
	gCvarBeamMaterial = CreateConVar("gap_beams_material", "sprites/laser.vmt", "Material used for beams. Server restart needed for this to take effect.");
}

public void OnClientPutInServer(int client)
{
	ResetVariables(client);
}

public void OnMapStart()
{
	char buff[PLATFORM_MAX_PATH];
	gCvarBeamMaterial.GetString(buff, sizeof(buff));
	gModelIndex = PrecacheModel(buff, true);
}

public Action ConCmd_Gap(int client, int args)
{
	if (!client)
	{
		ReplyToCommand(client, "You have to be in game to use this command");
		return Plugin_Handled;
	}

	OpenMenu(client);
	return Plugin_Handled;
}

public void OnPlayerRunCmdPost(int client, int buttons, int impulse, 
						const float vel[3], const float angles[3], 
						int weapon, int subtype, int cmdnum, 
						int tickcount, int seed, const int mouse[2])
{
	if (!gPreview[client])
	{
		return;
	}

	if (gCurrPoint[client] == POINT_B)
	{
		float endPos[3];

		if (!GetAimPosition(client, endPos))
		{
			return;
		}

		DrawLine(client, gPointPos[ client ][ POINT_A ], endPos, GetTickInterval() * 20, gColorWhite);
	}
}

void OpenMenu(int client)
{
	Panel panel = new Panel();

	panel.SetTitle("Gap");
	panel.DrawItem("Select point");
	//panel.DrawItem("Snapping: off");

	panel.CurrentKey = 10;
	panel.DrawItem("Exit", ITEMDRAW_CONTROL);

	gPreview[client] = panel.Send(client, handler, MENU_TIME_FOREVER);

	delete panel;
}

public int handler(Menu menu, MenuAction action, int client, int item)
{
	if (action != MenuAction_Select)
	{
		gPreview[client] = false;
		return 0;
	}

	switch (item)
	{
		case 1: // Select point
		{
			if (GetAimPosition(client, gPointPos[ client ][ gCurrPoint[client] ]))
			{
				if (gCurrPoint[client] == POINT_A && gPreviewTimer[client] != null)
				{
					// Don't retrigger the timer
					KillTimer(gPreviewTimer[client]);
					gPreviewTimer[client] = null;
				}

				gCurrPoint[client]++;

				if (gCurrPoint[client] == NUM_POINTS)
				{
					float startPos[3], endPos[3];

					startPos = gPointPos[client][ POINT_A ];
					endPos   = gPointPos[client][ POINT_B ];

					// Draw a line between the two points
					DrawRing(client, startPos, RING_START_RADIUS, RING_END_RADIUS, PREVIEW_TIME, gColorGreen, FBEAM_FADEIN);
					DrawRing(client, endPos, RING_START_RADIUS, RING_END_RADIUS, PREVIEW_TIME, gColorRed, FBEAM_FADEIN);
					DrawLine(client, startPos, endPos, PREVIEW_TIME, gColorWhite);
					gPreviewTimer[client] = CreateTimer(PREVIEW_TIME, CompleteGap, client, .flags = TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);

					float distance = GetDistance(startPos, endPos);
					PrintToChat(client, "Distance: %.2f", distance);

					gCurrPoint[client] = POINT_A;
				}
			}
			else
			{
				PrintToChat(client, "Couldn't get point position (raytrace did not hit). Try again.");
			}
			OpenMenu(client);
		}
		case 2: // Snapping
		{
			// TODO: Add snap to grid options
			OpenMenu(client);
		}
		case 10:
		{
			gPreview[client] = false;
		}
	}
	return 0;
}

public Action CompleteGap(Handle timer, int client)
{
	if (!gPreview[client])
	{
		gPreviewTimer[client] = null
		return Plugin_Stop;
	}

	float startPos[3], endPos[3];

	startPos = gPointPos[client][ POINT_A ];
	endPos   = gPointPos[client][ POINT_B ];

	DrawRing(client, startPos, RING_START_RADIUS, RING_END_RADIUS, PREVIEW_TIME, gColorGreen, FBEAM_FADEIN);
	DrawRing(client, endPos, RING_START_RADIUS, RING_END_RADIUS, PREVIEW_TIME, gColorRed, FBEAM_FADEIN);
	DrawLine(client, startPos, endPos, PREVIEW_TIME, gColorWhite);

	return Plugin_Continue;
}

bool GetAimPosition(int client, float endPosition[3])
{
	float eyePosition[3];
	GetClientEyePosition(client, eyePosition);

	float eyeAngles[3];
	GetClientEyeAngles(client, eyeAngles);

	//float dirVector[3];
	//GetAngleVectors(eyeAngles, dirVector, NULL_VECTOR, NULL_VECTOR);

	TR_TraceRayFilter(eyePosition, eyeAngles, MASK_PLAYERSOLID, RayType_Infinite, TraceFilter);

	if (TR_DidHit(null))
	{
		TR_GetEndPosition(endPosition, null);
		return true;
	}
	return false;
}

public bool TraceFilter(int entity, int contentsMask)
{
	// Pass through players
	return !(0 < entity && entity <= MaxClients);
}

stock void DrawLine(int client, float start[3], float end[3], float life, int color[4])
{
	float origin[3];
	GetClientAbsOrigin(client, origin);

	TE_SetupBeamPoints(start, end, 
				.ModelIndex = gModelIndex, 
				.HaloIndex = 0, 
				.StartFrame = 0, 
				.FrameRate = 0,
				.Life = life,
				.Width = 1.0,
				.EndWidth = 1.0,
				.FadeLength = 0,
				.Amplitude = 0.0,
				.Color = color,
				.Speed = 0);
	
	TE_SendToAllInRange(origin, RangeType_Visibility, .delay = 0.0);
}

stock void DrawRing(int client, float center[3], float startRadius, float endRadius, float life, int color[4], int flags = 0)
{
	float origin[3];
	GetClientAbsOrigin(client, origin);

	TE_SetupBeamRingPoint(center, 
				.Start_Radius = startRadius,
				.End_Radius = endRadius,
				.ModelIndex = gModelIndex,
				.HaloIndex = 0,
				.StartFrame = 0,
				.FrameRate = 30,
				.Life = life,
				.Width = 2.0,
				.Amplitude = 0.0,
				.Color = color,
				.Speed = 3,
				.Flags = flags);
	
	TE_SendToAllInRange(origin, RangeType_Visibility, .delay = 0.0);
}

void ResetVariables(int client)
{
	gPreview[client] = false;
	gCurrPoint[client] = POINT_A;
	gPreviewTimer[client] = null;

	for (int i = 0; i < NUM_POINTS; i++)
	{
		gPointPos[client][i] = NULL_VECTOR;
	}
}

float GetDistance(float startPos[3], float endPos[3])
{
	float difference[3];
	SubtractVectors(endPos, startPos, difference);
	return GetVectorLength(difference);
}