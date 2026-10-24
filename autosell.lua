local source = [====[

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local player = Players.LocalPlayer
while not player do task.wait(); player = Players.LocalPlayer end
local playerGui = player:WaitForChild("PlayerGui")
local old = playerGui:FindFirstChild("ItemSellerGUI")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "ItemSellerGUI"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui
local alive, auto, busy = true, false, false
local revision = 0
local teleporting = false
local HttpService = game:GetService("HttpService")
local SCRIPT_FILE = "item-seller-gui.lua"

-- Store configs inside a dedicated executor Workspace folder.
-- Each Roblox account gets its own settings file inside that folder.
-- Example: workspace/MosquitoAutoSell/item-seller-settings-123456789.json
local CONFIG_FOLDER = "MosquitoAutoSell"
local userId = tostring(player.UserId)
local SETTINGS_FILE = CONFIG_FOLDER .. "/item-seller-settings-" .. userId .. ".json"

-- Create the config folder if the executor supports filesystem folders.
if type(isfolder) == "function" and type(makefolder) == "function" then
    if not isfolder(CONFIG_FOLDER) then
        pcall(function() makefolder(CONFIG_FOLDER) end)
    end
end

local saved = {}
if type(readfile) == "function" then
    local ok, data = pcall(function() return HttpService:JSONDecode(readfile(SETTINGS_FILE)) end)
    if ok and type(data) == "table" then saved = data end
end
-- Auto-sell is a persistent setting, just like the other GUI settings.
local savedAuto = saved.auto == true
local rarities = {"common", "uncommon", "rare", "epic", "legendary", "ultimate"}
local selected = {common=false, uncommon=false, rare=false, epic=false, legendary=false, ultimate=false}
local POWER_PER_UPGRADE = 10

local connections = {}
local function connect(signal, fn)
    local c = signal:Connect(fn)
    table.insert(connections, c)
    return c
end

local function create(kind, props, parent)
    local obj = Instance.new(kind)
    for k,v in pairs(props) do obj[k] = v end
    obj.Parent = parent
    return obj
end

local bg = Color3.fromRGB(23,26,34)
local card = Color3.fromRGB(35,40,51)
local ink = Color3.fromRGB(235,239,247)
local muted = Color3.fromRGB(159,170,190)
local blue = Color3.fromRGB(65,117,220)
local green = Color3.fromRGB(70,170,120)
local red = Color3.fromRGB(150,64,64)

local function label(parent, text, x,y,w,h,size)
    return create("TextLabel", {
        Text=text, Position=UDim2.fromOffset(x,y), Size=UDim2.new(w,0,0,h),
        BackgroundTransparency=1, TextColor3=ink, Font=Enum.Font.Gotham,
        TextSize=size or 13, TextXAlignment=Enum.TextXAlignment.Left
    },parent)
end

local function button(parent,text,x,y,w,h)
    local b = create("TextButton", {
        Text=text, Position=UDim2.new(x,0,0,y), Size=UDim2.new(w,-6,0,h),
        BackgroundColor3=card, BorderSizePixel=0, TextColor3=ink,
        Font=Enum.Font.GothamMedium, TextSize=12
    },parent)
    create("UICorner",{CornerRadius=UDim.new(0,7)},b)
    return b
end

local savedPosX = tonumber(saved.guiPosX) or 0.5
local savedPosY = tonumber(saved.guiPosY) or 0.5

-- Keep a sane base window size. The SIZE slider scales the entire GUI,
-- so old oversized guiSizeX/guiSizeY values from previous test builds
-- cannot make the window cover the whole screen.
local BASE_W, BASE_H = 560, 520
local MIN_SCALE, MAX_SCALE = 0.50, 0.90
local savedScale = tonumber(saved.guiScale)
if not savedScale then
    local oldW = tonumber(saved.guiSizeX)
    savedScale = oldW and math.clamp(oldW/BASE_W,MIN_SCALE,MAX_SCALE) or 0.78
end
savedScale = math.clamp(savedScale,MIN_SCALE,MAX_SCALE)

local frame = create("Frame", {
    AnchorPoint=Vector2.new(.5,.5), Position=UDim2.fromScale(savedPosX,savedPosY),
    Size=UDim2.fromOffset(BASE_W,BASE_H), BackgroundColor3=bg, BorderSizePixel=0
},gui)
local guiScale = create("UIScale",{Scale=savedScale},frame)
create("UICorner",{CornerRadius=UDim.new(0,12)},frame)


local header = label(frame,"Item auto-seller",16,0,.60,44,17)
header.Active = true
local minimize = button(frame,"Hide",.66,8,.17,28)
local close = button(frame,"Close",.84,8,.15,28)

-- GUI SIZE: fixed in the top bar so it is always reachable.
local sizeBar = create("Frame",{
    Position=UDim2.fromOffset(12,42),Size=UDim2.new(1,-24,0,28),
    BackgroundColor3=card,BorderSizePixel=0
},frame)
create("UICorner",{CornerRadius=UDim.new(0,7)},sizeBar)

local sizeLabel = create("TextLabel",{
    Position=UDim2.fromOffset(10,0),Size=UDim2.fromOffset(42,28),
    BackgroundTransparency=1,Text="SIZE",TextColor3=muted,
    Font=Enum.Font.GothamMedium,TextSize=10,
    TextXAlignment=Enum.TextXAlignment.Left
},sizeBar)

local sizeTrack = create("Frame",{
    Position=UDim2.fromOffset(50,10),Size=UDim2.new(1,-112,0,8),
    BackgroundColor3=ink,BorderSizePixel=0
},sizeBar)
create("UICorner",{CornerRadius=UDim.new(0,4)},sizeTrack)

local sizeFill = create("Frame",{
    Position=UDim2.fromScale(0,0),Size=UDim2.fromScale(0,1),
    BackgroundColor3=blue,BorderSizePixel=0
},sizeTrack)
create("UICorner",{CornerRadius=UDim.new(0,4)},sizeFill)

local sizeKnob = create("TextButton",{
    AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(0,.5),
    Size=UDim2.fromOffset(18,18),BackgroundColor3=ink,BorderSizePixel=0,
    Text="",AutoButtonColor=false
},sizeTrack)
create("UICorner",{CornerRadius=UDim.new(1,0)},sizeKnob)

local sizeValue = create("TextLabel",{
    Position=UDim2.new(1,-54,0,0),Size=UDim2.fromOffset(48,28),
    BackgroundTransparency=1,Text="",TextColor3=muted,
    Font=Enum.Font.GothamMedium,TextSize=10,
    TextXAlignment=Enum.TextXAlignment.Right
},sizeBar)


local restore = create("TextButton", {
    Position=UDim2.new(saved.restorePosX or 0, saved.restorePosOffsetX or 16,
        saved.restorePosY or 0, saved.restorePosOffsetY or 80),
    Size=UDim2.fromOffset(190,40),
    BackgroundColor3=card, BorderSizePixel=0, TextColor3=ink,
    Font=Enum.Font.GothamMedium, TextSize=13, Text="Seller · OFF · Open"
},gui)
create("UICorner",{CornerRadius=UDim.new(0,9)},restore)

local restoreMoved=false
local function setMinimized(value)
    frame.Visible=not value
    restore.Visible=value
end
connect(minimize.MouseButton1Click,function() setMinimized(true) end)
connect(restore.MouseButton1Click,function()
    if restoreMoved then
        restoreMoved=false
        return
    end
    setMinimized(false)
end)
setMinimized(true)

local body = create("ScrollingFrame",{
    Position=UDim2.fromOffset(12,76), Size=UDim2.new(1,-24,1,-88),
    BackgroundTransparency=1, BorderSizePixel=0, ScrollBarThickness=4,
    CanvasSize=UDim2.fromOffset(0,0), AutomaticCanvasSize=Enum.AutomaticSize.Y,
    ScrollingDirection=Enum.ScrollingDirection.Y
},frame)

label(body,"SELL RARITIES",0,0,1,22,12)
local rarityButtons = {}
for i,r in ipairs(rarities) do
    rarityButtons[r] = button(body,"",((i-1)%3)/3,28+math.floor((i-1)/3)*36,1/3,30)
end

label(body,"KEEP BY NAME + RARITY",0,106,1,24,12)
label(body,"Each row protects only the checked rarities. + adds a row; − removes it.",0,130,1,20,10).TextColor3=muted

local keepRows={}
local keepContainer=create("ScrollingFrame",{
    Position=UDim2.fromOffset(0,154),Size=UDim2.new(1,-8,0,190),
    BackgroundColor3=card,BorderSizePixel=0,ScrollBarThickness=5,
    CanvasSize=UDim2.new(),AutomaticCanvasSize=Enum.AutomaticSize.Y,
    ScrollingDirection=Enum.ScrollingDirection.Y
},body)
create("UIPadding",{PaddingLeft=UDim.new(0,8),PaddingRight=UDim.new(0,8),PaddingTop=UDim.new(0,8),PaddingBottom=UDim.new(0,8)},keepContainer)
create("UIListLayout",{Padding=UDim.new(0,7),SortOrder=Enum.SortOrder.LayoutOrder},keepContainer)

local function rebuildKeepRows()
    for _,child in ipairs(keepContainer:GetChildren()) do
        if child:IsA("Frame") then child:Destroy() end
    end
    for index,row in ipairs(keepRows) do
        local f=create("Frame",{
            Size=UDim2.new(1,-4,0,62),BackgroundColor3=bg,BorderSizePixel=0,LayoutOrder=index
        },keepContainer)
        create("UICorner",{CornerRadius=UDim.new(0,7)},f)
        row.frame=f
        row.nameBox=create("TextBox",{
            Position=UDim2.fromOffset(6,6),Size=UDim2.new(1,-86,0,25),
            BackgroundColor3=card,BorderSizePixel=0,Text=row.name or "",
            PlaceholderText="Item name",ClearTextOnFocus=false,TextColor3=ink,
            Font=Enum.Font.Gotham,TextSize=11
        },f)
        create("UICorner",{CornerRadius=UDim.new(0,5)},row.nameBox)
        local minus=create("TextButton",{
            Position=UDim2.new(1,-78,0,6),Size=UDim2.fromOffset(32,25),
            BackgroundColor3=card,BorderSizePixel=0,TextColor3=ink,
            Font=Enum.Font.GothamBold,TextSize=15,Text="−"
        },f)
        local plus=create("TextButton",{
            Position=UDim2.new(1,-40,0,6),Size=UDim2.fromOffset(32,25),
            BackgroundColor3=blue,BorderSizePixel=0,TextColor3=ink,
            Font=Enum.Font.GothamBold,TextSize=15,Text="+"
        },f)
        create("UICorner",{CornerRadius=UDim.new(0,5)},minus)
        create("UICorner",{CornerRadius=UDim.new(0,5)},plus)
        local width=1/#rarities
        for i,r in ipairs(rarities) do
            local b=create("TextButton",{
                Position=UDim2.new((i-1)*width,2,0,36),Size=UDim2.new(width,-4,0,20),
                BackgroundColor3=row.rarities[r] and blue or card,BorderSizePixel=0,
                Text=(row.rarities[r] and "✓ " or "○ ")..r,TextColor3=ink,
                Font=Enum.Font.GothamMedium,TextSize=9
            },f)
            create("UICorner",{CornerRadius=UDim.new(0,5)},b)
            connect(b.MouseButton1Click,function()
                row.rarities[r]=not row.rarities[r]
                revision=revision+1;rebuildKeepRows();updateButtons()
            end)
        end
        connect(row.nameBox:GetPropertyChangedSignal("Text"),function()
            row.name=row.nameBox.Text;revision=revision+1;updateButtons()
        end)
        connect(plus.MouseButton1Click,function()
            table.insert(keepRows,index+1,{name="",rarities={}})
            rebuildKeepRows();revision=revision+1;updateButtons()
        end)
        connect(minus.MouseButton1Click,function()
            if #keepRows<=1 then row.name="";row.rarities={} else table.remove(keepRows,index) end
            rebuildKeepRows();revision=revision+1;updateButtons()
        end)
    end
end
table.insert(keepRows,{name="",rarities={}})

label(body,"KEEP ARMOR BY POTENTIAL",0,358,1,24,12)
label(body,"Potential = current power + remaining upgrades × 10.",0,382,1,20,10).TextColor3=muted

local potentialRows={}
local potentialContainer=create("ScrollingFrame",{
    Position=UDim2.fromOffset(0,406),Size=UDim2.new(1,-8,0,170),
    BackgroundColor3=card,BorderSizePixel=0,ScrollBarThickness=5,
    CanvasSize=UDim2.new(),AutomaticCanvasSize=Enum.AutomaticSize.Y,
    ScrollingDirection=Enum.ScrollingDirection.Y
},body)
create("UIPadding",{PaddingLeft=UDim.new(0,8),PaddingRight=UDim.new(0,8),PaddingTop=UDim.new(0,8),PaddingBottom=UDim.new(0,8)},potentialContainer)
create("UIListLayout",{Padding=UDim.new(0,7),SortOrder=Enum.SortOrder.LayoutOrder},potentialContainer)

local function rebuildPotentialRows()
    for _,child in ipairs(potentialContainer:GetChildren()) do
        if child:IsA("Frame") then child:Destroy() end
    end
    for index,row in ipairs(potentialRows) do
        local f=create("Frame",{
            Size=UDim2.new(1,-4,0,54),BackgroundColor3=bg,BorderSizePixel=0,LayoutOrder=index
        },potentialContainer)
        create("UICorner",{CornerRadius=UDim.new(0,7)},f)
        row.frame=f
        row.nameBox=create("TextBox",{
            Position=UDim2.fromOffset(6,5),Size=UDim2.new(.40,-8,0,24),
            BackgroundColor3=card,BorderSizePixel=0,Text=row.name or "",
            PlaceholderText="Armor name",ClearTextOnFocus=false,TextColor3=ink,
            Font=Enum.Font.Gotham,TextSize=10
        },f)
        row.powerBox=create("TextBox",{
            Position=UDim2.new(.40,0,0,5),Size=UDim2.new(.25,-8,0,24),
            BackgroundColor3=card,BorderSizePixel=0,Text=row.power or "",
            PlaceholderText="Min power",ClearTextOnFocus=false,TextColor3=ink,
            Font=Enum.Font.Gotham,TextSize=10
        },f)
        create("UICorner",{CornerRadius=UDim.new(0,5)},row.nameBox)
        create("UICorner",{CornerRadius=UDim.new(0,5)},row.powerBox)
        local physical=create("TextButton",{
            Position=UDim2.new(.65,0,0,5),Size=UDim2.new(.10,-4,0,24),
            BackgroundColor3=row.type=="physical" and blue or card,BorderSizePixel=0,
            TextColor3=ink,Font=Enum.Font.GothamMedium,TextSize=8,Text="Physical"
        },f)
        local spell=create("TextButton",{
            Position=UDim2.new(.75,0,0,5),Size=UDim2.new(.10,-4,0,24),
            BackgroundColor3=row.type=="spell" and blue or card,BorderSizePixel=0,
            TextColor3=ink,Font=Enum.Font.GothamMedium,TextSize=8,Text="Spell"
        },f)
        local minus=create("TextButton",{
            Position=UDim2.new(1,-78,0,5),Size=UDim2.fromOffset(32,24),
            BackgroundColor3=card,BorderSizePixel=0,TextColor3=ink,
            Font=Enum.Font.GothamBold,TextSize=15,Text="−"
        },f)
        local plus=create("TextButton",{
            Position=UDim2.new(1,-40,0,5),Size=UDim2.fromOffset(32,24),
            BackgroundColor3=blue,BorderSizePixel=0,TextColor3=ink,
            Font=Enum.Font.GothamBold,TextSize=15,Text="+"
        },f)
        for _,b in ipairs({physical,spell,minus,plus}) do create("UICorner",{CornerRadius=UDim.new(0,5)},b) end
        connect(row.nameBox:GetPropertyChangedSignal("Text"),function() row.name=row.nameBox.Text;revision=revision+1;updateButtons() end)
        connect(row.powerBox:GetPropertyChangedSignal("Text"),function() row.power=row.powerBox.Text;revision=revision+1;updateButtons() end)
        connect(physical.MouseButton1Click,function() row.type="physical";rebuildPotentialRows();revision=revision+1;updateButtons() end)
        connect(spell.MouseButton1Click,function() row.type="spell";rebuildPotentialRows();revision=revision+1;updateButtons() end)
        connect(plus.MouseButton1Click,function()
            table.insert(potentialRows,index+1,{name="",power="",type=nil})
            rebuildPotentialRows();revision=revision+1;updateButtons()
        end)
        connect(minus.MouseButton1Click,function()
            if #potentialRows<=1 then row.name="";row.power="";row.type=nil else table.remove(potentialRows,index) end
            rebuildPotentialRows();revision=revision+1;updateButtons()
        end)
    end
end
table.insert(potentialRows,{name="",power="",type=nil})

label(body,"KEEP ABILITY",0,594,1,24,12)
label(body,"Amount 0 = OFF. Names entered = keep only those abilities; all other abilities are sold.",0,618,1,20,10).TextColor3=muted
local abilityAmount=create("TextBox",{
    Position=UDim2.fromOffset(0,644),Size=UDim2.new(.25,0,0,28),Text="0",
    ClearTextOnFocus=false,BackgroundColor3=card,BorderSizePixel=0,
    TextColor3=ink,Font=Enum.Font.Gotham,TextSize=12,PlaceholderText="Amount"
},body)
create("UICorner",{CornerRadius=UDim.new(0,6)},abilityAmount)
local abilityNames=create("TextBox",{
    Position=UDim2.new(.28,0,0,644),Size=UDim2.new(.72,-8,0,72),
    BackgroundColor3=card,BorderSizePixel=0,Text="",
    PlaceholderText="Ability names, one per line (blank = all abilities)",
    MultiLine=true,ClearTextOnFocus=false,TextColor3=ink,Font=Enum.Font.Gotham,
    TextSize=11,TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Top,TextWrapped=true
},body)
create("UICorner",{CornerRadius=UDim.new(0,6)},abilityNames)
create("UIPadding",{PaddingLeft=UDim.new(0,7),PaddingTop=UDim.new(0,6)},abilityNames)

label(body,"KEEP LEVEL + (0 = OFF)",0,730,.55,24,12)
local levelBox=create("TextBox",{
    Position=UDim2.new(.62,0,0,730),Size=UDim2.new(.36,0,0,28),Text="0",
    ClearTextOnFocus=false,BackgroundColor3=card,BorderSizePixel=0,TextColor3=ink,Font=Enum.Font.Gotham,TextSize=13
},body)
create("UICorner",{CornerRadius=UDim.new(0,6)},levelBox)
label(body,"SELL INTERVAL (SECONDS)",0,766,.55,24,12)
local intervalBox=create("TextBox",{
    Position=UDim2.new(.62,0,0,766),Size=UDim2.new(.36,0,0,28),Text="10",
    ClearTextOnFocus=false,BackgroundColor3=card,BorderSizePixel=0,TextColor3=ink,Font=Enum.Font.Gotham,TextSize=13
},body)
create("UICorner",{CornerRadius=UDim.new(0,6)},intervalBox)
local preview=button(body,"Preview only",0,806,.5,38)
preview.BackgroundColor3=blue
local toggle=button(body,"Auto-sell: OFF",.5,806,.5,38)
local status=label(body,"Preview is safe: it does not sell anything.",0,852,1,48,12)
status.TextWrapped=true
status.TextColor3=muted
local results=create("ScrollingFrame",{
    Position=UDim2.fromOffset(0,912),Size=UDim2.new(1,-8,0,420),BackgroundColor3=card,
    BorderSizePixel=0,ScrollBarThickness=5,CanvasSize=UDim2.new(),AutomaticCanvasSize=Enum.AutomaticSize.Y
},body)
create("UIPadding",{PaddingLeft=UDim.new(0,10),PaddingRight=UDim.new(0,10),PaddingTop=UDim.new(0,8),PaddingBottom=UDim.new(0,8)},results)
create("UIListLayout",{Padding=UDim.new(0,5),SortOrder=Enum.SortOrder.LayoutOrder},results)
local function row(text,color)
    create("TextLabel",{Size=UDim2.new(1,-8,0,0),AutomaticSize=Enum.AutomaticSize.Y,BackgroundTransparency=1,
        Text=text,TextWrapped=true,TextColor3=color or ink,TextSize=12,Font=Enum.Font.Gotham,
        TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Top,LayoutOrder=#results:GetChildren()},results)
end
row("Click Preview only to see your inventory decisions.",muted)
rebuildKeepRows()
rebuildPotentialRows()

local saveWarning=false
local restoringSettings=true

local function saveSettings()
    local level=tonumber(levelBox.Text)
    local interval=tonumber(intervalBox.Text)
    local amount=tonumber(abilityAmount.Text)
    local data={
        auto=auto == true,
        guiScale=guiScale.Scale,
        guiSizeX=math.floor(BASE_W*guiScale.Scale+0.5),
        guiSizeY=math.floor(BASE_H*guiScale.Scale+0.5),
        guiPosX=frame.Position.X.Scale,
        guiPosY=frame.Position.Y.Scale,
        restorePosX=restore.Position.X.Scale,
        restorePosY=restore.Position.Y.Scale,
        restorePosOffsetX=restore.Position.X.Offset,
        restorePosOffsetY=restore.Position.Y.Offset,
        level=level and level>=0 and level%1==0 and level or 0,
        interval=interval and interval>=1 and interval<math.huge and interval or 10,
        abilityAmount=amount and amount>=0 and amount%1==0 and amount or 0,
        abilityNames=abilityNames.Text,
        selected=selected,
        keepRows={},
        potentialRows={}
    }
    for _,r in ipairs(keepRows) do
        table.insert(data.keepRows,{name=r.name or "",rarities=r.rarities or {}})
    end
    for _,r in ipairs(potentialRows) do
        table.insert(data.potentialRows,{name=r.name or "",power=r.power or "",type=r.type})
    end
    saved=data
    if type(writefile)=="function" then
        local ok,err=pcall(function() writefile(SETTINGS_FILE,HttpService:JSONEncode(data)) end)
        if not ok and not saveWarning then
            saveWarning=true
            warn("Settings could not be saved: "..tostring(err))
        end
    end
end

function updateButtons()
    restore.Text=auto and "Seller · ON · Open" or "Seller · OFF · Open"
    toggle.Text=auto and "Auto-sell: ON" or "Auto-sell: OFF"
    toggle.BackgroundColor3=auto and red or card
    for r,b in pairs(rarityButtons) do
        b.Text=(selected[r] and "✓ " or "○ ")..r
        b.BackgroundColor3=selected[r] and blue or card
    end
    saveSettings()
end

local function changed()
    revision=revision+1
    if restoringSettings then
        return
    end
    updateButtons()
    status.Text="Settings changed and saved."
end

for r,b in pairs(rarityButtons) do
    connect(b.MouseButton1Click,function() selected[r]=not selected[r]; changed() end)
end
for _,box in ipairs({levelBox,abilityAmount,abilityNames,intervalBox}) do
    connect(box:GetPropertyChangedSignal("Text"),changed)
end

-- Restore saved primitive settings. GUI rows are restored separately below.
if type(saved.level)=="number" and saved.level>=0 and saved.level%1==0 then levelBox.Text=tostring(saved.level) end
if type(saved.interval)=="number" and saved.interval>=1 then intervalBox.Text=tostring(saved.interval) end
if type(saved.abilityAmount)=="number" and saved.abilityAmount>=0 then abilityAmount.Text=tostring(saved.abilityAmount) end
if type(saved.abilityNames)=="string" then abilityNames.Text=saved.abilityNames end
if type(saved.selected)=="table" then
    for _,r in ipairs(rarities) do
        if type(saved.selected[r])=="boolean" then selected[r]=saved.selected[r] end
    end
end

local function rebuildFromSaved()
    if type(saved.keepRows)=="table" and #saved.keepRows>0 then
        keepRows={}
        for _,r in ipairs(saved.keepRows) do
            table.insert(keepRows,{name=type(r.name)=="string" and r.name or "",rarities=type(r.rarities)=="table" and r.rarities or {}})
        end
        rebuildKeepRows()
    end
    if type(saved.potentialRows)=="table" and #saved.potentialRows>0 then
        potentialRows={}
        for _,r in ipairs(saved.potentialRows) do
            local t=(r.type=="physical" or r.type=="spell") and r.type or nil
            table.insert(potentialRows,{name=type(r.name)=="string" and r.name or "",
                power=type(r.power)=="string" and r.power or tostring(r.power or ""),type=t})
        end
        rebuildPotentialRows()
    end
end
rebuildFromSaved()
restoringSettings=false

local categories={{"weapons","weapon"},{"helmets","helmet"},{"chests","chest"},{"abilities","ability"}}

-- Normalize names without relying on the global string.gsub/gmatch functions.
-- This keeps comparisons case-insensitive while preserving the item name text.
local function normalize(value)
    local s=tostring(value or ""):lower()
    local startPos=1
    local endPos=#s
    while startPos<=endPos and s:sub(startPos,startPos)==" " do
        startPos=startPos+1
    end
    while endPos>=startPos and s:sub(endPos,endPos)==" " do
        endPos=endPos-1
    end
    if startPos>endPos then return "" end
    return s:sub(startPos,endPos)
end

local function checkAbilityEquipped(item)
    if type(item.equipped)=="table" then
        for _,v in pairs(item.equipped) do if v==true then return true end end
        return false
    end
    return item.equipped==true
end

local function readStat(item,fields)
    for _,field in ipairs(fields) do
        local raw=item[field]
        if raw~=nil then
            local n=tonumber(raw)
            if n and n==n and n>=0 and n<math.huge then return n end
            return nil
        end
    end
    return nil
end

local STAT_FIELDS={
    physical={"physicalPower","physicalDamage"},
    spell={"spellPower","SpellPower","spellDamage","SpellDamage"},
    total={"maxUpgrades","MaxUpgrades","maximumUpgrades","MaximumUpgrades","totalUpgrades","TotalUpgrades"},
    used={"currentUpgrade","CurrentUpgrade","currentUpgrades","CurrentUpgrades","upgradesUsed","UpgradesUsed"}
}

local function armorPotential(item,powerType,ppu)
    local power=readStat(item,STAT_FIELDS[powerType])
    local total=readStat(item,STAT_FIELDS.total)
    local used=readStat(item,STAT_FIELDS.used)
    if not power or not total or not used or used>total then return nil end
    return power+(total-used)*ppu
end

local function nameMatches(item,target)
    local n=normalize(target)
    if n=="" then return false end
    for _,field in ipairs({"name","abilityName","itemName","gearName"}) do
        if type(item[field])=="string" and normalize(item[field])==n then return true end
    end
    return false
end

local function keepByNameRarity(item)
    if type(item)~="table" or type(item.name)~="string" then return false end
    local name=normalize(item.name)
    local rarity=type(item.rarity)=="string" and normalize(item.rarity) or ""
    if name=="" or rarity=="" then return false end
    for _,r in ipairs(keepRows) do
        if normalize(r.name)==name and r.rarities[rarity]==true then return true end
    end
    return false
end

local function potentialRule(item,ppu)
    if type(item)~="table" then return false,true end
    for _,r in ipairs(potentialRows) do
        local n=normalize(r.name)
        local threshold=tonumber(r.power)
        if n~="" and threshold and threshold>=0 and (r.type=="physical" or r.type=="spell") and nameMatches(item,n) then
            local p=armorPotential(item,r.type,ppu)
            if p==nil then
                return true,true -- safe: rule matched but data cannot be evaluated
            end
            if p>=threshold then return true,false end
        end
    end
    return false,false
end

local function parseAbilityNames()
    local t={}
    local text=tostring(abilityNames.Text or "")
    -- Avoid string.gmatch/gsub entirely. Split is a Luau string method.
    local lines=text:split("\n")
    for _,line in ipairs(lines) do
        local n=normalize(line)
        if n~="" then t[n]=true end
    end
    return t
end

local function settings()
    local level=tonumber(levelBox.Text)
    local interval=tonumber(intervalBox.Text)
    local amount=tonumber(abilityAmount.Text)
    if not level or level<0 or level%1~=0 then return nil,"Enter a whole keep level of 0 or higher." end
    if not interval or interval<1 or interval==math.huge then return nil,"Enter an interval of at least 1 second." end
    if not amount or amount<0 or amount%1~=0 then return nil,"Ability amount must be a whole number 0 or higher." end
    return {level=level,interval=interval,abilityAmount=amount,abilityNames=parseAbilityNames()}
end

local function reason(item,isAbility,cfg,abilityCounts)
    if type(item)~="table" then return "unrecognized data" end
    if type(item.name)~="string" or normalize(item.name)=="" then return "missing name" end

    if isAbility and checkAbilityEquipped(item) then return "equipped" end
    if not isAbility and item.equipped==true then return "equipped" end
    if not isAbility and item.equipped~=false then return "unknown equipped status" end

    -- Explicit item+rarity keep always beats Sell Rarity.
    if keepByNameRarity(item) then return "keep by name + rarity" end

    -- Armor potential also beats Sell Rarity and Keep Level.
    local pkeep,unknown=potentialRule(item,POWER_PER_UPGRADE)
    if pkeep then return unknown and "potential data unavailable (safe keep)" or "armor potential" end

    if isAbility and cfg.abilityAmount>0 then
        local names=cfg.abilityNames
        if next(names)==nil then
            -- Empty list means keep N of every ability; handled in scan because
            -- this decision needs a per-name count.
        else
            local n=normalize(item.name)
            if names[n] then
                local used=abilityCounts[n] or 0
                if used<cfg.abilityAmount then
                    abilityCounts[n]=used+1
                    return "keep ability quota"
                end
                return nil
            end
            return "ability not listed"
        end
    end

    if type(item.rarity)~="string" or not selected[item.rarity:lower()] then
        -- Not selected for sale, so it is protected from Sell Rarity.
        return "protected / rarity not selected"
    end

    if cfg.level>0 then
        local n=tonumber(item.levelReq)
        if not n then return "unknown level" end
        if n>=cfg.level then return "level "..cfg.level.."+" end
    end

    return nil
end


-- ===== Sell logic ported from the Harvard script =====
local LOBBY_PLACE=77649408247578
local SELL_DELAY=1          -- seconds between items when selling inside a dungeon
local SELL_CHECK_AFTER=2    -- seconds before re-reading the bag to verify
local WORN_HOURS=24         -- abilities equipped within this window are kept
local WORN_FILE=CONFIG_FOLDER.."/worn-"..userId..".json"
local scriptStart=os.clock()

local function inLobby() return game.PlaceId==LOBBY_PLACE end

-- In the lobby, wait for the account data to load before any automatic sale.
local function lobbyReady()
    if not inLobby() then return true end
    if os.clock()-scriptStart<10 then return false end
    local stats=player:FindFirstChild("leaderstats")
    local lvl=stats and stats:FindFirstChild("Level")
    return lvl~=nil and (tonumber(lvl.Value) or 0)>1
end

local worn={}
if type(readfile)=="function" then
    local okW,dataW=pcall(function() return HttpService:JSONDecode(readfile(WORN_FILE)) end)
    if okW and type(dataW)=="table" then
        for k,v in pairs(dataW) do
            if type(k)=="string" and tonumber(v) then worn[k]=tonumber(v) end
        end
    end
end

local function wornKey(item)
    local uid=item.UniqueItemID
    if type(uid)=="string" and uid~="" and uid~="none" then return "uid:"..uid end
    return "name:"..tostring(item.name):lower()
end

local function noteWorn(inv)
    if type(inv)~="table" or type(inv.abilities)~="table" then return end
    local now,dirty=os.time(),false
    for _,item in pairs(inv.abilities) do
        if type(item)=="table" and type(item.name)=="string" and type(item.equipped)=="table" then
            local on=false
            for _,v in pairs(item.equipped) do if v==true then on=true end end
            local k=wornKey(item)
            if on and (worn[k]==nil or now-worn[k]>600) then worn[k]=now; dirty=true end
        end
    end
    if dirty then
        for k,t in pairs(worn) do
            if now-t>2*WORN_HOURS*3600 then worn[k]=nil end
        end
        if type(writefile)=="function" then
            pcall(function() writefile(WORN_FILE,HttpService:JSONEncode(worn)) end)
        end
    end
end

local function wasWorn(item)
    local t=worn[wornKey(item)]
    return t~=nil and os.time()-t<=WORN_HOURS*3600
end

local function countRemaining(inv,uids)
    local n=0
    for _,c in ipairs(categories) do
        local group=inv[c[1]]
        if type(group)=="table" then
            for _,it in pairs(group) do
                if type(it)=="table" and type(it.UniqueItemID)=="string" and uids[it.UniqueItemID] then n=n+1 end
            end
        end
    end
    return n
end

local function scan(cfg)
    local remotes=ReplicatedStorage:FindFirstChild("remotes")
    local reload=remotes and remotes:FindFirstChild("reloadInvy")
    if not reload then error("Inventory remote not found.") end
    local inv=reload:InvokeServer()
    if type(inv)~="table" then error("Inventory could not be read.") end
    pcall(noteWorn,inv)

    local payload={weapon={},helmet={},chest={},ability={}}
    local kept,sold={},{}
    local kc,sc=0,0
    local abilityCounts={}
    local saleItems,saleUids,uidCount={}, {}, 0
    local function addSell(catKey,id,item)
        table.insert(payload[catKey],id)
        local uid=type(item)=="table" and item.UniqueItemID or nil
        if type(uid)~="string" or uid=="" then uid=nil end
        table.insert(saleItems,{cat=catKey,id=id,uid=uid})
        if uid and not saleUids[uid] then saleUids[uid]=true; uidCount=uidCount+1 end
    end

    -- First pass: explicit ability names get their quotas. For blank names,
    -- every ability gets a quota independently.
    local abilityItems={}
    if type(inv.abilities)=="table" then
        for key,item in pairs(inv.abilities) do
            if type(item)=="table" then table.insert(abilityItems,{key=key,item=item}) end
        end
    end
    table.sort(abilityItems,function(a,b) return tostring(a.key)<tostring(b.key) end)

    local function process(catName,catKey,items)
        if items~=nil and type(items)~="table" then error("Invalid inventory category: "..catName) end
        for key,item in pairs(items or {}) do
            local why
            if catKey=="ability" then
                -- Ability quota is applied only to abilities that are not
                -- explicitly kept by another rule.
                if type(item)=="table" and checkAbilityEquipped(item) then
                    why="equipped"
                elseif keepByNameRarity(item) then
                    why="keep by name + rarity"
                else
                    local pkeep,unknown=potentialRule(item,POWER_PER_UPGRADE)
                    if pkeep then
                        why=unknown and "potential data unavailable (safe keep)" or "armor potential"
                    else
                        local amount=cfg.abilityAmount
                        if amount>0 then
                            local listed=next(cfg.abilityNames)~=nil
                            local n=type(item)=="table" and normalize(item.name) or ""
                            local applies=(not listed) or cfg.abilityNames[n]
                            if applies and n~="" then
                                local used=abilityCounts[n] or 0
                                if used<amount then
                                    abilityCounts[n]=used+1
                                    why="keep ability quota"
                                end
                            elseif listed then
                                why="ability not listed"
                            end
                        end
                    end
                end
            else
                why=reason(item,false,cfg,abilityCounts)
            end

            local id
            if type(key)=="string" then
                id=tonumber(tostring(key):match("^"..catKey.."_(%d+)$"))
            end
            local text=tostring(key)
            if type(item)=="table" then
                text=tostring(item.name or key).." · "..tostring(item.rarity or "?").." · Lv "..tostring(item.levelReq or "?")
            end

            if why then
                text=text.." — "..why
                kept[text]=(kept[text] or 0)+1
                kc=kc+1
            else
                if type(item)=="table" and item.equipped==true then
                    why="equipped"
                    kept[text.." — equipped"]=(kept[text.." — equipped"] or 0)+1
                    kc=kc+1
                elseif type(item)=="table" and item.equipped~=false and catKey~="ability" then
                    kept[text.." — unknown equipped status"]=(kept[text.." — unknown equipped status"] or 0)+1
                    kc=kc+1
                elseif type(item)=="table" and type(item.rarity)~="string" then
                    kept[text.." — unknown rarity"]=(kept[text.." — unknown rarity"] or 0)+1
                    kc=kc+1
                elseif not id then
                    kept[text.." — unknown item ID"]=(kept[text.." — unknown item ID"] or 0)+1
                    kc=kc+1
                else
                    sold[text]=(sold[text] or 0)+1
                    sc=sc+1
                    addSell(catKey,id,item)
                end
            end
        end
    end

    process("weapons","weapon",inv.weapons)
    process("helmets","helmet",inv.helmets)
    process("chests","chest",inv.chests)

    -- Abilities: when names are listed, only listed abilities get the quota;
    -- every other ability is explicitly sold. When names are blank, the quota
    -- applies independently to every ability name.
    local listedAbilityNames = next(cfg.abilityNames) ~= nil
    for _,entry in ipairs(abilityItems) do
        local key,item=entry.key,entry.item
        local why=nil
        local forceSellReason=nil

        if checkAbilityEquipped(item) then
            why="equipped"
        elseif wasWorn(item) then
            why="recently worn ("..WORN_HOURS.."h)"
        elseif keepByNameRarity(item) then
            why="keep by name + rarity"
        else
            local pkeep,unknown=potentialRule(item,POWER_PER_UPGRADE)
            if pkeep then
                why=unknown and "potential data unavailable (safe keep)" or "armor potential"
            elseif cfg.abilityAmount>0 then
                local n=normalize(item.name)
                if n=="" then
                    forceSellReason="missing ability name"
                elseif listedAbilityNames and not cfg.abilityNames[n] then
                    forceSellReason="ability not listed"
                else
                    local used=abilityCounts[n] or 0
                    if used<cfg.abilityAmount then
                        abilityCounts[n]=used+1
                        why="keep ability quota"
                    else
                        forceSellReason="ability quota exceeded"
                    end
                end
            end
        end

        local id=type(key)=="string" and tonumber(tostring(key):match("^ability_(%d+)$")) or nil
        local text=tostring(item.name or key).." · "..tostring(item.rarity or "?").." · Lv "..tostring(item.levelReq or "?")

        if why then
            kept[text] = (kept[text] or 0)+1
            kc=kc+1
        elseif forceSellReason then
            if id then
                sold[text.." — "..forceSellReason]=(sold[text.." — "..forceSellReason] or 0)+1
                sc=sc+1
                addSell("ability",id,item)
            else
                kept[text.." — unknown item ID"]=(kept[text.." — unknown item ID"] or 0)+1
                kc=kc+1
            end
        elseif not id then
            kept[text.." — unknown item ID"]=(kept[text.." — unknown item ID"] or 0)+1
            kc=kc+1
        elseif type(item.rarity)~="string" then
            kept[text.." — unknown rarity"]=(kept[text.." — unknown rarity"] or 0)+1
            kc=kc+1
        elseif selected[item.rarity:lower()] then
            sold[text]=(sold[text] or 0)+1
            sc=sc+1
            addSell("ability",id,item)
        else
            kept[text.." — rarity not selected"]=(kept[text.." — rarity not selected"] or 0)+1
            kc=kc+1
        end
    end

    return {payload=payload,items=saleItems,uids=saleUids,uidCount=uidCount,kept=kept,sold=sold,kc=kc,sc=sc}
end

local function showGroup(title,group,count,color)
    row(title.." · "..count,color)
    local keys={}
    for k in pairs(group) do table.insert(keys,k) end
    table.sort(keys)
    if #keys==0 then row("None",muted) end
    for _,k in ipairs(keys) do row(group[k].."× "..k) end
end

-- Sells the planned items the way the Harvard script does:
--  lobby   -> one request, items as "id:uniqueId"
--  dungeon -> one item at a time (plain ids), SELL_DELAY apart
-- then re-reads the bag to confirm how many actually went.
local function executeSale(data,version)
    local remotes=ReplicatedStorage:FindFirstChild("remotes")
    local sellRemote=remotes and remotes:FindFirstChild("sellItemEvent")
    local reload=remotes and remotes:FindFirstChild("reloadInvy")
    if not sellRemote then error("Sell remote not found.") end
    local asked=#data.items

    if inLobby() then
        local packet={weapon={},helmet={},chest={},ability={}}
        for _,it in ipairs(data.items) do
            table.insert(packet[it.cat],tostring(it.id)..":"..(it.uid or "none"))
        end
        sellRemote:FireServer(packet)
    else
        for i,it in ipairs(data.items) do
            if not alive or not auto or teleporting then
                return nil,asked,"Sale stopped after "..(i-1).." of "..asked.." items."
            end
            if revision~=version then
                return nil,asked,"Settings changed; sale stopped after "..(i-1).." of "..asked.." items."
            end
            local packet={weapon={},helmet={},chest={},ability={}}
            packet[it.cat]={it.id}
            status.Text="Selling "..i.."/"..asked.."…"
            pcall(function() sellRemote:FireServer(packet) end)
            task.wait(SELL_DELAY)
        end
    end

    if not reload or data.uidCount~=asked then
        return nil,asked,"Sale requested for "..asked.." items (not verified)."
    end
    task.wait(SELL_CHECK_AFTER)
    local okInv,inv=pcall(function() return reload:InvokeServer() end)
    if not okInv or type(inv)~="table" then
        return nil,asked,"Sale requested for "..asked.." items; could not re-open the bag to check."
    end
    return math.max(0,asked-countRemaining(inv,data.uids)),asked
end

local function perform(sell)
    if busy or not alive or teleporting then return end
    local cfg,err=settings()
    if not cfg then updateButtons(); status.Text=err; return end
    busy=true
    preview.AutoButtonColor=false
    local version=revision
    status.Text="Reading inventory…"
    local ok,data=pcall(scan,cfg)
    local function finish() busy=false; preview.AutoButtonColor=true end
    if not alive or teleporting then finish(); return end
    if version~=revision then finish(); status.Text="Settings changed during scan. Preview again."; return end
    if not ok then
        finish()
        updateButtons()
        status.Text="Scan failed: "..tostring(data)
        return
    end

    for _,child in ipairs(results:GetChildren()) do
        if child:IsA("TextLabel") then child:Destroy() end
    end
    showGroup("WOULD KEEP",data.kept,data.kc,green)
    showGroup("WOULD SELL",data.sold,data.sc,Color3.fromRGB(247,185,111))
    results.CanvasPosition=Vector2.new(0,0)

    if sell and auto then
        if data.sc==0 then finish(); status.Text="Nothing to sell. Keeping "..data.kc.." items."; return end
        local sent,gone,asked,msg=pcall(executeSale,data,version)
        finish()
        if not alive then return end
        if not sent then
            updateButtons()
            saveSettings()
            status.Text="Sale request failed: "..tostring(gone)
        elseif msg then
            status.Text=msg
        elseif gone==0 then
            status.Text="The game sold nothing ("..asked.." asked)."
        else
            status.Text="Sold "..gone.." of "..asked.." items; keeping "..data.kc.."."
        end
    else
        finish()
        status.Text="Preview: "..data.sc.." would sell; "..data.kc.." would remain. Nothing sold."
    end
end

connect(preview.MouseButton1Click,function()
    if busy then
        status.Text="Inventory scan is already running. Please wait."
        return
    end

    updateButtons()
    status.Text="Starting preview…"

    task.spawn(function()
        local ok,err=pcall(function()
            perform(false)
        end)
        if not ok and alive then
            busy=false
            status.Text="Preview failed: "..tostring(err)
            warn("Item auto-seller preview failed: "..tostring(err))
        end
    end)
end)

connect(toggle.MouseButton1Click,function()
    if auto then
        auto=false
        updateButtons()
        saveSettings()
        status.Text="Auto-sell stopped and saved."
        return
    end
    local cfg,err=settings()
    if not cfg then status.Text=err; return end
    auto=true
    updateButtons()
    saveSettings()
    status.Text="Auto-sell enabled and saved. It will restore automatically next time."
end)

local queueTeleport = queue_on_teleport or queueonteleport or (syn and syn.queue_on_teleport)
local queued=false
connect(player.OnTeleport,function(state)
    if state==Enum.TeleportState.Failed then
        teleporting=false
        status.Text="Teleport failed. Previous auto-sell setting retained."
        return
    end
    teleporting=true
    revision=revision+1
    setMinimized(true)
    saveSettings()
    if not queued and type(queueTeleport)=="function" then
        local ok,err=pcall(queueTeleport,[[
            if not game:IsLoaded() then game.Loaded:Wait() end
            local ok,err=pcall(function()
                local source=readfile("item-seller-gui.lua")
                local fn,problem=loadstring(source)
                assert(fn,problem)
                fn()
            end)
            if not ok then warn("Auto-seller teleport restart failed: "..tostring(err)) end
        ]])
        queued=ok
        if not ok then warn("Could not queue auto-seller: "..tostring(err)) end
    elseif type(queueTeleport)~="function" then
        warn("Teleport restart unavailable. Re-run the saved script after teleport; it will open minimized.")
    end
end)

local function cleanup()
    saveSettings()
    alive=false
    auto=false
    for _,c in ipairs(connections) do c:Disconnect() end
end
connect(gui.Destroying,cleanup)
connect(close.MouseButton1Click,function() auto=false; saveSettings(); gui:Destroy() end)

local dragging,start,position
connect(header.InputBegan,function(input)
    if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
        dragging=input; start=input.Position; position=frame.Position
    end
end)

local restoreDragging,restoreStart,restorePosition
connect(restore.InputBegan,function(input)
    if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
        restoreDragging=input
        restoreStart=input.Position
        restorePosition=restore.Position
        restoreMoved=false
    end
end)

local resizing=false
local resizeInput=nil

local function scaleFromInput(input)
    local x=input.Position.X
    local left=sizeTrack.AbsolutePosition.X
    local width=sizeTrack.AbsoluteSize.X
    if width<=0 then return MIN_SCALE end
    local alpha=math.clamp((x-left)/width,0,1)
    return MIN_SCALE+(MAX_SCALE-MIN_SCALE)*alpha
end

local function applyGuiScale(scale, save)
    scale=math.clamp(scale,MIN_SCALE,MAX_SCALE)
    guiScale.Scale=scale
    local alpha=(scale-MIN_SCALE)/(MAX_SCALE-MIN_SCALE)
    sizeFill.Size=UDim2.new(alpha,0,1,0)
    sizeKnob.Position=UDim2.new(alpha,0,.5,0)
    sizeValue.Text=("%d%%"):format(math.floor(scale*100+0.5))
    if save then saveSettings() end
end

local function beginResize(input)
    if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
        resizing=true
        resizeInput=input
        applyGuiScale(scaleFromInput(input),false)
    end
end

connect(sizeTrack.InputBegan,beginResize)
connect(sizeKnob.InputBegan,beginResize)

connect(UserInputService.InputChanged,function(input)
    if dragging and (input==dragging or input.UserInputType==Enum.UserInputType.MouseMovement) then
        local delta=input.Position-start
        frame.Position=UDim2.new(position.X.Scale,position.X.Offset+delta.X,
            position.Y.Scale,position.Y.Offset+delta.Y)
    end

    if restoreDragging and (input==restoreDragging or input.UserInputType==Enum.UserInputType.MouseMovement) then
        local delta=input.Position-restoreStart
        if math.abs(delta.X)>3 or math.abs(delta.Y)>3 then restoreMoved=true end
        restore.Position=UDim2.new(restorePosition.X.Scale,restorePosition.X.Offset+delta.X,
            restorePosition.Y.Scale,restorePosition.Y.Offset+delta.Y)
    end

    if resizing and (input==resizeInput or input.UserInputType==Enum.UserInputType.MouseMovement or input.UserInputType==Enum.UserInputType.Touch) then
        applyGuiScale(scaleFromInput(input),false)
    end
end)

connect(UserInputService.InputEnded,function(input)
    if input==dragging then
        dragging=nil
        saveSettings()
    end
    if input==restoreDragging then
        restoreDragging=nil
        saveSettings()
    end
    if resizing and (input==resizeInput or input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch) then
        resizing=false
        resizeInput=nil
        saveSettings()
    end
end)

-- Initialize the slider from the saved GUI scale.
task.defer(function()
    applyGuiScale(savedScale,false)
end)

-- Restore the last Auto-sell state after the GUI is created.
auto = savedAuto
updateButtons()
if auto then
    status.Text="Auto-sell restored from saved settings."
end

task.spawn(function()
    local nextScan=0
    while alive do
        if auto and not teleporting and not busy and os.clock()>=nextScan and lobbyReady() then
            perform(true)
            local cfg=settings()
            nextScan=os.clock()+(cfg and cfg.interval or 10)
        elseif not auto then
            nextScan=0
        end
        task.wait(.2)
    end
end)
]====]
local ok,err=pcall(function()
    assert(type(writefile)=="function", "writefile unavailable")
    writefile("item-seller-gui.lua",source)
end)
if not ok then warn("Teleport script could not be saved: "..tostring(err)) end
local run,problem=loadstring(source)
assert(run,problem)
run()
