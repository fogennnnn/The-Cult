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

local function tryOpenHelpTicket()
  if type(ToggleHelpFrame) == "function" then
    pcall(ToggleHelpFrame)
  end
  if type(HelpFrame_OpenTicket) == "function" then
    pcall(HelpFrame_OpenTicket)
  end
  if GMTicketText and GMTicketText.SetText and CultRedeem_Char and CultRedeem_Char.lastTicketText then
    pcall(function()
      GMTicketText:SetText(CultRedeem_Char.lastTicketText)
      GMTicketText:SetFocus()
    end)
  end
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
  tryOpenHelpTicket()

  msg("Prepared: " .. ticketText, 0.6, 1.0, 0.6)
  msg("Submit this text in a GM ticket if it is not already filled.", 0.6, 1.0, 0.6)
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
