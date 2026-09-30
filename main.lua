local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local CoreGui = game:GetService("CoreGui")
local VirtualInputManager = game:GetService("VirtualInputManager")
local VirtualUser = game:GetService("VirtualUser")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer

--==================================================
-- REMOVE OLD GUI
--==================================================

pcall(function()
    local old = CoreGui:FindFirstChild("EggTeleportGUI")
    if old then
        old:Destroy()
    end
end)

--==================================================
-- SETTINGS
--==================================================

local MAX_DISPLAYED_EGGS = 5

local AutoFarmGlobal = false
local AntiAFKEnabled = true
local AutoLeaveEnabled = true

-- Extra admins/mods to leave for (add UserIds here)
local ExtraAdminUserIds = {
    -- 123456789,
}

-- If the game is owned by a group, anyone with this rank or higher counts as admin
local ADMIN_MIN_GROUP_RANK = 200

local AutoTP_Settings = {}
local eggObjects = {}
local eggRows = {}
local eggQueue = {}
local failedEggs = {}

local isProcessingQueue = false
local RETURN_CFRAME = nil

local CurrentTheme = "Crimson"

--==================================================
-- EGG PRIORITY
-- BEST -> WORST
--==================================================

local EggPriority = {
    ["Giant Egg"] = 1000,
    ["Dragon Egg"] = 990,

    ["Solaris Egg"] = 980,
    ["Cherub Egg"] = 970,
    ["Blackhole Egg"] = 960,
    ["Galaxy Egg"] = 950,
    ["Aurora Egg"] = 940,
    ["Soul Egg"] = 930,
    ["Sinister Egg"] = 920,
    ["Flaming Egg"] = 910,
    ["Dominus Egg"] = 900,
    ["Asteroid Egg"] = 890,
    ["Skull Egg"] = 880,
    ["Crystal Egg"] = 870,
    ["Diamond Egg"] = 860,
    ["Golden Egg"] = 850,
    ["Glass Egg"] = 840,
    ["Ice Egg"] = 830,
    ["Slime Egg"] = 820,
    ["Flower Egg"] = 810,
    ["Mushroom Egg"] = 800,
    ["Leaf Egg"] = 790,
    ["Stone Egg"] = 780,
    ["Easter Egg"] = 770,
    ["Cracked Egg"] = 760,
    ["Brown Egg"] = 750,
    ["White Egg"] = 740,
}

--==================================================
-- THEMES
--==================================================

local Themes = {

    Crimson = {
        Background = Color3.fromRGB(18, 7, 10),
        Card = Color3.fromRGB(28, 10, 14),
        Card2 = Color3.fromRGB(38, 13, 18),
        Dark = Color3.fromRGB(48, 16, 22),
        Accent = Color3.fromRGB(180, 35, 50),
        Bright = Color3.fromRGB(235, 55, 70),
        Text = Color3.fromRGB(255, 242, 244),
        SubText = Color3.fromRGB(190, 150, 155),
        Border = Color3.fromRGB(125, 25, 40)
    },

    Purple = {
        Background = Color3.fromRGB(13, 8, 20),
        Card = Color3.fromRGB(23, 13, 35),
        Card2 = Color3.fromRGB(34, 18, 50),
        Dark = Color3.fromRGB(45, 23, 65),
        Accent = Color3.fromRGB(125, 65, 210),
        Bright = Color3.fromRGB(170, 95, 255),
        Text = Color3.fromRGB(247, 240, 255),
        SubText = Color3.fromRGB(175, 155, 195),
        Border = Color3.fromRGB(95, 45, 160)
    },

    Emerald = {
        Background = Color3.fromRGB(6, 18, 13),
        Card = Color3.fromRGB(10, 28, 20),
        Card2 = Color3.fromRGB(14, 40, 28),
        Dark = Color3.fromRGB(18, 52, 36),
        Accent = Color3.fromRGB(30, 170, 100),
        Bright = Color3.fromRGB(55, 220, 130),
        Text = Color3.fromRGB(238, 255, 246),
        SubText = Color3.fromRGB(145, 190, 165),
        Border = Color3.fromRGB(25, 125, 75)
    },

    Ocean = {
        Background = Color3.fromRGB(6, 13, 21),
        Card = Color3.fromRGB(9, 22, 34),
        Card2 = Color3.fromRGB(12, 32, 48),
        Dark = Color3.fromRGB(16, 42, 62),
        Accent = Color3.fromRGB(35, 130, 210),
        Bright = Color3.fromRGB(55, 185, 255),
        Text = Color3.fromRGB(238, 250, 255),
        SubText = Color3.fromRGB(145, 180, 195),
        Border = Color3.fromRGB(25, 100, 165)
    }
}

local Theme = Themes[CurrentTheme]

--==================================================
-- ANTI AFK
--==================================================

LocalPlayer.Idled:Connect(function()

    if AntiAFKEnabled then
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new(0, 0))
    end
end)

task.spawn(function()

    while task.wait(60) do

        if AntiAFKEnabled then
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new(0, 0))
        end
    end
end)

--==================================================
-- RETURN POSITION
--==================================================

local function setupBaseOnRespawn()

    local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local humanoid = char:FindFirstChildOfClass("Humanoid")

    if humanoid then
        pcall(function()
            humanoid:TakeDamage(100)
        end)
    end

    local newChar = LocalPlayer.CharacterAdded:Wait()
    local hrp = newChar:WaitForChild("HumanoidRootPart", 5)

    task.wait(0.2)

    if hrp then
        RETURN_CFRAME = hrp.CFrame
    end
end

task.spawn(setupBaseOnRespawn)

--==================================================
-- GUI
--==================================================

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "EggTeleportGUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = CoreGui

--==================================================
-- 🖼️ BACKGROUND IMAGE
--==================================================

-- Replace this with your Roblox image/decal asset ID.
local BACKGROUND_IMAGE_ID = "rbxassetid://71239209139686"

local Background = Instance.new("ImageLabel")
Background.Name = "KaizeBackground"
Background.Size = UDim2.new(1, 0, 1, 0)
Background.Position = UDim2.new(0, 0, 0, 0)
Background.BackgroundTransparency = 1
Background.Image = BACKGROUND_IMAGE_ID
Background.ImageTransparency = 0.25
Background.ScaleType = Enum.ScaleType.Crop
Background.ZIndex = 0
Background.Parent = ScreenGui

local BackgroundCorner = Instance.new("UICorner")
BackgroundCorner.CornerRadius = UDim.new(0, 12)
BackgroundCorner.Parent = Background

local UIScale = Instance.new("UIScale")
UIScale.Scale = 1
UIScale.Parent = ScreenGui

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 300, 0, 470)
MainFrame.Position = UDim2.new(0.05, 0, 0.22, 0)
MainFrame.BackgroundColor3 = Theme.Background
MainFrame.BorderSizePixel = 0
MainFrame.ZIndex = 2
MainFrame.Parent = ScreenGui

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 12)
MainCorner.Parent = MainFrame

local MainStroke = Instance.new("UIStroke")
MainStroke.Color = Theme.Border
MainStroke.Thickness = 1
MainStroke.Parent = MainFrame

--==================================================
-- HEADER
--==================================================

local Header = Instance.new("Frame")
Header.Size = UDim2.new(1, 0, 0, 58)
Header.BackgroundColor3 = Theme.Card
Header.BorderSizePixel = 0
Header.Parent = MainFrame

local HeaderCorner = Instance.new("UICorner")
HeaderCorner.CornerRadius = UDim.new(0, 12)
HeaderCorner.Parent = Header

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -65, 0, 30)
Title.Position = UDim2.new(0, 15, 0, 7)
Title.BackgroundTransparency = 1
Title.Text = "Kaize Developer"
Title.TextColor3 = Theme.Text
Title.Font = Enum.Font.GothamBold
Title.TextSize = 22
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = Header

local Subtitle = Instance.new("TextLabel")
Subtitle.Size = UDim2.new(1, -65, 0, 17)
Subtitle.Position = UDim2.new(0, 16, 0, 34)
Subtitle.BackgroundTransparency = 1
Subtitle.Text = "RIDE A PET • HUB"
Subtitle.TextColor3 = Theme.SubText
Subtitle.Font = Enum.Font.Gotham
Subtitle.TextSize = 9
Subtitle.TextXAlignment = Enum.TextXAlignment.Left
Subtitle.Parent = Header

local Minimize = Instance.new("TextButton")
Minimize.Size = UDim2.new(0, 35, 0, 35)
Minimize.Position = UDim2.new(1, -45, 0, 11)
Minimize.BackgroundColor3 = Theme.Dark
Minimize.Text = "—"
Minimize.TextColor3 = Theme.Text
Minimize.Font = Enum.Font.GothamBold
Minimize.TextSize = 18
Minimize.BorderSizePixel = 0
Minimize.Parent = Header

local MinCorner = Instance.new("UICorner")
MinCorner.CornerRadius = UDim.new(0, 8)
MinCorner.Parent = Minimize

--==================================================
-- TABS
--==================================================

local MainTab = Instance.new("TextButton")
MainTab.Size = UDim2.new(0.5, -8, 0, 34)
MainTab.Position = UDim2.new(0, 5, 0, 64)
MainTab.BackgroundColor3 = Theme.Accent
MainTab.Text = "MAIN"
MainTab.TextColor3 = Theme.Text
MainTab.Font = Enum.Font.GothamBold
MainTab.TextSize = 11
MainTab.BorderSizePixel = 0
MainTab.Parent = MainFrame

local MainTabCorner = Instance.new("UICorner")
MainTabCorner.CornerRadius = UDim.new(0, 8)
MainTabCorner.Parent = MainTab

local MiscTab = Instance.new("TextButton")
MiscTab.Size = UDim2.new(0.5, -8, 0, 34)
MiscTab.Position = UDim2.new(0.5, 3, 0, 64)
MiscTab.BackgroundColor3 = Theme.Card2
MiscTab.Text = "MISC"
MiscTab.TextColor3 = Theme.SubText
MiscTab.Font = Enum.Font.GothamBold
MiscTab.TextSize = 11
MiscTab.BorderSizePixel = 0
MiscTab.Parent = MainFrame

local MiscTabCorner = Instance.new("UICorner")
MiscTabCorner.CornerRadius = UDim.new(0, 8)
MiscTabCorner.Parent = MiscTab

--==================================================
-- PAGES
--==================================================

local MainPage = Instance.new("Frame")
MainPage.Size = UDim2.new(1, -14, 1, -108)
MainPage.Position = UDim2.new(0, 7, 0, 104)
MainPage.BackgroundTransparency = 1
MainPage.Parent = MainFrame

local MiscPage = Instance.new("Frame")
MiscPage.Size = MainPage.Size
MiscPage.Position = MainPage.Position
MiscPage.BackgroundTransparency = 1
MiscPage.Visible = false
MiscPage.Parent = MainFrame

--==================================================
-- MAIN SCROLL
--==================================================

local EggScroll = Instance.new("ScrollingFrame")
EggScroll.Size = UDim2.new(1, 0, 1, -105)
EggScroll.BackgroundTransparency = 1
EggScroll.BorderSizePixel = 0
EggScroll.ScrollBarThickness = 3
EggScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
EggScroll.Parent = MainPage

local EggLayout = Instance.new("UIListLayout")
EggLayout.Padding = UDim.new(0, 6)
EggLayout.SortOrder = Enum.SortOrder.LayoutOrder
EggLayout.Parent = EggScroll

EggLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()

    EggScroll.CanvasSize = UDim2.new(
        0,
        0,
        0,
        EggLayout.AbsoluteContentSize.Y + 8
    )
end)

--==================================================
-- BUTTON CREATOR
--==================================================

local function createButton(parent, text, size)

    local button = Instance.new("TextButton")

    button.Size = size or UDim2.new(1, 0, 0, 40)
    button.BackgroundColor3 = Theme.Card2
    button.Text = text
    button.TextColor3 = Theme.Text
    button.Font = Enum.Font.GothamBold
    button.TextSize = 11
    button.BorderSizePixel = 0
    button.AutoButtonColor = false
    button.Parent = parent

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = button

    local stroke = Instance.new("UIStroke")
    stroke.Color = Theme.Border
    stroke.Thickness = 1
    stroke.Parent = button

    return button
end

--==================================================
-- FARM / BACK
--==================================================

local FarmButton = createButton(
    MainPage,
    "AUTO FARM : OFF",
    UDim2.new(1, 0, 0, 42)
)

FarmButton.Position = UDim2.new(0, 0, 1, -96)

local TeleportBackButton = createButton(
    MainPage,
    "TELEPORT BACK",
    UDim2.new(1, 0, 0, 42)
)

TeleportBackButton.Position = UDim2.new(0, 0, 1, -47)

--==================================================
-- MISC
--==================================================

local MiscScroll = Instance.new("ScrollingFrame")
MiscScroll.Size = UDim2.new(1, 0, 1, 0)
MiscScroll.BackgroundTransparency = 1
MiscScroll.BorderSizePixel = 0
MiscScroll.ScrollBarThickness = 3
MiscScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
MiscScroll.Parent = MiscPage

local MiscLayout = Instance.new("UIListLayout")
MiscLayout.Padding = UDim.new(0, 7)
MiscLayout.SortOrder = Enum.SortOrder.LayoutOrder
MiscLayout.Parent = MiscScroll

MiscLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()

    MiscScroll.CanvasSize = UDim2.new(
        0,
        0,
        0,
        MiscLayout.AbsoluteContentSize.Y + 10
    )
end)

--==================================================
-- ANTI AFK
--==================================================

local AntiAFKButton = createButton(
    MiscScroll,
    "ANTI-AFK : ON",
    UDim2.new(1, 0, 0, 40)
)

AntiAFKButton.MouseButton1Click:Connect(function()

    AntiAFKEnabled = not AntiAFKEnabled

    AntiAFKButton.Text =
        "ANTI-AFK : " ..
        (AntiAFKEnabled and "ON" or "OFF")
end)

--==================================================
-- AUTO LEAVE (OWNER / ADMIN JOINS)
--==================================================

local AutoLeaveButton = createButton(
    MiscScroll,
    "AUTO LEAVE : ON",
    UDim2.new(1, 0, 0, 40)
)

local hasLeft = false

local function isOwnerOrAdmin(plr)

    if not plr or plr == LocalPlayer then
        return false
    end

    -- Game owner (user-owned game)
    if game.CreatorType == Enum.CreatorType.User
        and plr.UserId == game.CreatorId
    then
        return true
    end

    -- Manual admin list
    if table.find(ExtraAdminUserIds, plr.UserId) then
        return true
    end

    -- Group-owned game: group owner / high rank
    if game.CreatorType == Enum.CreatorType.Group then

        local ok, rank = pcall(function()
            return plr:GetRankInGroup(game.CreatorId)
        end)

        if ok and rank and rank >= ADMIN_MIN_GROUP_RANK then
            return true
        end
    end

    return false
end

local function leaveGame(plr)

    if hasLeft then
        return
    end

    hasLeft = true

    pcall(function()
        LocalPlayer:Kick("Auto Leave: " .. plr.Name .. " (owner/admin) joined.")
    end)

    task.delay(1, function()
        pcall(function()
            game:Shutdown()
        end)
    end)
end

local function checkPlayer(plr)

    if not AutoLeaveEnabled or hasLeft then
        return
    end

    task.spawn(function()
        if AutoLeaveEnabled and isOwnerOrAdmin(plr) then
            leaveGame(plr)
        end
    end)
end

Players.PlayerAdded:Connect(checkPlayer)

-- Check players already in the server when the script starts
for _, plr in ipairs(Players:GetPlayers()) do
    checkPlayer(plr)
end

AutoLeaveButton.MouseButton1Click:Connect(function()

    AutoLeaveEnabled = not AutoLeaveEnabled

    AutoLeaveButton.Text =
        "AUTO LEAVE : " ..
        (AutoLeaveEnabled and "ON" or "OFF")

    -- Also check people already in the server
    if AutoLeaveEnabled then
        for _, plr in ipairs(Players:GetPlayers()) do
            checkPlayer(plr)
        end
    end
end)

--==================================================
-- GUI SMALLER
--==================================================

local SmallerButton = createButton(
    MiscScroll,
    "GUI SMALLER",
    UDim2.new(1, 0, 0, 40)
)

SmallerButton.MouseButton1Click:Connect(function()

    if UIScale.Scale > 0.85 then

        UIScale.Scale = 0.8
        SmallerButton.Text = "GUI SIZE : SMALL"

    else

        UIScale.Scale = 1
        SmallerButton.Text = "GUI SIZE : NORMAL"
    end
end)

--==================================================
-- UI SCALE
--==================================================

local ScaleLabel = Instance.new("TextLabel")
ScaleLabel.Size = UDim2.new(1, 0, 0, 25)
ScaleLabel.BackgroundTransparency = 1
ScaleLabel.Text = "UI SCALE"
ScaleLabel.TextColor3 = Theme.SubText
ScaleLabel.Font = Enum.Font.GothamBold
ScaleLabel.TextSize = 10
ScaleLabel.TextXAlignment = Enum.TextXAlignment.Left
ScaleLabel.Parent = MiscScroll

local ScaleFrame = Instance.new("Frame")
ScaleFrame.Size = UDim2.new(1, 0, 0, 38)
ScaleFrame.BackgroundTransparency = 1
ScaleFrame.Parent = MiscScroll

local ScaleLayout = Instance.new("UIListLayout")
ScaleLayout.FillDirection = Enum.FillDirection.Horizontal
ScaleLayout.Padding = UDim.new(0, 5)
ScaleLayout.Parent = ScaleFrame

for _, scale in ipairs({0.8, 1, 1.25, 1.5}) do

    local button = createButton(
        ScaleFrame,
        tostring(scale) .. "x",
        UDim2.new(0.25, -4, 1, 0)
    )

    button.MouseButton1Click:Connect(function()
        UIScale.Scale = scale
    end)
end

--==================================================
-- COLOR CHANGER
--==================================================

local ColorLabel = Instance.new("TextLabel")
ColorLabel.Size = UDim2.new(1, 0, 0, 25)
ColorLabel.BackgroundTransparency = 1
ColorLabel.Text = "COLOR CHANGER"
ColorLabel.TextColor3 = Theme.SubText
ColorLabel.Font = Enum.Font.GothamBold
ColorLabel.TextSize = 10
ColorLabel.TextXAlignment = Enum.TextXAlignment.Left
ColorLabel.Parent = MiscScroll

local ColorFrame = Instance.new("Frame")
ColorFrame.Size = UDim2.new(1, 0, 0, 78)
ColorFrame.BackgroundTransparency = 1
ColorFrame.Parent = MiscScroll

local ColorGrid = Instance.new("UIGridLayout")
ColorGrid.CellSize = UDim2.new(0.5, -4, 0, 34)
ColorGrid.CellPadding = UDim2.new(0, 6, 0, 6)
ColorGrid.Parent = ColorFrame

local ColorButtons = {}

for _, themeName in ipairs({
    "Crimson",
    "Purple",
    "Emerald",
    "Ocean"
}) do

    local button = createButton(
        ColorFrame,
        themeName,
        UDim2.new(0, 0, 0, 34)
    )

    ColorButtons[themeName] = button
end

--==================================================
-- THEME APPLY
--==================================================

local function applyTheme(themeName)

    if not Themes[themeName] then
        return
    end

    CurrentTheme = themeName
    Theme = Themes[themeName]

    MainFrame.BackgroundColor3 = Theme.Background
    MainStroke.Color = Theme.Border

    Header.BackgroundColor3 = Theme.Card

    Title.TextColor3 = Theme.Text
    Subtitle.TextColor3 = Theme.SubText

    Minimize.BackgroundColor3 = Theme.Dark
    Minimize.TextColor3 = Theme.Text

    MainTab.BackgroundColor3 = Theme.Accent
    MainTab.TextColor3 = Theme.Text

    MiscTab.BackgroundColor3 = Theme.Card2
    MiscTab.TextColor3 = Theme.SubText

    for _, button in pairs(ColorButtons) do
        button.BackgroundColor3 = Theme.Card2
        button.TextColor3 = Theme.Text
    end

    for _, button in ipairs({
        FarmButton,
        TeleportBackButton,
        AntiAFKButton,
        AutoLeaveButton,
        SmallerButton
    }) do
        button.BackgroundColor3 = Theme.Card2
        button.TextColor3 = Theme.Text
    end

    for _, obj in ipairs(ScreenGui:GetDescendants()) do

        if obj:IsA("UIStroke") then
            obj.Color = Theme.Border
        end
    end

    refreshEggUI()
end

for themeName, button in pairs(ColorButtons) do

    button.MouseButton1Click:Connect(function()
        applyTheme(themeName)
    end)
end

--==================================================
-- GAME FUNCTIONS
--==================================================

local function freezeCharacter(hrp, freeze)

    if hrp then
        hrp.Anchored = freeze
    end
end

local function getTargetCFrame(obj)

    if not obj or not obj.Parent then
        return nil
    end

    if obj:IsA("BasePart") then
        return obj.CFrame

    elseif obj:IsA("Model") then
        return obj:GetPivot()
    end

    return nil
end

local function tpToObj(obj)

    local character = LocalPlayer.Character
    local hrp = character and character:FindFirstChild("HumanoidRootPart")

    if not hrp then
        return
    end

    local targetCFrame = getTargetCFrame(obj)

    if targetCFrame then
        hrp.CFrame = targetCFrame
    end
end

local function returnToStart()

    local character = LocalPlayer.Character
    local hrp = character and character:FindFirstChild("HumanoidRootPart")

    if hrp and RETURN_CFRAME then

        freezeCharacter(hrp, false)
        hrp.CFrame = RETURN_CFRAME
    end
end

local function holdKeyE(duration)

    VirtualInputManager:SendKeyEvent(
        true,
        Enum.KeyCode.E,
        false,
        game
    )

    task.wait(duration or 3)

    VirtualInputManager:SendKeyEvent(
        false,
        Enum.KeyCode.E,
        false,
        game
    )
end

--==================================================
-- GARDEN DETECTION
--==================================================

local function nameLooksLikeGarden(name)

    name = string.lower(name)

    return
        string.find(name, "garden", 1, true)
        or string.find(name, "plot", 1, true)
        or string.find(name, "farm", 1, true)
        or string.find(name, "base", 1, true)
end

local GardenContainers = {}

local function scanGardenContainers()

    table.clear(GardenContainers)

    for _, obj in ipairs(Workspace:GetChildren()) do

        if nameLooksLikeGarden(obj.Name) then
            GardenContainers[obj] = true
        end
    end

    -- Also detect named garden models/folders one level deeper
    for _, obj in ipairs(Workspace:GetDescendants()) do

        if (obj:IsA("Model") or obj:IsA("Folder"))
            and nameLooksLikeGarden(obj.Name)
        then
            GardenContainers[obj] = true
        end
    end
end

scanGardenContainers()

local function isInsideGarden(obj)

    local current = obj

    while current and current ~= Workspace do

        if GardenContainers[current] then
            return true
        end

        current = current.Parent
    end

    return false
end

--==================================================
-- EGG DETECTION
--==================================================

local function isEggObject(obj)

    if not obj then
        return false
    end

    local name = string.lower(obj.Name)

    return string.find(name, "egg", 1, true) ~= nil
end

local function getEggPriority(obj)

    if not obj then
        return 0
    end

    if EggPriority[obj.Name] then
        return EggPriority[obj.Name]
    end

    return 1
end

--==================================================
-- TOP 5 MAP EGGS
--==================================================

local function getTopEggs()

    local available = {}

    for egg in pairs(eggObjects) do

        if egg
            and egg.Parent
            and isEggObject(egg)
            and not isInsideGarden(egg)
            and getTargetCFrame(egg)
        then

            table.insert(available, egg)
        end
    end

    table.sort(available, function(a, b)

        local pa = getEggPriority(a)
        local pb = getEggPriority(b)

        if pa == pb then
            return string.lower(a.Name) < string.lower(b.Name)
        end

        return pa > pb
    end)

    local top = {}

    for i = 1, math.min(MAX_DISPLAYED_EGGS, #available) do
        top[i] = available[i]
    end

    return top
end

local function isTopEgg(egg)

    for _, obj in ipairs(getTopEggs()) do

        if obj == egg then
            return true
        end
    end

    return false
end

--==================================================
-- REFRESH TOP 5
--==================================================

function refreshEggUI()

    for egg, row in pairs(eggRows) do

        if row then
            row:Destroy()
        end

        eggRows[egg] = nil
    end

    local topEggs = getTopEggs()

    for index, egg in ipairs(topEggs) do

        local row = Instance.new("Frame")

        row.Size = UDim2.new(1, -4, 0, 62)
        row.BackgroundColor3 = Theme.Card
        row.BorderSizePixel = 0
        row.LayoutOrder = index
        row.Parent = EggScroll

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 9)
        corner.Parent = row

        local stroke = Instance.new("UIStroke")
        stroke.Color = Theme.Border
        stroke.Parent = row

        local rank = Instance.new("TextLabel")
        rank.Size = UDim2.new(0, 30, 1, 0)
        rank.Position = UDim2.new(0, 5, 0, 0)
        rank.BackgroundTransparency = 1
        rank.Text = "#" .. index
        rank.TextColor3 = Theme.Bright
        rank.Font = Enum.Font.GothamBold
        rank.TextSize = 14
        rank.Parent = row

        local name = Instance.new("TextLabel")
        name.Size = UDim2.new(1, -145, 0, 25)
        name.Position = UDim2.new(0, 38, 0, 7)
        name.BackgroundTransparency = 1
        name.Text = egg.Name
        name.TextColor3 = Theme.Text
        name.Font = Enum.Font.GothamBold
        name.TextSize = 10
        name.TextXAlignment = Enum.TextXAlignment.Left
        name.TextTruncate = Enum.TextTruncate.AtEnd
        name.Parent = row

        local status = Instance.new("TextLabel")
        status.Size = UDim2.new(1, -145, 0, 18)
        status.Position = UDim2.new(0, 38, 0, 32)
        status.BackgroundTransparency = 1
        status.Text = "MAP • AVAILABLE"
        status.TextColor3 = Theme.SubText
        status.Font = Enum.Font.Gotham
        status.TextSize = 8
        status.TextXAlignment = Enum.TextXAlignment.Left
        status.Parent = row

        local Teleport = Instance.new("TextButton")
        Teleport.Size = UDim2.new(0, 48, 0, 25)
        Teleport.Position = UDim2.new(1, -105, 0, 7)
        Teleport.BackgroundColor3 = Theme.Card2
        Teleport.Text = "TP"
        Teleport.TextColor3 = Theme.Text
        Teleport.Font = Enum.Font.GothamBold
        Teleport.TextSize = 9
        Teleport.BorderSizePixel = 0
        Teleport.Parent = row

        local tpCorner = Instance.new("UICorner")
        tpCorner.CornerRadius = UDim.new(0, 6)
        tpCorner.Parent = Teleport

        Teleport.MouseButton1Click:Connect(function()

            if egg
                and egg.Parent
                and not isInsideGarden(egg)
            then
                tpToObj(egg)
            end
        end)

        local Auto = Instance.new("TextButton")
        Auto.Size = UDim2.new(0, 48, 0, 25)
        Auto.Position = UDim2.new(1, -53, 0, 7)
        Auto.BackgroundColor3 = Theme.Accent
        Auto.TextColor3 = Theme.Text
        Auto.Font = Enum.Font.GothamBold
        Auto.TextSize = 8
        Auto.BorderSizePixel = 0
        Auto.Text = AutoTP_Settings[egg.Name] and "AUTO ON" or "AUTO"
        Auto.Parent = row

        local autoCorner = Instance.new("UICorner")
        autoCorner.CornerRadius = UDim.new(0, 6)
        autoCorner.Parent = Auto

        Auto.MouseButton1Click:Connect(function()

            AutoTP_Settings[egg.Name] =
                not AutoTP_Settings[egg.Name]

            if AutoTP_Settings[egg.Name] then
                Auto.Text = "AUTO ON"
                queueEggForFarm(egg)
            else
                Auto.Text = "AUTO"
            end
        end)

        eggRows[egg] = row
    end
end

--==================================================
-- QUEUE
--==================================================

function processQueue()

    if isProcessingQueue then
        return
    end

    isProcessingQueue = true

    task.spawn(function()

        while #eggQueue > 0 do

            local egg = table.remove(eggQueue, 1)

            if egg
                and egg.Parent
                and not isInsideGarden(egg)
                and not failedEggs[egg]
            then

                local attempts = 0
                local success = false

                while attempts < 5
                    and AutoFarmGlobal
                    and egg.Parent
                    and not isInsideGarden(egg)
                do

                    attempts += 1

                    local character = LocalPlayer.Character
                    local hrp = character
                        and character:FindFirstChild("HumanoidRootPart")

                    local targetCFrame = getTargetCFrame(egg)

                    if not hrp or not targetCFrame then
                        break
                    end

                    -- Re-check before every teleport
                    if isInsideGarden(egg) then
                        break
                    end

                    hrp.CFrame =
                        targetCFrame
                        + Vector3.new(0, 2, 0)

                    freezeCharacter(hrp, true)

                    task.wait(0.15)

                    holdKeyE(3)

                    task.wait(0.25)

                    if not egg.Parent then
                        success = true
                        break
                    end

                    freezeCharacter(hrp, false)

                    task.wait(0.25)
                end

                local character = LocalPlayer.Character
                local hrp = character
                    and character:FindFirstChild("HumanoidRootPart")

                if hrp then
                    freezeCharacter(hrp, false)
                end

                if not success
                    and egg
                    and egg.Parent
                then
                    failedEggs[egg] = true
                end

                returnToStart()

                task.wait(0.3)
            end

            refreshEggUI()
        end

        isProcessingQueue = false
    end)
end

function queueEggForFarm(egg)

    if not AutoFarmGlobal then
        return
    end

    if not egg
        or not egg.Parent
        or isInsideGarden(egg)
        or not isTopEgg(egg)
    then
        return
    end

    if failedEggs[egg] then
        return
    end

    for _, queued in ipairs(eggQueue) do

        if queued == egg then
            return
        end
    end

    table.insert(eggQueue, egg)

    processQueue()
end

--==================================================
-- AUTO FARM
--==================================================

FarmButton.MouseButton1Click:Connect(function()

    AutoFarmGlobal = not AutoFarmGlobal

    if AutoFarmGlobal then

        FarmButton.Text = "AUTO FARM : ON"
        FarmButton.BackgroundColor3 = Theme.Accent

        for _, egg in ipairs(getTopEggs()) do
            queueEggForFarm(egg)
        end

    else

        FarmButton.Text = "AUTO FARM : OFF"
        FarmButton.BackgroundColor3 = Theme.Card2

        table.clear(eggQueue)
    end
end)

--==================================================
-- TELEPORT BACK
--==================================================

TeleportBackButton.MouseButton1Click:Connect(function()
    returnToStart()
end)

--==================================================
-- ADD EGG
--==================================================

local function addEgg(egg)

    if not egg or not egg.Parent then
        return
    end

    if not isEggObject(egg) then
        return
    end

    if isInsideGarden(egg) then
        return
    end

    if not getTargetCFrame(egg) then
        return
    end

    if eggObjects[egg] then
        return
    end

    eggObjects[egg] = true
    failedEggs[egg] = nil

    refreshEggUI()

    if AutoFarmGlobal and isTopEgg(egg) then
        queueEggForFarm(egg)
    end
end

--==================================================
-- REMOVE EGG
--==================================================

local function removeEgg(egg)

    eggObjects[egg] = nil
    failedEggs[egg] = nil

    local row = eggRows[egg]

    if row then
        row:Destroy()
    end

    eggRows[egg] = nil

    refreshEggUI()

    -- Promote the next best map egg
    if AutoFarmGlobal then

        task.defer(function()

            for _, newEgg in ipairs(getTopEggs()) do

                if not failedEggs[newEgg] then
                    queueEggForFarm(newEgg)
                end
            end
        end)
    end
end

--==================================================
-- INITIAL MAP SCAN
--==================================================

for _, obj in ipairs(Workspace:GetDescendants()) do

    if isEggObject(obj)
        and not isInsideGarden(obj)
    then
        addEgg(obj)
    end
end

--==================================================
-- NEW OBJECTS
--==================================================

Workspace.DescendantAdded:Connect(function(obj)

    if isEggObject(obj) then

        task.wait(0.05)

        if obj
            and obj.Parent
            and not isInsideGarden(obj)
        then
            addEgg(obj)
        end
    end
end)

--==================================================
-- REMOVED OBJECTS
--==================================================

Workspace.DescendantRemoving:Connect(function(obj)

    if eggObjects[obj] then
        removeEgg(obj)
    end
end)

--==================================================
-- GARDEN RESCAN
--==================================================

task.spawn(function()

    while task.wait(2) do

        scanGardenContainers()

        local changed = false

        for egg in pairs(eggObjects) do

            if not egg
                or not egg.Parent
                or isInsideGarden(egg)
            then

                eggObjects[egg] = nil
                failedEggs[egg] = nil

                if eggRows[egg] then
                    eggRows[egg]:Destroy()
                end

                eggRows[egg] = nil

                changed = true
            end
        end

        for _, obj in ipairs(Workspace:GetDescendants()) do

            if isEggObject(obj)
                and obj.Parent
                and not isInsideGarden(obj)
                and not eggObjects[obj]
            then
                addEgg(obj)
                changed = true
            end
        end

        if changed then
            refreshEggUI()
        end

        -- Always keep the farm working on current Top 5
        if AutoFarmGlobal then

            for _, egg in ipairs(getTopEggs()) do
                queueEggForFarm(egg)
            end
        end
    end
end)

--==================================================
-- TABS
--==================================================

MainTab.MouseButton1Click:Connect(function()

    MainPage.Visible = true
    MiscPage.Visible = false

    MainTab.BackgroundColor3 = Theme.Accent
    MainTab.TextColor3 = Theme.Text

    MiscTab.BackgroundColor3 = Theme.Card2
    MiscTab.TextColor3 = Theme.SubText
end)

MiscTab.MouseButton1Click:Connect(function()

    MainPage.Visible = false
    MiscPage.Visible = true

    MiscTab.BackgroundColor3 = Theme.Accent
    MiscTab.TextColor3 = Theme.Text

    MainTab.BackgroundColor3 = Theme.Card2
    MainTab.TextColor3 = Theme.SubText
end)

--==================================================
-- MINIMIZE
--==================================================

local minimized = false

Minimize.MouseButton1Click:Connect(function()

    minimized = not minimized

    if minimized then

        MainFrame.Size = UDim2.new(0, 300, 0, 58)

        MainTab.Visible = false
        MiscTab.Visible = false

        MainPage.Visible = false
        MiscPage.Visible = false

    else

        MainFrame.Size = UDim2.new(0, 300, 0, 470)

        MainTab.Visible = true
        MiscTab.Visible = true

        MainPage.Visible = true
    end
end)

--==================================================
-- DRAG
--==================================================

local dragging = false
local dragStart
local startPos

Header.InputBegan:Connect(function(input)

    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch
    then

        dragging = true
        dragStart = input.Position
        startPos = MainFrame.Position

        input.Changed:Connect(function()

            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
            end
        end)
    end
end)

Header.InputChanged:Connect(function(input)

    if input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch
    then

        if dragging then

            local delta = input.Position - dragStart

            MainFrame.Position = UDim2.new(
                startPos.X.Scale,
                startPos.X.Offset + delta.X,
                startPos.Y.Scale,
                startPos.Y.Offset + delta.Y
            )
        end
    end
end)

--==================================================
-- START
--==================================================

refreshEggUI()
applyTheme("Crimson")
