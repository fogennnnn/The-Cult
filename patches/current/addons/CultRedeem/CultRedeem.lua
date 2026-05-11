local ADDON_TAG = "|cff8ad3ff[HEMOGold]|r "

if not CultRedeem_Char then
  CultRedeem_Char = {}
end
if not CultRedeem_DB then
  CultRedeem_DB = {}
end
if not CultRedeem_DB.charMoney then
  CultRedeem_DB.charMoney = {}
end

local function msg(text, r, g, b)
  DEFAULT_CHAT_FRAME:AddMessage(ADDON_TAG .. text, r or 1, g or 1, b or 1)
end

local function moneyText(copper)
  copper = tonumber(copper or 0) or 0
  if copper < 0 then
    copper = 0
  end
  local gold = math.floor(copper / 10000)
  local silver = math.floor(math.mod(copper, 10000) / 100)
  local coin = math.mod(copper, 100)
  return string.format("%dg %ds %dc", gold, silver, coin)
end

local function realmNameSafe()
  return GetRealmName() or "UnknownRealm"
end

local function charKey()
  return realmNameSafe() .. "|" .. (UnitName("player") or "Unknown")
end

local function updateCharSnapshot(money)
  local key = charKey()
  CultRedeem_DB.charMoney[key] = tonumber(money or 0) or 0
end

local function accountMoneyEstimate()
  local total = 0
  local realm = realmNameSafe() .. "|"
  for key, value in pairs(CultRedeem_DB.charMoney) do
    if string.find(key, realm, 1, true) == 1 then
      total = total + (tonumber(value or 0) or 0)
    end
  end
  return total
end

local function saveFramePos(frame)
  local point, _, relPoint, x, y = frame:GetPoint(1)
  CultRedeem_Char.framePoint = point
  CultRedeem_Char.frameRelPoint = relPoint
  CultRedeem_Char.frameX = x
  CultRedeem_Char.frameY = y
end

local function restoreFramePos(frame)
  frame:ClearAllPoints()
  if CultRedeem_Char.framePoint and CultRedeem_Char.frameRelPoint then
    frame:SetPoint(
      CultRedeem_Char.framePoint,
      UIParent,
      CultRedeem_Char.frameRelPoint,
      CultRedeem_Char.frameX or 0,
      CultRedeem_Char.frameY or 0
    )
  else
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 90)
  end
end

local panel = CreateFrame("Frame", "CultHemoPanel", UIParent)
panel:SetWidth(360)
panel:SetHeight(176)
panel:SetMovable(true)
panel:EnableMouse(true)
panel:RegisterForDrag("LeftButton")
panel:SetClampedToScreen(true)
panel:SetBackdrop({
  bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
  edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  tile = true,
  tileSize = 16,
  edgeSize = 16,
  insets = { left = 3, right = 3, top = 3, bottom = 3 }
})
panel:SetBackdropColor(0, 0, 0, 0.92)
panel:SetScript("OnDragStart", function()
  panel:StartMoving()
end)
panel:SetScript("OnDragStop", function()
  panel:StopMovingOrSizing()
  saveFramePos(panel)
end)

local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -14)
title:SetText("HEMOGold")

local closeBtn = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
closeBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -4, -4)

local hint = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
hint:SetJustifyH("LEFT")
hint:SetWidth(320)
hint:SetText("Account mirror status.")

local lineGold = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
lineGold:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -16)
lineGold:SetText("Gold (char): --")

local lineHemo = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
lineHemo:SetPoint("TOPLEFT", lineGold, "BOTTOMLEFT", 0, -8)
lineHemo:SetText("HEMO (acct est): --")

local lineDelta = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
lineDelta:SetPoint("TOPLEFT", lineHemo, "BOTTOMLEFT", 0, -8)
lineDelta:SetText("Last money change: --")

local lineMirror = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
lineMirror:SetPoint("TOPLEFT", lineDelta, "BOTTOMLEFT", 0, -10)
lineMirror:SetWidth(330)
lineMirror:SetJustifyH("LEFT")
lineMirror:SetText("Commands: /hemo   /hemostat")

local lineInterval = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
lineInterval:SetPoint("TOPLEFT", lineMirror, "BOTTOMLEFT", 0, -8)
lineInterval:SetWidth(330)
lineInterval:SetJustifyH("LEFT")
lineInterval:SetText("")

local lineCmd = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
lineCmd:SetPoint("TOPLEFT", lineInterval, "BOTTOMLEFT", 0, -8)
lineCmd:SetWidth(330)
lineCmd:SetJustifyH("LEFT")
lineCmd:SetText("")

local state = {
  lastMoney = 0,
  lastDiff = 0,
  lastChangeAt = 0,
}

local function updateView()
  local money = GetMoney() or 0
  if money ~= state.lastMoney then
    state.lastDiff = money - state.lastMoney
    state.lastMoney = money
    state.lastChangeAt = GetTime() or 0
  end

  updateCharSnapshot(money)
  local accountMoney = accountMoneyEstimate()
  lineGold:SetText("Gold (char): " .. moneyText(money))
  lineHemo:SetText(string.format("HEMO (acct est): %.2f", accountMoney / 10000))

  if state.lastChangeAt <= 0 then
    lineDelta:SetText("Last money change: --")
  else
    local ago = math.max(0, math.floor((GetTime() or 0) - state.lastChangeAt))
    local sign = ""
    if state.lastDiff > 0 then
      sign = "+"
    elseif state.lastDiff < 0 then
      sign = "-"
    end
    lineDelta:SetText("Last money change: " .. sign .. moneyText(math.abs(state.lastDiff)) .. " (" .. ago .. "s ago)")
  end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("VARIABLES_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_MONEY")
eventFrame:SetScript("OnEvent", function()
  if event == "VARIABLES_LOADED" then
    restoreFramePos(panel)
    if CultRedeem_Char.panelHidden == nil then
      CultRedeem_Char.panelHidden = false
    end
    if CultRedeem_Char.panelHidden then
      panel:Hide()
    else
      panel:Show()
    end
  end
  updateView()
end)

local updateTicker = CreateFrame("Frame")
updateTicker:SetScript("OnUpdate", function()
  local elapsed = arg1 or 0
  CultRedeem_Char._pulse = (CultRedeem_Char._pulse or 0) + elapsed
  if CultRedeem_Char._pulse >= 0.33 then
    CultRedeem_Char._pulse = 0
    if panel:IsVisible() then
      updateView()
    end
  end
end)

SLASH_CULTHEMO1 = "/hemo"
SlashCmdList["CULTHEMO"] = function()
  if panel:IsVisible() then
    panel:Hide()
    CultRedeem_Char.panelHidden = true
  else
    panel:Show()
    CultRedeem_Char.panelHidden = false
    updateView()
  end
end

SLASH_CULTHEMOSTAT1 = "/hemostat"
SlashCmdList["CULTHEMOSTAT"] = function()
  local money = GetMoney() or 0
  updateCharSnapshot(money)
  local accountMoney = accountMoneyEstimate()
  msg("Gold now (char): " .. moneyText(money), 0.7, 1.0, 0.8)
  msg(string.format("HEMO (acct est): %.2f", accountMoney / 10000), 0.7, 1.0, 0.8)
end

SLASH_CULTREDEEM1 = "/redeem"
SlashCmdList["CULTREDEEM"] = function()
  msg("Redeem ticket flow is retired. Use /hemo for mirror status.", 1.0, 0.85, 0.5)
end

msg("Loaded. /hemo to toggle panel.", 0.5, 0.9, 0.5)

-- Tooltip safety net:
-- Some UI stacks can append duplicate stat lines repeatedly while hovering.
-- Keep one copy of each numeric stat line so item tooltips remain readable.
local function isNumericStatLine(text)
  if not text then
    return false
  end
  return string.find(text, "^[%+%-]%d+%s") ~= nil
end

local function sanitizeTooltip(tooltip)
  if not tooltip or not tooltip:IsVisible() then
    return
  end
  local tipName = tooltip:GetName()
  if not tipName then
    return
  end
  local lineCount = tooltip:NumLines() or 0
  if lineCount < 3 then
    return
  end

  local seen = {}
  local changed = false
  for i = 2, lineCount do
    local globalName = tipName .. "TextLeft" .. i
    local left = getglobal(globalName)
    if left and left:IsVisible() then
      local text = left:GetText()
      if text and text ~= "" and isNumericStatLine(text) then
        if seen[text] then
          left:SetText("")
          left:Hide()
          changed = true
        else
          seen[text] = true
        end
      end
    end
  end
  if changed then
    tooltip:Show()
  end
end

local tooltipFixTicker = CreateFrame("Frame")
tooltipFixTicker:SetScript("OnUpdate", function()
  local elapsed = arg1 or 0
  CultRedeem_Char._tooltipPulse = (CultRedeem_Char._tooltipPulse or 0) + elapsed
  if CultRedeem_Char._tooltipPulse < 0.08 then
    return
  end
  CultRedeem_Char._tooltipPulse = 0
  sanitizeTooltip(GameTooltip)
  sanitizeTooltip(ItemRefTooltip)
  sanitizeTooltip(ShoppingTooltip1)
  sanitizeTooltip(ShoppingTooltip2)
end)
