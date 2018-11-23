JSON = require("JSON")

local fn = "C:\\Temp\\colorout.json"
win.DeleteFile(fn)

local editorfn = editor.GetFileName(nil)

Keys("CtrlF10 F2") -- Focus on file; save
if Area.Dialog then return end -- Error or "Enter file name" prompt
Keys("F12 1") -- Switch windows
if not Area.Shell then return end

local item = panel.GetCurrentPanelItem(nil, 1)
local itemfn = nil
if item then
  itemfn = item.FileName
end
if not itemfn or itemfn == ".." then
  itemfn = editorfn
  item = nil
end
local extension = itemfn:match("%.(%w+)$"):lower()

if extension=="d" then
  print("dcheck ")
  if item then
    Keys("CtrlEnter")
  else
    print(itemfn)
  end
else
  if not item then
    print(itemfn)
  end
end
Keys("Enter")

Keys("AltF8 ShiftDel Esc") -- Remove from history

--Keys("F4")
--if Area.Dialog then -- Open existing or new instance?
--  Keys("Enter")
--end
--if not Area.Editor then return end

--editor.Editor(itemfn, nil, nil, nil, nil, nil, EF_OPENMODE_USEEXISTING)
Keys("F12 End Enter")


local file = io.open(fn)
if not file then return end

local items = {}
for line in file:lines() do
  local entry = JSON:decode(line)
  entry.text = entry.message
  table.insert(items, entry)
end
file:close()
if next(items) == nil then return end

local answer = far.Menu({Title="Compilation result"}, items)
if not answer then return end

function goTo(file, line, column, title)
  Keys("ShiftF4")
  print(file)
  Keys("Enter")
  if Area.Dialog then -- Open existing or new instance?
    Keys("Enter")
  end

  editor.SetPosition(nil, line, column=="" and 1 or tonumber(column))
  if (title) then
    editor.SetTitle(nil, title)
  end
end

local info = editor.GetInfo(nil)
if answer.fixes then
  items = {}
  for k, v in pairs(JSON:decode(answer.fixes)) do
    table.insert(items, {cmd=v, text=k})
  end
  table.insert(items, {text="Go to error", cmd={{command="goto", line=answer.line, char=answer.column}}})
  local title = "Select action"
  if answer.id then
    title = answer.id
  end
  item = far.Menu({Title=title}, items)
  if not item then return end
  for i, cmd in ipairs(item.cmd) do
    if cmd.command == "goto" then
      goTo(answer.file, cmd.line, cmd.char, nil)
    elseif cmd.command == "insert" then
      print(cmd.text)
    elseif cmd.command == "return" then
      local offset = tonumber(cmd.offset)
      editor.SetPosition(
        nil,
	info.CurLine + offset,
	info.CurPos,
	info.CurTabPos,
	--info.TopScreenLine and info.TopScreenLine+offset or 0,
	info.TopScreenLine+offset,
	info.LeftPos
      )
    else
      assert(nil, "Unknown command: " .. cmd.command)
    end
  end
else
  goTo(answer.file, answer.line, answer.column, answer.text)
end
