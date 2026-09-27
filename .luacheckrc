std = "lua51"
max_line_length = false
unused_args = false
exclude_files = { "libs/", ".release/" }

globals = {
  "Sprout",
  "SproutDB",
}

read_globals = {
  -- Libraries
  "LibStub", "ChatThrottleLib",
  -- WoW API
  "C_ChatInfo", "C_Map", "C_PartyInfo", "C_Timer", "Enum", "Settings",
  "GetTime", "GetBuildInfo", "GetChannelName", "GetNormalizedRealmName",
  "GetRealZoneText", "GetZoneText", "GetSubZoneText",
  "JoinTemporaryChannel", "LeaveChannelByName",
  "UnitFullName", "UnitName", "UnitNameUnmodified", "UnitLevel", "UnitClass", "UnitFactionGroup",
  "RegionalUniqueNamesEnabled", "MenuUtil",
  "InviteUnit", "ChatFrame_OpenChat", "ChatFrame_SendTell", "ChatFrame_AddMessageEventFilter",
  "ChatFrame_RemoveChannel", "DEFAULT_CHAT_FRAME", "GameTooltip",
  "RAID_CLASS_COLORS", "LOCALIZED_CLASS_NAMES_MALE", "NORMAL_FONT_COLOR",
  "CreateFrame", "UIParent", "GameTooltip_Hide",
  "hooksecurefunc", "strsplit", "strtrim", "wipe", "tinsert", "tremove",
  "date", "time",
}
