SLASH_CULTMAK1 = "/mak"

local function Trim(s)
  if not s then
    return ""
  end
  return string.gsub(s, "^%s*(.-)%s*$", "%1")
end

local function SendMakCommand(msg)
  local command = ".mak"
  local extra = Trim(msg)
  if extra ~= "" then
    command = command .. " " .. extra
  end

  if ChatFrameEditBox then
    ChatFrameEditBox:SetText(command)
    ChatEdit_SendText(ChatFrameEditBox, 0)
    return
  end

  if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.editBox then
    DEFAULT_CHAT_FRAME.editBox:SetText(command)
    ChatEdit_SendText(DEFAULT_CHAT_FRAME.editBox, 0)
    return
  end

  SendChatMessage(command, "SAY")
end

SlashCmdList["CULTMAK"] = function(msg)
  SendMakCommand(msg)
end
