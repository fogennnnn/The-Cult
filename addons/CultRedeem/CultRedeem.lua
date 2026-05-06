local ADDON_TAG = "|cff8ad3ff[CultRedeem]|r "

if not CultRedeem_Char then
  CultRedeem_Char = {}
end

local function msg(text, r, g, b)
  DEFAULT_CHAT_FRAME:AddMessage(ADDON_TAG .. text, r or 1, g or 1, b or 1)
end

local function trim(value)
  value = tostring(value or "")
  value = string.gsub(value, "^%s+", "")
  value = string.gsub(value, "%s+$", "")
  return value
end

local function normalizedCode(raw)
  local code = string.upper(trim(raw))
  if string.find(code, "^[A-Z0-9]+$") and string.len(code) >= 6 and string.len(code) <= 24 then
    return code
  end
  return nil
end

local function composeTicket(code)
  return "redeem " .. code
end

local function insertIntoChat(text)
  if not ChatFrameEditBox then
    return false
  end
  ChatFrameEditBox:Show()
  ChatFrameEditBox:SetFocus()
  ChatFrameEditBox:SetText(text)
  return true
end

local function lowerSafe(value)
  if not value then
    return ""
  end
  return string.lower(tostring(value))
end

local function tryFillTicketText(text)
  if not text or text == "" then
    return false
  end
  if not (GMTicketText and GMTicketText.SetText and GMTicketText.IsVisible and GMTicketText:IsVisible()) then
    return false
  end
  pcall(function()
    GMTicketText:SetText(text)
    GMTicketText:SetFocus()
    if GMTicketText.HighlightText then
      GMTicketText:HighlightText()
    end
  end)
  return true
end

local function isGMIssuesButtonText(text)
  local t = lowerSafe(text)
  return string.find(t, "issues that gms can assist with", 1, true)
    or string.find(t, "issues that gm", 1, true)
    or string.find(t, "can assist with", 1, true)
end

local function clickIssuesButtonRecursive(root, depth)
  if not root or depth > 5 or not root.GetChildren then
    return false
  end
  local children = { root:GetChildren() }
  local childCount = table.getn(children)
  local i
  for i = 1, childCount do
    local child = children[i]
    if child and child.IsVisible and child:IsVisible() then
      if child.GetText and child.Click then
        local ok, text = pcall(child.GetText, child)
        if ok and text and isGMIssuesButtonText(text) then
          pcall(child.Click, child)
          return true
        end
      end
      if clickIssuesButtonRecursive(child, depth + 1) then
        return true
      end
    end
  end
  return false
end

local function advanceHelpFrame()
  if type(ToggleHelpFrame) == "function" and not (HelpFrame and HelpFrame.IsVisible and HelpFrame:IsVisible()) then
    pcall(ToggleHelpFrame)
  end
  if type(HelpFrame_OpenTicket) == "function" then
    pcall(HelpFrame_OpenTicket)
  end
  if HelpFrame and HelpFrame.IsVisible and HelpFrame:IsVisible() then
    clickIssuesButtonRecursive(HelpFrame, 0)
  end
end

local redeemFillRunner = CreateFrame("Frame")
redeemFillRunner:SetScript("OnUpdate", function()
  local elapsed = arg1 or 0
  local state = CultRedeem_Char and CultRedeem_Char.pendingFill
  if not state or not state.text then
    return
  end
  state.elapsed = (state.elapsed or 0) + elapsed
  if state.elapsed < 0.12 then
    return
  end
  state.elapsed = 0
  state.tries = (state.tries or 0) + 1

  if tryFillTicketText(state.text) then
    CultRedeem_Char.pendingFill = nil
    msg("Ticket text inserted. Press Submit.", 0.6, 1.0, 0.6)
    return
  end

  advanceHelpFrame()

  if state.tries >= 80 then
    CultRedeem_Char.pendingFill = nil
    msg("Could not auto-fill ticket box. Paste this manually:", 1.0, 0.85, 0.45)
    msg(state.text, 1.0, 0.85, 0.45)
  end
end)

local function startTicketFill(text)
  if not CultRedeem_Char then
    CultRedeem_Char = {}
  end
  CultRedeem_Char.pendingFill = {
    text = text,
    tries = 0,
    elapsed = 0,
  }
  advanceHelpFrame()
end

local function showUsage()
  msg("Usage: /redeem <claimcode>", 1.0, 0.9, 0.6)
  msg("Example: /redeem 509B678944B8", 1.0, 0.9, 0.6)
end

local function handleRedeemCommand(input)
  local code = normalizedCode(input)
  if not code then
    msg("Invalid claim code format. Use 6-24 letters/numbers.", 1.0, 0.4, 0.4)
    showUsage()
    return
  end

  local ticketText = composeTicket(code)
  CultRedeem_Char.lastCode = code
  CultRedeem_Char.lastTicketText = ticketText

  insertIntoChat(ticketText)
  startTicketFill(ticketText)

  msg("Prepared: " .. ticketText, 0.6, 1.0, 0.6)
  msg("Opening GM ticket and inserting text...", 0.6, 1.0, 0.6)
end

SLASH_CULTREDEEM1 = "/redeem"
SlashCmdList["CULTREDEEM"] = function(msgText)
  local input = trim(msgText)
  if input == "" then
    showUsage()
    if CultRedeem_Char and CultRedeem_Char.lastTicketText then
      msg("Last prepared: " .. CultRedeem_Char.lastTicketText, 0.7, 0.9, 1.0)
    end
    return
  end
  handleRedeemCommand(input)
end

SLASH_CULTREDEEMHELP1 = "/redeemhelp"
SlashCmdList["CULTREDEEMHELP"] = function()
  showUsage()
  msg("Flow: /redeem CODE -> submit GM ticket text -> gold arrives by mail.", 0.7, 0.9, 1.0)
end

msg("Loaded. Use /redeem <claimcode>.", 0.5, 0.9, 0.5)
