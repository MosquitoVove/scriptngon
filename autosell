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
    status.Text="Settings changed and saveystal Blade|w|n|13|p",
    "Enchanted Demonic Greataxe|w|n|18|p",
    "Enchanted Sea Axes|w|n|2|s",
    "Enchanted Sea Daggers|w|n|2|s",
    "Enchanted Serpent Daggers|w|n|2|s",
    "Enchanted Shard Dual Blade|w|n|7|p",
    "Enchanted Shard Spelldagger|w|n|7|s",
    "Enchanted Shard Staff|w|n|7|s",
    "Enchanted Shard War Axe|w|n|7|p",
    "Enchanted Shuriken|a|e|15|d",
    "Enchanted Spinning Blades|a|e|13|d",
    "Enchanted Sword|w|n|5|p",
    "Energized Spell Dagger|w|n|12|s",
    "Energy Orb|a|e|12|d",
    "Enhanced Inner Focus|a|l|2|b",
    "Enhanced Inner Rage|a|l|2|b",
    "Ethereal Greataxe|w|n|10|p",
    "Explosive Mine|a|e|12|d",
    "Explosive Punch|a|e|16|d",
    "Fallen Guardian Armor|c|n|1|g",
    "Fallen Guardian Helmet|h|n|1|g",
    "Fallen Mage Armor|c|n|1|m",
    "Fallen Mage Helmet|h|n|1|m",
    "Fallen Warrior Armor|c|n|1|w",
    "Fallen Warrior Helmet|h|n|1|w",
    "Fallen's Battlestaff|w|n|1|s",
    "Fallen's Blade|w|n|1|p",
    "Fallen's Halberd|w|n|1|p",
    "Fallen's Spellblades|w|n|1|s",
    "File:Fungal Guardian Armor|c|n|7|g",
    "Fire and Ice Staff|w|n|10|s",
    "Fire Bomb|a|u|20|d",
    "Fireball|a|c|4|d",
    "Flame Cyclone|a|e|15|d",
    "Flame Shuriken|a|e|11|d",
    "Flame Staff|w|n|5|s",
    "Flame Step|a|c|0|d",
    "Flame Strike|a|r|11|d",
    "Focus Beam|a|e|12|d",
    "Forest Vine Hatchet|w|n|7|p",
    "Forest Vine Spellblade|w|n|7|s",
    "Forgotten Army|a|e|17|d",
    "Forgotten Guardian Armor|c|n|21|g",
    "Forgotten Guardian Helmet|h|n|21|g",
    "Forgotten Mage Hood|h|n|21|m",
    "Forgotten Mage Robes|c|n|21|m",
    "Forgotten Warrior Armor|c|n|21|w",
    "Forgotten Warrior Helmet|h|n|21|w",
    "Frost Cone|a|r|11|d",
    "Frost Giant Greataxe|w|n|11|p",
    "Frost Maul|w|n|20|p",
    "Frostbound Guardian Armor|c|n|20|g",
    "Frostbound Guardian Helmet|h|n|20|g",
    "Frostbound Mage Cloak|h|n|20|m",
    "Frostbound Mage Robes|c|n|20|m",
    "Frostbound Warrior Armor|c|n|20|w",
    "Frostbound Warrior Helmet|h|n|20|w",
    "Frostshard Battle Axe|w|n|20|p",
    "Frostshard Greatstaff|w|n|20|s",
    "Frostshard Hammer|w|n|20|p",
    "Frostshard Lance|w|n|20|s",
    "Frostshard Trident|w|n|20|s",
    "Frostshard Twinblades|w|n|20|p",
    "Frostwarden|w|l|20|s",
    "Frosty Staff|w|n|20|s",
    "Frozen Greatsword|w|n|20|p",
    "Frozen Lord's Greatsword|w|n|20|p",
    "Frozen Spelldaggers|w|n|20|s",
    "Fungal Guardian Helmet|h|n|7|g",
    "Fungal Lance|w|n|7|p",
    "Fungal Mage Armor|c|n|7|m",
    "Fungal Mage Helmet|h|n|7|m",
    "Fungal Pike|w|n|7|s",
    "Fungal Poison|a|r|7|d",
    "Fungal Staff|w|n|7|s",
    "Fungal Warhammer|w|n|7|p",
    "Fungal Warrior Armor|c|n|7|w",
    "Fungal Warrior Helmet|h|n|7|w",
    "Fusion Greatsword|w|n|16|p",
    "Fusion Magic Keyblade|w|n|3|s",
    "Galactic Dual Blades|w|l|12|p",
    "Galactic Pike|w|l|12|s",
    "Gale Barrage|a|e|11|d",
    "Gale Slice|a|u|20|d",
    "Geyser|a|e|11|d",
    "Ghostly Cannon Barrage|a|u|13|d",
    "Ghostly Greataxe|w|n|5|p",
    "Ghostly Rampage|a|r|15|d",
    "Ghoul Slayer|w|n|5|p",
    "Giant Royal Axe|w|n|17|p",
    "Gildenscale Guardian Armor|c|n|9|g",
    "Gildenscale Guardian Helmet|h|n|9|g",
    "Gildenscale Mage Armor|c|n|9|m",
    "Gildenscale Mage Helmet|h|n|9|m",
    "Gildenscale Oath And Aegis|w|l|9|p",
    "Gildenscale Warrior Armor|c|n|9|w",
    "Gildenscale Warrior Helmet|h|n|9|w",
    "Glacial Blows|a|r|10|d",
    "Glacial Greatsword|w|n|20|p",
    "Glorious Guardian Armor|c|n|18|g",
    "Glorious Guardian Helmet|h|n|18|g",
    "Glorious Mage Armor|c|n|18|m",
    "Glorious Mage Helmet|h|n|18|m",
    "Glorious Warrior Armor|c|n|18|w",
    "Glorious Warrior Helmet|h|n|18|w",
    "Goblin Cleaver|w|n|10|p",
    "God Spear|a|e|9|d",
    "Godforged Greatstaff|w|l|3|s",
    "Godly Guardian Armor|c|n|13|g",
    "Godly Guardian Helmet|h|n|13|g",
    "Godly Mage Helmet|h|n|13|m",
    "Godly Mage Robes|c|n|13|m",
    "Godly Warrior Armor|c|n|13|w",
    "Godly Warrior Helmet|h|n|13|w",
    "Godsword|w|n|20|p",
    "Golden Kopesh|w|n|4|p",
    "Grand Claymore|w|n|5|p",
    "Granite Maul|w|n|5|p",
    "Gravity Leap|a|l|1|",
    "Greater Dark Scythe|w|n|13|s",
    "Greater Prophet Staff|w|n|13|s",
    "Ground Slam|a|u|20|d",
    "Ground Stomp|a|e|16|d",
    "Guardian Armor|c|n|5|g",
    "Guardian Call|a|e|13|g",
    "Guardian Helmet|h|n|5|g",
    "Guardian Roar|a|r|6|g",
    "Guardian's Blessing|a|r|10|g",
    "Gungnir|w|l|11|s",
    "Hand Cannon|a|u|15|d",
    "Hands Of Death|a|e|22|d",
    "Hardened Ice Sword|w|n|20|p",
    "Heavenly Greatsword|w|n|10|p",
    "Heavenly Guardian Armor|c|n|3|g",
    "Heavenly Guardian Helmet|h|n|3|g",
    "Heavenly Mage Armor|c|n|3|m",
    "Heavenly Mage Helmet|h|n|3|m",
    "Heavenly Warrior Armor|c|n|3|w",
    "Heavenly Warrior Helmet|h|n|3|w",
    "Hellstone Greataxe|w|n|19|p",
    "Hextech Greataxe|w|n|16|p",
    "Hextech Katana|w|n|16|p",
    "Hextech Overloaded Staff|w|l|3|s",
    "Hextech Polearm|w|n|16|s",
    "Hextech Wired Spellblade|w|n|16|s",
    "High Priest Battleaxe|w|n|10|p",
    "Hofund|w|x|11|p",
    "Holy Barrier|a|r|4|g",
    "Holy Circle|a|e|4|h",
    "Holy Grail|w|n|20|s",
    "Holy Staff|w|n|5|s",
    "Holy Sun Staff|w|n|4|s",
    "Holy Wand|w|n|13|s",
    "Honorable Greatsword|w|n|15|p",
    "Hope's Triumph|w|n|18|s",
    "Hunter's Guardian Armor|c|n|8|g",
    "Hunter's Guardian Helmet|h|n|8|g",
    "Hunter's Mage Armor|c|n|8|m",
    "Hunter's Mage Helmet|h|n|8|m",
    "Hunter's Warrior Armor|c|n|8|w",
    "Hunter's Warrior Helmet|h|n|8|w",
    "Ice Barrage|a|e|2|d",
    "Ice Crash|a|e|2|d",
    "Ice Enhanced Sword|w|n|20|p",
    "Ice Greatspear|w|n|11|p",
    "Ice Guardian Armor|c|n|21|g",
    "Ice Guardian Helmet|h|n|21|g",
    "Ice Infused Slicer|w|n|20|p",
    "Ice King's Guardian Armor|c|n|21|g",
    "Ice King's Guardian Helmet|h|n|21|g",
    "Ice King's Mage Hood|h|n|21|m",
    "Ice King's Mage Robes|c|n|21|m",
    "Ice King's Warrior Armor|c|n|21|w",
    "Ice King's Warrior Helmet|h|n|21|w",
    "Ice Mage Hood|h|n|21|m",
    "Ice Mage Robes|c|n|21|m",
    "Ice Needles|a|u|20|d",
    "Ice Nova|a|r|18|d",
    "Ice Queen's Wand|w|n|20|s",
    "Ice Reaver|w|n|20|s",
    "Ice Sickles|w|n|20|p",
    "Ice Spellblade|w|n|11|s",
    "Ice Spikes|a|e|2|d",
    "Ice Totem|a|e|18|d",
    "Ice Wand|w|n|20|s",
    "Ice Warrior Armor|c|n|21|w",
    "Ice Warrior Helmet|h|n|21|w",
    "Iceblade|w|n|20|p",
    "Icicle Barrage|a|r|17|d",
    "Illusion Blast|a|e|15|d",
    "Industrial Guardian Armor|c|n|16|g",
    "Industrial Guardian Helmet|h|n|16|g",
    "Industrial Mage Armor|c|n|16|m",
    "Industrial Mage Helmet|h|n|16|m",
    "Industrial Spellscythe|w|n|15|s",
    "Industrial Warrior Armor|c|n|16|w",
    "Industrial Warrior Helmet|h|n|16|w",
    "Infernal Blast|a|e|16|d",
    "Infernal Elemental Sword|w|n|20|p",
    "Infernal Guardian Armor|c|n|15|g",
    "Infernal Guardian Helmet|h|n|15|g",
    "Infernal Mage Hood|h|n|15|m",
    "Infernal Mage Robes|c|n|15|m",
    "Infernal Orbs|a|u|18|d",
    "Infernal Strike|a|e|18|d",
    "Infernal Sun Staff|w|n|10|s",
    "Infernal Warrior Armor|c|n|15|w",
    "Infernal Warrior Helmet|h|n|15|w",
    "Inferno Plate Armor|c|n|13|w",
    "Inferno Plate Helmet|h|n|13|w",
    "Inner Focus|a|e|19|b",
    "Inner Rage|a|e|19|b",
    "Innervate|a|e|4|b",
    "Inventor's Greatsword|w|l|16|p",
    "Inventor's Guardian Armor|c|n|3|g",
    "Inventor's Guardian Helmet|h|n|3|g",
    "Inventor's Mage Armor|c|n|3|m",
    "Inventor's Mage Helmet|h|n|3|m",
    "Inventor's Spellblade|w|l|16|s",
    "Inventor's Warrior Armor|c|n|3|w",
    "Inventor's Warrior Helmet|h|n|3|w",
    "Iron Armor|c|n|5|g",
    "Iron Helmet|h|n|5|g",
    "Iron Longsword|w|n|5|p",
    "Jade Rain|a|e|9|d",
    "Jade Roller|a|e|9|d",
    "Jade Spelldagger|w|n|15|s",
    "Jigoku Club And Shield|w|n|22|p",
    "Jigoku Shuriblade|w|n|22|s",
    "Jigoku Twin Katanas|w|n|22|p",
    "Jigoku Twin Warfans|w|n|22|s",
    "Jotunn Guardian Armor|c|n|11|g",
    "Jotunn Guardian Helmet|h|n|11|g",
    "Jotunn Mage Armor|c|n|11|m",
    "Jotunn Mage Helmet|h|n|11|m",
    "Jotunn Warrior Armor|c|n|11|w",
    "Jotunn Warrior Helmet|h|n|11|w",
    "King's Greatsword|w|n|20|p",
    "King's Spellblade|w|n|20|s",
    "Kraken Slayer|w|l|8|p",
    "Kunai Knives|a|e|22|d",
    "Laevateinn|w|x|11|s",
    "Lava Barrage|a|e|19|d",
    "Lava Beam Orb|a|e|19|d",
    "Lava Cage|a|e|19|d",
    "Lava King's Guardian Armor|c|n|19|g",
    "Lava King's Guardian Helmet|h|n|19|g",
    "Lava King's Mage Armor|c|n|19|m",
    "Lava King's Mage Helmet|h|n|19|m",
    "Lava King's Spell Daggers|w|l|19|s",
    "Lava King's Warrior Armor|c|n|19|w",
    "Lava King's Warrior Helmet|h|n|19|w",
    "Lava King's Warscythe|w|l|19|p",
    "Lava Lash|a|e|15|d",
    "Lava Shard Staff|w|n|19|s",
    "Lava Spellblade|w|n|19|s",
    "Lava Tendril Pike|w|n|19|s",
    "Leaping Strike|a|c|0|d",
    "Life Dash|a|r|16|h",
    "Life Pulse|a|r|6|h",
    "Lightning Beam|a|u|20|d",
    "Lightning Burst|a|e|7|d",
    "Lightning Strikes|a|r|4|d",
    "Luminous Greatstaff|w|n|18|s",
    "Mage Plate Armor|c|n|21|m",
    "Mage Plate Helmet|h|n|21|m",
    "Mage's Spellbook|w|n|5|s",
    "Magic Mallet|w|n|5|s",
    "Magic Trident|w|n|8|s",
    "Magma Infused Staff|w|n|20|s",
    "Magma Infused Waraxe|w|n|19|p",
    "Mana Infused Spellblade|w|n|17|s",
    "Mercenary Armor|c|n|5|w",
    "Mercenary Helmet|h|n|5|w",
    "Midgardian Guardian Armor|c|n|11|g",
    "Midgardian Guardian Helmet|h|n|11|g",
    "Midgardian Mage Armor|c|n|11|m",
    "Midgardian Mage Helmet|h|n|11|m",
    "Midgardian Warrior Armor|c|n|11|w",
    "Midgardian Warrior Helmet|h|n|11|w",
    "Mighty Cleave|a|e|1|",
    "Mighty Flatblade|w|n|13|p",
    "Mighty Frozen Greatsword|w|n|20|p",
    "Mighty Fusion Maul|w|n|16|p",
    "Mighty Fusion Spellblade|w|n|16|s",
    "Mighty Leap|a|r|8|d",
    "Mjolnir|w|l|11|p",
    "Molten Ball|a|e|12|d",
    "Molten Blade|w|n|13|p",
    "Molten Forged Guardian Armor|c|n|19|g",
    "Molten Forged Guardian Helmet|h|n|19|g",
    "Molten Forged Mage Armor|c|n|19|m",
    "Molten Forged Mage Helmet|h|n|19|m",
    "Molten Forged Warrior Armor|c|n|19|w",
    "Molten Forged Warrior Helmet|h|n|19|w",
    "Molten Greataxe|w|n|13|p",
    "Molten Maul|w|n|0|p",
    "Molten Shards|a|e|19|d",
    "Moon Crystal Spell Blade|w|n|12|s",
    "Moonlight Staff|w|n|10|s",
    "Mossy Greatsword|w|n|20|p",
    "Mystery Matter|a|e|12|d",
    "Mythical Guardian Armor|c|n|8|g",
    "Mythical Guardian Helmet|h|n|8|g",
    "Mythical Mage Armor|c|n|8|m",
    "Mythical Mage Helmet|h|n|8|m",
    "Mythical Warrior Armor|c|n|8|w",
    "Mythical Warrior Helmet|h|n|8|w",
    "Nature Guardian Armor|c|n|3|g",
    "Nature Guardian Helmet|h|n|3|g",
    "Nature Mage Armor|c|n|3|m",
    "Nature Mage Helmet|h|n|3|m",
    "Nature Scythe|w|n|18|p",
    "Nature Spellblade|w|n|3|s",
    "Nature Warrior Armor|c|n|3|w",
    "Nature Warrior Helmet|h|n|3|w",
    "Norse Blade|w|n|11|p",
    "Norse Greataxe|w|n|11|p",
    "Northern Runic Blade|w|n|11|p",
    "Northern Spellstaff|w|n|11|s",
    "Novice Armor|c|n|5|w",
    "Novice Helmet|h|n|5|w",
    "Novice Wand|w|n|5|s",
    "Oathsworn Guardian Armor|c|n|9|g",
    "Oathsworn Guardian Helmet|h|n|9|g",
    "Oathsworn Halberd|w|n|9|p",
    "Oathsworn Hammer|w|n|9|p",
    "Oathsworn Mage Armor|c|n|9|m",
    "Oathsworn Mage Helmet|h|n|9|m",
    "Oathsworn Spellblade|w|n|9|s",
    "Oathsworn Spellscythe|w|n|9|s",
    "Oathsworn Staff And Tome|w|n|9|s",
    "Oathsworn Sword And Shield|w|n|9|p",
    "Oathsworn Warrior Armor|c|n|9|w",
    "Oathsworn Warrior Helmet|h|n|9|w",
    "Ocean Dweller's Mageblade|w|n|8|s",
    "Ocean Pearl Staff|w|n|2|s",
    "Ocean Splitter|w|n|13|p",
    "Oceanic Greatsword|w|n|2|p",
    "Oni Guardian Armor|c|n|22|g",
    "Oni Guardian Helmet|h|n|22|g",
    "Oni Mage Cloak|h|n|22|m",
    "Oni Mage Robes|c|n|22|m",
    "Oni Warrior Armor|c|n|22|w",
    "Oni Warrior Helmet|h|n|22|w",
    "Oni's Bell Staff|w|n|22|s",
    "Oni's Dadao|w|n|22|p",
    "Oni's Kanabo|w|n|22|p",
    "Oni's Naginata|w|n|22|s",
    "Onyx Empowered Greatsword|w|n|13|p",
    "Onyx Hammer|w|n|20|p",
    "Onyx Spell Scythe|w|n|20|s",
    "Onyx Staff|w|n|5|s",
    "Oracle's Ascendance|w|l|0|s",
    "Oracle's Gaze|w|l|0|s",
    "Oracle's Revelation|w|l|0|s",
    "Oracle's Wisdom|w|l|0|s",
    "Orb Of Destruction|a|e|16|d",
    "Overcharge|a|r|16|d",
    "Overgrown War Scythe|w|n|7|p",
    "Overlord's Guardian Armor|c|n|17|g",
    "Overlord's Guardian Hat|h|n|17|g",
    "Overlord's Mage Hat|h|n|17|m",
    "Overlord's Mage Robes|c|n|17|m",
    "Overlord's Manablade|w|l|17|s",
    "Overlord's Rageblade|w|l|17|p",
    "Overlord's Warrior Armor|c|n|17|w",
    "Overlord's Warrior Hat|h|n|17|w",
    "Phantom Blades|a|e|8|d",
    "Phantom Flames|a|e|13|d",
    "Phantom Striker|a|e|8|d",
    "Phase Barrage|a|n|14|d",
    "Phoenix Greatstaff|w|l|18|s",
    "Piercing Rain|a|u|20|d",
    "Piercing Roots|a|r|7|d",
    "Pink Pearl Spellscythe|w|n|15|s",
    "Pirate King's Guardian Armor|c|n|13|g",
    "Pirate King's Guardian Helmet|h|n|13|g",
    "Pirate King's Mage Halo|h|n|13|m",
    "Pirate King's Mage Robes|c|n|13|m",
    "Pirate King's Warrior Armor|c|n|13|w",
    "Pirate King's Warrior Helmet|h|n|13|w",
    "Plasma Infused Cutlass|w|n|16|s",
    "Plasma Spellblade|w|n|16|s",
    "Plasma Twin Spellblade|w|n|16|s",
    "Poison Cloud|a|r|4|d",
    "Poison Spear|w|n|8|s",
    "Pulse Beam|a|r|8|d",
    "Pulse Waves|a|r|16|d",
    "Pulsefire|a|r|13|d",
    "Pulverizer|w|n|5|p",
    "Raider's Guardian Armor|c|n|8|g",
    "Raider's Guardian Helmet|h|n|8|g",
    "Raider's Mage Armor|c|n|8|m",
    "Raider's Mage Helmet|h|n|8|m",
    "Raider's Warrior Armor|c|n|8|w",
    "Raider's Warrior Helmet|h|n|8|w",
    "Red Knight Armor|c|n|5|w",
    "Red Knight Helmet|h|n|5|w",
    "Redemption|a|u|4|h",
    "Reinforced Guardian Armor|c|n|18|g",
    "Reinforced Guardian Helmet|h|n|18|g",
    "Reinforced Ice Blade|w|n|20|p",
    "Reinforced Steel Sword|w|n|20|p",
    "Rejuvenating Spray|a|u|20|h",
    "Rending Slice|a|r|18|d",
    "Revitalize|a|e|7|h",
    "Rift Beam|a|e|22|d",
    "Riptide Guardian Armor|c|n|2|g",
    "Riptide Guardian Helmet|h|n|2|g",
    "Riptide Mage Armor|c|n|2|m",
    "Riptide Mage Helmet|h|n|2|m",
    "Riptide Warrior Armor|c|n|2|w",
    "Riptide Warrior Helmet|h|n|2|w",
    "Rogue Guardian Armor|c|n|17|g",
    "Rogue Guardian Hood|h|n|17|g",
    "Rogue Mage Hood|h|n|17|m",
    "Rogue Mage Robes|c|n|17|m",
    "Rogue Warrior Armor|c|n|17|w",
    "Rogue Warrior Hood|h|n|17|w",
    "Rogue's Rapier|w|n|5|p",
    "Royal Crimson Greatsword|w|n|18|p",
    "Royal Katana|w|n|15|p",
    "Royal Slicer|w|n|20|p",
    "Ruby Greatsword|w|n|15|p",
    "Ruby Staff|w|n|13|s",
    "Runic Hammer|w|n|20|p",
    "Runic Mace|w|n|11|s",
    "Runic Pike|w|n|17|s",
    "Runic Spellscythe|w|n|17|s",
    "Runic Strike|a|u|17|d",
    "Sacrificial Orbs|a|e|1|",
    "Sakura Greatstaff|w|l|15|s",
    "Sakura Katana|w|l|15|p",
    "Salvaged Guardian Armor|c|n|17|g",
    "Salvaged Guardian Helmet|h|n|17|g",
    "Salvaged Mage Hat|h|n|17|m",
    "Salvaged Mage Robes|c|n|17|m",
    "Salvaged Warrior Armor|c|n|17|w",
    "Salvaged Warrior Helmet|h|n|17|w",
    "Samurai Guardian Armor|c|n|15|g",
    "Samurai Guardian Helmet|h|n|15|g",
    "Samurai Mage Helmet|h|n|15|m",
    "Samurai Mage Robes|c|n|15|m",
    "Samurai Warrior Armor|c|n|15|w",
    "Samurai Warrior Hairband|h|n|15|w",
    "Sandstone Guardian Armor|c|n|4|g",
    "Sandstone Guardian Helmet|h|n|4|g",
    "Sandstone Mage Cloak|h|n|4|m",
    "Sandstone Mage Robes|c|n|4|m",
    "Sandstone Warrior Armor|c|n|4|w",
    "Sandstone Warrior Helmet|h|n|4|w",
    "Sapphire Greatstaff|w|n|18|s",
    "Sapphire Spell Dagger|w|n|20|s",
    "Sapphire Spellspear|w|n|15|s",
    "Sapphire Stone Wand|w|n|17|s",
    "Sea King's Greatstaff|w|l|2|s",
    "Sea King's Trident|w|l|2|p",
    "Sea Serpent's Wings|w|l|8|s",
    "Sea Staff|w|n|2|s",
    "Seafarer's Lost Blade|w|n|8|p",
    "Seafarer's Magic Device|w|n|8|s",
    "Searing Beam|a|u|20|d",
    "Seishin Cleaver|w|n|22|p",
    "Seishin Club|w|n|22|s",
    "Seishin Crescent|w|n|22|p",
    "Seishin Guardian Armor|c|n|22|g",
    "Seishin Guardian Helmet|h|n|22|g",
    "Seishin Mage Cloak|h|n|22|m",
    "Seishin Mage Robes|c|n|22|m",
    "Seishin Staff|w|n|22|s",
    "Seishin Warrior Armor|c|n|22|w",
    "Seishin Warrior Helmet|h|n|22|w",
    "Serpent Pike|w|n|2|p",
    "Serpent Scimitars|w|n|2|p",
    "Sharktooth Blade|w|n|8|p",
    "Shattered Magma Blade|w|n|19|p",
    "Shatterstrike|a|e|1|",
    "Shock Blast|a|r|0|d",
    "Shock Wave|a|r|0|d",
    "Skull Flames|a|e|13|d",
    "Slam|a|u|4|d",
    "Smite|a|r|8|d",
    "Snow Elemental Staff|w|n|20|s",
    "Snowy Greatstaff|w|n|20|s",
    "Solar Beam|a|e|9|d",
    "Solar Essence Staff|w|n|12|s",
    "Solar Greatsword|w|n|12|p",
    "Solar Katana|w|n|12|p",
    "Solar Staff|w|n|13|s",
    "Soul Drain|a|e|11|d",
    "Soulstealer Greatsword|w|l|13|p",
    "Space Guardian Armor|c|n|12|g",
    "Space Guardian Helmet|h|n|12|g",
    "Space Mage Armor|c|n|12|m",
    "Space Mage Helmet|h|n|12|m",
    "Space Warrior Armor|c|n|12|w",
    "Space Warrior Helmet|h|n|12|w",
    "Spear Strike|a|r|2|d",
    "Spiked Club|w|n|5|p",
    "Spinning Blade Smash|a|e|22|d",
    "Spirit Bomb|a|u|8|d",
    "Spirit Link|a|e|22|h",
    "Staff of Heat|w|n|15|s",
    "Staff of the Gods|w|l|13|s",
    "Staff of the North|w|n|11|s",
    "Star Barrage|a|r|16|d",
    "Starfall|a|r|16|d",
    "Starter Wand|w|c|0|s",
    "Steel Serrated Sword|w|n|5|p",
    "Steel Strongsword|w|n|20|p",
    "Stone Scythe|w|n|17|p",
    "Stone Strongsword|w|n|13|p",
    "Storm Blast|a|e|0|d",
    "Storm Wave|a|e|0|d",
    "Sunken Blade|w|n|3|p",
    "Sunlight Staff|w|n|10|s",
    "Taunt|a|c|5|g",
    "Taunting Aura|a|u|20|g",
    "Templar Blade|w|n|13|p",
    "Templar Hood|h|n|5|m",
    "Templar Robes|c|n|5|m",
    "Thunderous Blast|a|u|10|d",
    "Timelost Greatsword|w|n|18|p",
    "Timelost Guardian Armor|c|n|18|g",
    "Timelost Guardian Helmet|h|n|18|g",
    "Timelost Mage Armor|c|n|18|m",
    "Timelost Mage Helmet|h|n|18|m",
    "Timelost Spellbook|w|n|18|s",
    "Timelost Warhammer|w|n|18|p",
    "Timelost Warrior Armor|c|n|18|w",
    "Timelost Warrior Helmet|h|n|18|w",
    "Titan's Greataxe|w|n|13|p",
    "Titan-forged_Guardian_Armor|c|n|10|g",
    "Titan-forged_Guardian_Helmet|h|n|10|g",
    "Titan-forged_Mage_Armor|c|n|10|m",
    "Titan-forged_Mage_Helmet|h|n|10|m",
    "Titan-forged_Warrior_Armor|c|n|10|w",
    "Titan-forged_Warrior_Helmet|h|n|10|w",
    "Titanium Guardian Armor|c|n|16|g",
    "Titanium Guardian Helmet|h|n|16|g",
    "Titanium Mage Armor|c|n|16|m",
    "Titanium Mage Helmet|h|n|16|m",
    "Titanium Warrior Armor|c|n|16|w",
    "Titanium Warrior Helmet|h|n|16|w",
    "Toxic Spellscythe|w|n|17|s",
    "Toxic Warspear|w|n|15|p",
    "Tribal Mage Armor|c|n|18|m",
    "Tribal Mage Hood|h|n|18|m",
    "Tribal Staff|w|n|10|s",
    "Tribal Warrior Helmet|h|n|18|w",
    "Tribal_Warrior_Armor|c|n|18|w",
    "Triple Blade Throw|a|e|16|d",
    "Triple Quake|a|e|22|d",
    "Triton Guardian Armor|c|n|2|g",
    "Triton Guardian Helmet|h|n|2|g",
    "Triton Mage Armor|c|n|2|m",
    "Triton Mage Helmet|h|n|2|m",
    "Triton Warrior Armor|c|n|2|w",
    "Triton Warrior Helmet|h|n|2|w",
    "Tsunami|a|u|17|d",
    "Tundra Guardian Armor|c|n|20|g",
    "Tundra Guardian Helmet|h|n|20|g",
    "Tundra Mage Cloak|h|n|20|m",
    "Tundra Mage Robes|c|n|20|m",
    "Tundra Warrior Armor|c|n|20|w",
    "Tundra Warrior Helmet|h|n|20|w",
    "Twin Bladed Slicer|w|n|20|p",
    "Twin Slash|a|e|12|d",
    "Twisted Wood Greatstaff|w|l|3|s",
    "Twisted Wood Greatsword|w|l|3|p",
    "Universal Heal|a|e|13|h",
    "Unstable Warp|a|l|1|",
    "Valhalla Guardian Armor|c|n|11|g",
    "Valhalla Guardian Helmet|h|n|11|g",
    "Valhalla Mage Armor|c|n|11|m",
    "Valhalla Mage Helmet|h|n|11|m",
    "Valhalla Warrior Armor|c|n|11|w",
    "Valhalla Warrior Helmet|h|n|11|w",
    "Vampiric Greatstaff|w|n|18|s",
    "Vengeful Taunt|a|e|1|",
    "Viking Hatchets|w|n|11|p",
    "Viking Sceptre|w|n|11|s",
    "Viking Shield|w|n|11|s",
    "Violet Spellblade|w|n|15|s",
    "Void Beam|a|r|10|d",
    "Void Dragon|a|e|22|d",
    "Void Greatsword|w|n|12|p",
    "Void Plate Armor|c|n|13|g",
    "Void Plate Helmet|h|n|13|g",
    "Void Spell Blade|w|n|12|s",
    "Void Spell Dagger|w|n|12|s",
    "Void Spheres|a|r|8|d",
    "Voidborn Guardian Armor|c|n|1|g",
    "Voidborn Guardian Helmet|h|n|1|g",
    "Voidborn Mage Armor|c|n|1|m",
    "Voidborn Mage Helmet|h|n|1|m",
    "Voidborn Warrior Armor|c|n|1|w",
    "Voidborn Warrior Helmet|h|n|1|w",
    "Voidborn's Embrace|w|l|1|s",
    "Voidborn's Malice|w|l|1|p",
    "Voidfallen's Effigy & Edict|w|x|1|s",
    "Voidflames|a|e|1|",
    "Voidspire & Abyssal Veil|w|x|1|p",
    "Volcanic Greatsword|w|n|19|p",
    "Vortex|a|e|17|d",
    "Vortex Grenade|a|e|12|d",
    "War-forged Guardian Armor|c|n|16|g",
    "War-forged Guardian Helmet|h|n|16|g",
    "War-forged Mage Armor|c|n|16|m",
    "War-forged Mage Helmet|h|n|16|m",
    "War-forged Warrior Armor|c|n|16|w",
    "War-forged Warrior Helmet|h|n|16|w",
    "Warlord Plate Armor|c|n|21|w",
    "Warlord Plate Helmet|h|n|21|w",
    "Water Elemental Spellblade|w|n|20|s",
    "Water Orb|a|r|2|d",
    "Whirlwind|a|u|4|d",
    "Wind Blast|a|e|7|d",
    "Winter Lord's Guardian Armor|c|n|20|g",
    "Winter Lord's Guardian Helmet|h|n|20|g",
    "Winter Lord's Mage Cloak|h|n|20|m",
    "Winter Lord's Mage Robes|c|n|20|m",
    "Winter Lord's Warrior Armor|c|n|20|w",
    "Winter Lord's Warrior Helmet|h|n|20|w",
    "Winterborne|w|l|20|p",
    "Yokai Transformation|a|e|22|d"
}
local kinds = {w="Weapon", a="Ability", h="Helmet", c="Chest"}
local rarities = {n="Common/Unspecified", c="Common", u="Uncommon", r="Rare", e="Epic", l="Legendary", x="Ultimate"}
local rarityConfig = {c="sellCommon", u="sellUncommon", r="sellRare", e="sellEpic", l="sellLegendary", x="sellUltimate"}
local dungeons = {"Abyssal Void","Aquatic Temple","Boss Raids (Legacy)","Desert Temple","Desert Temple (Legacy)","Egg Island","Enchanted Forest","Ghastly Harbor","Gilded Skies","King's Castle","Northern Lands","Orbital Outpost","Pirate Island","Ready Player Two","Samurai Palace","Steampunk Sewers","The Canals","The Underworld","Volcanic Chambers","Winter Outpost","Winter Outpost (Legacy)","Yokai Peak"}
local catalog = {}
local function key(s) return tostring(s or ""):lower():gsub("[^a-z0-9]",""):gsub("armour","armor") end
for _, raw in ipairs(rawCatalog) do
    local name, kind, rarity, dung, role = raw:match("^(.-)|(%a)|([^|]*)|(%d+)|([^|]*)$")
    if name then catalog[#catalog+1] = {name=name,key=key(name),kind=kinds[kind] or "Weapon",kindCode=kind,rarity=rarities[rarity] or "Unknown",rarityCode=rarity,dungeon=dungeons[tonumber(dung)] or "Unknown",role=role} end
end

local cfg = {autoSell=false,sellAfterGames=10,sellKeepLevel=0,games=0,protectedNames={},
    sellCommon=false,sellUncommon=false,sellRare=false,sellEpic=false,sellLegendary=false,sellUltimate=false}
local function save()
    if not (writefile and makefolder) then return end
    pcall(function()
        if isfolder and not isfolder("HarvardAutoSell") then makefolder("HarvardAutoSell") end
        writefile(CONFIG_FILE,HttpService:JSONEncode(cfg))
    end)
end
if isfile and readfile and isfile(CONFIG_FILE) then
    local ok, data = pcall(function() return HttpService:JSONDecode(readfile(CONFIG_FILE)) end)
    if ok and type(data)=="table" then for k,v in pairs(data) do if cfg[k]~=nil then cfg[k]=v end end end
end
if type(cfg.protectedNames)~="table" then cfg.protectedNames={} end
if type(cfg.autoSell)~="boolean" then cfg.autoSell=false end

local function remotes()
    local folder=ReplicatedStorage:FindFirstChild("remotes")
    if not folder then return nil,nil end
    return folder:FindFirstChild("sellItemEvent"),folder:FindFirstChild("reloadInvy")
end
local function inventory()
    local _, reload=remotes()
    if not reload then return nil,"reloadInvy remote missing" end
    local ok, data=pcall(function() return reload:InvokeServer() end)
    if not ok or type(data)~="table" then return nil,"Inventory could not be loaded" end
    return data
end
local function itemName(it) return tostring(it.Name or it.name or it.ItemName or it.itemName or it.DisplayName or "") end
local function itemRarity(it)
    local v=it.Rarity or it.rarity or it.Tier or it.tier
    if type(v)=="string" then
        v=v:lower()
        for _,r in ipairs({"ultimate","legendary","epic","rare","uncommon","common"}) do if v:find(r,1,true) then return ({ultimate="x",legendary="l",epic="e",rare="r",uncommon="u",common="c"})[r] end end
    elseif type(v)=="number" then return ({[1]="c",[2]="u",[3]="r",[4]="e",[5]="l",[6]="x"})[v] end
end
local function equipped(it) return it.Equipped==true or it.IsEquipped==true or it.equipped==true end
local function itemLevel(it) return tonumber(it.Level or it.level or it.ItemLevel or it.itemLevel) end
local function groups(inv)
    return {weapon=inv.weapons or inv.weapon or {},helmet=inv.helmets or inv.helmet or {},chest=inv.chests or inv.chest or {},ability=inv.abilities or inv.ability or {}}
end
local function plan(inv)
    local payload={weapon={},helmet={},chest={},ability={}}
    local sell, keep={},{}
    for group, list in pairs(groups(inv)) do
        for _,it in pairs(list) do
            if type(it)=="table" then
                local name=itemName(it); local rarity=itemRarity(it); local level=itemLevel(it)
                local protected=equipped(it) or cfg.protectedNames[key(name)]==true
                -- Unknown rarity/level is conservatively kept.
                if not rarity or not rarityConfig[rarity] or level==nil then protected=true end
                if level and level >= (tonumber(cfg.sellKeepLevel) or 0) then protected=true end
                if not protected and rarity and rarityConfig[rarity] and cfg[rarityConfig[rarity]]==true then
                    payload[group][#payload[group]+1]=it
                    sell[#sell+1]={name=name,rarity=rarities[rarity] or rarity,id=it.UniqueItemID,group=group}
                else keep[#keep+1]={name=name,rarity=rarity and rarities[rarity] or "Unknown"} end
            end
        end
    end
    return payload,sell,keep
end
local function payloadCount(p) local n=0; for _,v in pairs(p) do n+=#v end; return n end

-- Harvard-like dark UI, with Auto sell, rarity controls, and the extracted item list.
local gui=Instance.new("ScreenGui"); gui.Name="HarvardAutoSellStandalone"; gui.ResetOnSpawn=false
pcall(function() gui.Parent=gethui and gethui() or player:WaitForChild("PlayerGui") end)
if not gui.Parent then gui.Parent=player:WaitForChild("PlayerGui") end
local root=Instance.new("Frame",gui); root.Size=UDim2.fromOffset(440,560); root.Position=UDim2.new(0,24,.5,-280); root.BackgroundColor3=Color3.fromRGB(22,24,30); root.BorderSizePixel=0
Instance.new("UICorner",root).CornerRadius=UDim.new(0,10)
local top=Instance.new("Frame",root); top.Size=UDim2.new(1,0,0,42); top.BackgroundColor3=Color3.fromRGB(29,32,40); top.BorderSizePixel=0
local title=Instance.new("TextLabel",top); title.BackgroundTransparency=1; title.Position=UDim2.fromOffset(14,0); title.Size=UDim2.new(1,-55,1,0); title.Font=Enum.Font.GothamSemibold; title.TextSize=15; title.TextXAlignment=Enum.TextXAlignment.Left; title.TextColor3=Color3.fromRGB(238,240,246); title.Text="Harvard  /  Auto sell + item list"
local close=Instance.new("TextButton",top); close.Size=UDim2.fromOffset(32,28); close.Position=UDim2.new(1,-38,0,7); close.Text="×"; close.Font=Enum.Font.GothamBold; close.TextSize=20; close.TextColor3=Color3.fromRGB(235,235,240); close.BackgroundColor3=Color3.fromRGB(52,56,67); close.BorderSizePixel=0
local scroll=Instance.new("ScrollingFrame",root); scroll.Position=UDim2.fromOffset(10,50); scroll.Size=UDim2.new(1,-20,1,-60); scroll.BackgroundTransparency=1; scroll.BorderSizePixel=0; scroll.ScrollBarThickness=4; scroll.AutomaticCanvasSize=Enum.AutomaticSize.Y; scroll.CanvasSize=UDim2.new()
local sl=Instance.new("UIListLayout",scroll); sl.Padding=UDim.new(0,8); sl.SortOrder=Enum.SortOrder.LayoutOrder
Instance.new("UIPadding",scroll).PaddingBottom=UDim.new(0,8)
local function section(name,desc,height)
    local f=Instance.new("Frame",scroll); f.Size=UDim2.new(1,-4,0,height); f.BackgroundColor3=Color3.fromRGB(30,33,41); f.BorderSizePixel=0; Instance.new("UICorner",f).CornerRadius=UDim.new(0,8)
    local h=Instance.new("TextLabel",f); h.BackgroundTransparency=1; h.Position=UDim2.fromOffset(10,6); h.Size=UDim2.new(1,-20,0,20); h.Font=Enum.Font.GothamSemibold; h.TextSize=13; h.TextXAlignment=Enum.TextXAlignment.Left; h.TextColor3=Color3.fromRGB(229,232,240); h.Text=name
    local d=Instance.new("TextLabel",f); d.BackgroundTransparency=1; d.Position=UDim2.fromOffset(10,27); d.Size=UDim2.new(1,-20,0,28); d.Font=Enum.Font.Gotham; d.TextSize=10; d.TextWrapped=true; d.TextXAlignment=Enum.TextXAlignment.Left; d.TextYAlignment=Enum.TextYAlignment.Top; d.TextColor3=Color3.fromRGB(158,164,178); d.Text=desc or ""
    return f
end
local function button(parent,text,pos,size,fn,danger)
    local b=Instance.new("TextButton",parent); b.Position=pos; b.Size=size; b.BackgroundColor3=danger and Color3.fromRGB(147,54,61) or Color3.fromRGB(60,70,91); b.BorderSizePixel=0; b.Text=text; b.Font=Enum.Font.GothamSemibold; b.TextSize=11; b.TextColor3=Color3.fromRGB(246,247,250); Instance.new("UICorner",b).CornerRadius=UDim.new(0,5); b.MouseButton1Click:Connect(fn); return b
end
local status=section("Auto sell","Sells selected unequipped items on lobby arrival and after a set number of dungeon starts.",138)
local statusText=Instance.new("TextLabel",status); statusText.BackgroundTransparency=1; statusText.Position=UDim2.fromOffset(10,57); statusText.Size=UDim2.new(1,-20,0,22); statusText.Font=Enum.Font.Gotham; statusText.TextSize=11; statusText.TextXAlignment=Enum.TextXAlignment.Left; statusText.TextColor3=Color3.fromRGB(198,203,215)
local gamesLabel=Instance.new("TextLabel",status); gamesLabel.BackgroundTransparency=1; gamesLabel.Position=UDim2.fromOffset(10,82); gamesLabel.Size=UDim2.fromOffset(112,24); gamesLabel.Font=Enum.Font.Gotham; gamesLabel.TextSize=11; gamesLabel.TextColor3=Color3.fromRGB(205,210,220); gamesLabel.TextXAlignment=Enum.TextXAlignment.Left; gamesLabel.Text="Sell after games"
local gamesBox=Instance.new("TextBox",status); gamesBox.Position=UDim2.fromOffset(124,81); gamesBox.Size=UDim2.fromOffset(50,25); gamesBox.BackgroundColor3=Color3.fromRGB(43,47,58); gamesBox.BorderSizePixel=0; gamesBox.TextColor3=Color3.fromRGB(245,246,249); gamesBox.Font=Enum.Font.Gotham; gamesBox.TextSize=12; gamesBox.Text=tostring(cfg.sellAfterGames); gamesBox.ClearTextOnFocus=false
local keepLabel=Instance.new("TextLabel",status); keepLabel.BackgroundTransparency=1; keepLabel.Position=UDim2.fromOffset(190,82); keepLabel.Size=UDim2.fromOffset(84,24); keepLabel.Font=Enum.Font.Gotham; keepLabel.TextSize=11; keepLabel.TextColor3=Color3.fromRGB(205,210,220); keepLabel.TextXAlignment=Enum.TextXAlignment.Left; keepLabel.Text="Keep level ≥"
local keepBox=Instance.new("TextBox",status); keepBox.Position=UDim2.fromOffset(278,81); keepBox.Size=UDim2.fromOffset(50,25); keepBox.BackgroundColor3=Color3.fromRGB(43,47,58); keepBox.BorderSizePixel=0; keepBox.TextColor3=Color3.fromRGB(245,246,249); keepBox.Font=Enum.Font.Gotham; keepBox.TextSize=12; keepBox.Text=tostring(cfg.sellKeepLevel); keepBox.ClearTextOnFocus=false
local note=Instance.new("TextLabel",status); note.BackgroundTransparency=1; note.Position=UDim2.fromOffset(10,108); note.Size=UDim2.new(1,-20,0,18); note.Font=Enum.Font.Gotham; note.TextSize=10; note.TextXAlignment=Enum.TextXAlignment.Left; note.TextColor3=Color3.fromRGB(238,183,124)
local function refresh()
    local inv=inventory()
    if not inv then statusText.Text=(cfg.autoSell and "Enabled • waiting for inventory" or "Switched off"); return end
    local p,s,k=plan(inv)
    statusText.Text=string.format("%s • %d item definitions • %d eligible • %d kept",cfg.autoSell and "Enabled" or "Switched off",#catalog,#s,#k)
end
gamesBox.FocusLost:Connect(function() cfg.sellAfterGames=math.clamp(math.floor(tonumber(gamesBox.Text) or 10),1,50); gamesBox.Text=tostring(cfg.sellAfterGames); save() end)
keepBox.FocusLost:Connect(function() cfg.sellKeepLevel=math.max(0,math.floor(tonumber(keepBox.Text) or 0)); keepBox.Text=tostring(cfg.sellKeepLevel); save(); refresh() end)
local function toggleAuto()
    if cfg.autoSell then cfg.autoSell=false; note.Text="Auto Sell switched off."; save(); refresh(); return end
    local inv=inventory()
    if not inv then note.Text="Cannot preview: inventory unavailable."; return end
    local p,s=plan(inv)
    note.Text=string.format("Preview: %d item(s) would be sold. Press Enable again to confirm.",#s)
    if _G.__HarvardStandaloneEnableArmed then
        _G.__HarvardStandaloneEnableArmed=nil; cfg.autoSell=true; note.Text="Auto Sell enabled."; save(); refresh()
    else
        _G.__HarvardStandaloneEnableArmed=true
        task.delay(8,function() _G.__HarvardStandaloneEnableArmed=nil end)
    end
end
button(status,"Enable / disable",UDim2.new(0,10,1,-32),UDim2.new(.48,-8,0,25),toggleAuto)
button(status,"Sell once now",UDim2.new(.5,0,1,-32),UDim2.new(.48,-8,0,25),function()
    local inv,err=inventory(); if not inv then note.Text=err or "Inventory unavailable"; return end
    local p,s=plan(inv); if #s==0 then note.Text="Nothing matches current sale rules."; return end
    note.Text=string.format("Preview: %d item(s). Press Sell once again within 8 seconds to confirm.",#s)
    if _G.__HarvardStandaloneSellArmed then
        _G.__HarvardStandaloneSellArmed=nil
        local remote=select(1,remotes()); if not remote then note.Text="sellItemEvent missing"; return end
        local ok=pcall(function() remote:FireServer(p) end)
        note.Text=ok and "Sell request sent; verify inventory." or "Sell request failed."
    else
        _G.__HarvardStandaloneSellArmed=true
        task.delay(8,function() _G.__HarvardStandaloneSellArmed=nil end)
    end
end)

local raritySection=section("Rarities to sell","Choose the rarities Harvard Auto Sell is allowed to sell. Changing a rarity switches Auto Sell off until re-enabled.",220)
local rarityRows={{"c","Common","sellCommon"},{"u","Uncommon","sellUncommon"},{"r","Rare","sellRare"},{"e","Epic","sellEpic"},{"l","Legendary","sellLegendary"},{"x","Ultimate","sellUltimate"}}
for i,row in ipairs(rarityRows) do
    local b=button(raritySection,(cfg[row[3]] and "✓  " or "□  ")..row[2],UDim2.fromOffset(10,56+(i-1)*26),UDim2.new(1,-20,0,23),function()
        cfg[row[3]]=not cfg[row[3]]; if cfg.autoSell then cfg.autoSell=false end
        b.Text=(cfg[row[3]] and "✓  " or "□  ")..row[2]; b.BackgroundColor3=cfg[row[3]] and Color3.fromRGB(49,108,83) or Color3.fromRGB(60,70,91)
        save(); refresh()
    end)
end

local listSection=section("Harvard item list","Extracted item catalog. Search and click a row to protect/unprotect that item by normalized name.",190)
local search=Instance.new("TextBox",listSection); search.Position=UDim2.fromOffset(10,57); search.Size=UDim2.new(1,-20,0,25); search.BackgroundColor3=Color3.fromRGB(43,47,58); search.BorderSizePixel=0; search.TextColor3=Color3.fromRGB(245,246,249); search.PlaceholderText="Search item, rarity, type, dungeon..."; search.Font=Enum.Font.Gotham; search.TextSize=11; search.ClearTextOnFocus=false
local list=Instance.new("ScrollingFrame",listSection); list.Position=UDim2.fromOffset(10,87); list.Size=UDim2.new(1,-20,0,90); list.BackgroundColor3=Color3.fromRGB(25,28,35); list.BorderSizePixel=0; list.ScrollBarThickness=4; list.CanvasSize=UDim2.new()
local ll=Instance.new("UIListLayout",list); ll.Padding=UDim.new(0,2)
ll:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function() list.CanvasSize=UDim2.new(0,0,0,ll.AbsoluteContentSize.Y+4) end)
local listCount=Instance.new("TextLabel",listSection); listCount.BackgroundTransparency=1; listCount.Position=UDim2.new(0,10,1,-15); listCount.Size=UDim2.new(1,-20,0,12); listCount.Font=Enum.Font.Gotham; listCount.TextSize=10; listCount.TextXAlignment=Enum.TextXAlignment.Left; listCount.TextColor3=Color3.fromRGB(158,164,178)
local function renderList()
    for _,c in ipairs(list:GetChildren()) do if c:IsA("TextButton") then c:Destroy() end end
    local q=search.Text:lower(); local matches=0
    for _,e in ipairs(catalog) do
        local hay=(e.name.." "..e.kind.." "..e.rarity.." "..e.dungeon):lower()
        if q=="" or hay:find(q,1,true) then
            matches+=1
            if matches<=150 then
                local protected=cfg.protectedNames[e.key]==true
                local b=Instance.new("TextButton",list); b.Size=UDim2.new(1,-4,0,22); b.BackgroundColor3=protected and Color3.fromRGB(49,108,83) or Color3.fromRGB(38,42,51); b.BorderSizePixel=0; b.TextColor3=Color3.fromRGB(226,230,238); b.Font=Enum.Font.Gotham; b.TextSize=10; b.TextXAlignment=Enum.TextXAlignment.Left; b.Text=(protected and "✓ " or "   ")..e.name.."  •  "..e.rarity.." "..e.kind
                b.MouseButton1Click:Connect(function() cfg.protectedNames[e.key]=not cfg.protectedNames[e.key] or nil; save(); renderList(); refresh() end)
            end
        end
    end
    listCount.Text=string.format("%d matches • showing up to 150 • click item to protect",matches)
end
search:GetPropertyChangedSignal("Text"):Connect(renderList)
close.Text="×"; close.Size=UDim2.fromOffset(32,28); close.Position=UDim2.new(1,-38,0,7); close.MouseButton1Click:Connect(function() save(); gui:Destroy() end)

local lastJob,lastPlace=game.JobId,game.PlaceId
local busy=false
local function autoSellNow()
    if busy or not cfg.autoSell then return end
    busy=true
    local remote=select(1,remotes()); local inv=inventory()
    if remote and inv then
        local p,s=plan(inv)
        if #s>0 then
            local ok=pcall(function() remote:FireServer(p) end)
            if ok then
                task.wait(2)
                local after=inventory()
                if after then local _,still=plan(after); note.Text=string.format("Requested %d sale(s); %d still eligible after check.",#s,#still)
                else note.Text="Sale request sent; inventory check unavailable." end
            else note.Text="Sell request failed." end
        else note.Text="Nothing matches current sale rules." end
    end
    busy=false; refresh()
end
task.spawn(function()
    while gui.Parent do
        task.wait(2)
        if game.JobId~=lastJob or game.PlaceId~=lastPlace then
            lastJob,lastPlace=game.JobId,game.PlaceId
            if game.PlaceId==LOBBY_PLACE then task.delay(3,autoSellNow)
            else
                cfg.games=(tonumber(cfg.games) or 0)+1; save()
                if cfg.autoSell and cfg.games>=math.clamp(tonumber(cfg.sellAfterGames) or 10,1,50) then cfg.games=0; save(); task.delay(5,autoSellNow) end
            end
        end
    end
end)
renderList(); refresh(); save()
