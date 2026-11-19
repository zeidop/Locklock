local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui", 10)
if not playerGui then return end
local Camera = workspace.CurrentCamera

-- ============================================
-- CONFIGURACIÓN GUARDADA
-- ============================================
local SAVE_FILE = "zeidop_hub_config.json"
local config = {
    buttonSize = 55, buttonVisible = true, isDraggable = true,
    predictEnabled = false, predictAmount = 0.090,
    useDistance3D = true,
    menuTransparency = 0, lockPart = "torso", lockKeyName = "L",
    jumpPower = 50, dashForce = 60, jumpBtnSize = 62, dashBtnSize = 62,
    dashMultiplier = 1.5, dashEnabled = true, instantDash = false,
    antiStun = false, dashAssist = true,
    assistAngle = 50, assistMaxT = 0.44, assistStopDist = 3,
    assistSpikeOn = 50, assistSpikeOff = 35, assistWindow = 0.35, assistLag = 0.06,
    aboveView = false, aboveHeight = 12,
    lockBtnXScale = 0.75, lockBtnXOffset = 0,
    lockBtnYScale = 0.65, lockBtnYOffset = 0,
    lockFree = false
}

local function loadConfig()
    pcall(function()
        if readfile and isfile and isfile(SAVE_FILE) then
            local d = HttpService:JSONDecode(readfile(SAVE_FILE))
            if type(d) == "table" then
                for k, v in pairs(d) do
                    if config[k] ~= nil then config[k] = v end
                end
            end
        end
    end)
end

local function saveConfig()
    pcall(function()
        if writefile then
            writefile(SAVE_FILE, HttpService:JSONEncode(config))
        end
    end)
end

loadConfig()

-- Variables de estado
local targetLock = false
local lockedPlayer = nil
local whitelist = {}
local blacklist = {}
local listeningForKey = false
local lockKey = Enum.KeyCode[config.lockKeyName] or Enum.KeyCode.L
local jumping = true
local stunLocked = false
local instantDashLastVel = Vector3.new(0, 0, 0)
-- v9: historial de posiciones del objetivo (una sola tabla). Mide la velocidad real en una
-- ventana de TIEMPO (no entre dos frames), asi no depende de tus FPS. No suaviza nada.
local TH = { t = {}, p = {}, n = 0, head = 0, root = nil, HN = 48, dashStatus = "-" }
function TH.reset(root)
    TH.n, TH.head, TH.root = 0, 0, root
end
function TH.push(now, root)
    if TH.root ~= root then TH.reset(root) end
    local pos = root.Position
    if TH.n > 0 then
        -- si paso mucho tiempo sin datos, o fue un teletransporte, se descarta el historial viejo
        if now - TH.t[TH.head] > 0.25 or (pos - TH.p[TH.head]).Magnitude > 60 then TH.n = 0 end
    end
    TH.head = TH.head % TH.HN + 1
    TH.t[TH.head], TH.p[TH.head] = now, pos
    if TH.n < TH.HN then TH.n = TH.n + 1 end
end
-- posicion registrada hace "age" segundos (entre dos muestras guardadas; solo para MEDIR)
function TH.posAt(age)
    local want = TH.t[TH.head] - age
    local nextIdx = TH.head
    for k = 1, TH.n - 1 do
        local idx = (TH.head - 1 - k) % TH.HN + 1
        if TH.t[idx] <= want then
            local t0, t1 = TH.t[idx], TH.t[nextIdx]
            local a = 0
            if t1 > t0 then a = (want - t0) / (t1 - t0) end
            return TH.p[idx] + (TH.p[nextIdx] - TH.p[idx]) * a
        end
        nextIdx = idx
    end
    return nil
end
-- velocidad horizontal del objetivo: la que replica Roblox, salvo que contradiga lo que se movio de verdad
function TH.velocity(root)
    local rv = root.AssemblyLinearVelocity
    local v = Vector3.new(rv.X, 0, rv.Z)
    local vh = nil
    if TH.root == root and TH.n >= 3 then
        local pOld = TH.posAt(0.08)
        if pOld then
            local d = TH.p[TH.head] - pOld
            vh = Vector3.new(d.X, 0, d.Z) / 0.08
        end
    end
    if vh then
        if v.Magnitude < 1 then
            v = vh
        elseif vh.Magnitude > 3 then
            local ratio = v.Magnitude / vh.Magnitude
            if v.Unit:Dot(vh.Unit) < 0.7 or ratio > 1.8 or ratio < 0.55 then v = vh end
        end
    end
    if v.Magnitude > 150 then v = v.Unit * 150 end
    return v
end
local PREDICT_TIME = config.predictAmount
local CAMERA_LOCK_NAME = "ZeidopCameraLock"
local LOGO_ID = 97991220544918
local LOAD_SOUND_ID = 0

-- ============================================
-- LIMPIEZA Y PANTALLA DE CARGA
-- ============================================
pcall(function() RunService:UnbindFromRenderStep(CAMERA_LOCK_NAME) end)
local oldGui = playerGui:FindFirstChild("ZeidopHub")
if oldGui then oldGui:Destroy() end
local oldLoad = playerGui:FindFirstChild("ZeidopLoad")
if oldLoad then oldLoad:Destroy() end

local loadGui = Instance.new("ScreenGui")
loadGui.Name = "ZeidopLoad"
loadGui.ResetOnSpawn = false
loadGui.IgnoreGuiInset = true
loadGui.DisplayOrder = 999999
loadGui.Parent = playerGui

local loadBg = Instance.new("Frame")
loadBg.Size = UDim2.new(1, 0, 1, 0)
loadBg.BackgroundColor3 = Color3.fromRGB(8, 8, 12)
loadBg.BorderSizePixel = 0
loadBg.Active = false
loadBg.Parent = loadGui

local loadLogo = Instance.new("ImageLabel")
loadLogo.Size = UDim2.new(0, 90, 0, 90)
loadLogo.Position = UDim2.new(0.5, -45, 0.10, 0)
loadLogo.BackgroundTransparency = 1
loadLogo.Image = LOGO_ID > 0 and ("rbxassetid://" .. LOGO_ID) or ""
loadLogo.Parent = loadBg
Instance.new("UICorner", loadLogo).CornerRadius = UDim.new(1, 0)
local loadLogoStroke = Instance.new("UIStroke")
loadLogoStroke.Color = Color3.fromRGB(160, 120, 255)
loadLogoStroke.Thickness = 3
loadLogoStroke.Parent = loadLogo

local loadTitle = Instance.new("TextLabel")
loadTitle.Size = UDim2.new(0.9, 0, 0, 45)
loadTitle.Position = UDim2.new(0.05, 0, 0.36, 0)
loadTitle.BackgroundTransparency = 1
loadTitle.Text = "zeidop"
loadTitle.TextColor3 = Color3.fromRGB(160, 120, 255)
loadTitle.TextSize = 38
loadTitle.Font = Enum.Font.GothamBlack
loadTitle.Parent = loadBg

local loadSubtitle = Instance.new("TextLabel")
loadSubtitle.Size = UDim2.new(0.9, 0, 0, 30)
loadSubtitle.Position = UDim2.new(0.05, 0, 0.50, 0)
loadSubtitle.BackgroundTransparency = 1
loadSubtitle.Text = "ohh estas usando un script de zeidop"
loadSubtitle.TextColor3 = Color3.fromRGB(220, 220, 230)
loadSubtitle.TextSize = 16
loadSubtitle.Font = Enum.Font.GothamBold
loadSubtitle.Parent = loadBg

local loadBarBg = Instance.new("Frame")
loadBarBg.Size = UDim2.new(0.5, 0, 0, 4)
loadBarBg.Position = UDim2.new(0.25, 0, 0.60, 0)
loadBarBg.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
loadBarBg.BorderSizePixel = 0
loadBarBg.Parent = loadGui
Instance.new("UICorner", loadBarBg).CornerRadius = UDim.new(1, 0)

local loadBar = Instance.new("Frame")
loadBar.Size = UDim2.new(0, 0, 1, 0)
loadBar.BackgroundColor3 = Color3.fromRGB(160, 120, 255)
loadBar.BorderSizePixel = 0
loadBar.Parent = loadBarBg
Instance.new("UICorner", loadBar).CornerRadius = UDim.new(1, 0)

if LOAD_SOUND_ID > 0 then
    local loadSound = Instance.new("Sound")
    loadSound.SoundId = "rbxassetid://" .. LOAD_SOUND_ID
    loadSound.Volume = 1
    loadSound.Parent = loadGui
    loadSound:Play()
end

spawn(function()
    local startTime = tick()
    while tick() - startTime < 2 do
        local progress = (tick() - startTime) / 2
        if progress > 1 then progress = 1 end
        loadBar.Size = UDim2.new(progress, 0, 1, 0)
        wait(0.03)
    end
end)

-- ============================================
-- GUI PRINCIPAL
-- ============================================
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ZeidopHub"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

local menuFrame = Instance.new("Frame")
menuFrame.Size = UDim2.new(0, 210, 0, 290)
menuFrame.Position = UDim2.new(0.02, 0, 0.15, 0)
menuFrame.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
menuFrame.BackgroundTransparency = config.menuTransparency
menuFrame.BorderSizePixel = 0
menuFrame.Active = true
menuFrame.Visible = false
menuFrame.Parent = screenGui
Instance.new("UICorner", menuFrame).CornerRadius = UDim.new(0, 12)

local menuStroke = Instance.new("UIStroke")
menuStroke.Color = Color3.fromRGB(60, 60, 75)
menuStroke.Thickness = 1.5
menuStroke.Parent = menuFrame

local titleBar = Instance.new("Frame")
titleBar.Size = UDim2.new(1, 0, 0, 30)
titleBar.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
titleBar.BorderSizePixel = 0
titleBar.Parent = menuFrame
Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 12)

local titleFix = Instance.new("Frame")
titleFix.Size = UDim2.new(1, 0, 0, 12)
titleFix.Position = UDim2.new(0, 0, 1, -12)
titleFix.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
titleFix.BorderSizePixel = 0
titleFix.Parent = titleBar

local titleLogo = Instance.new("ImageLabel")
titleLogo.Size = UDim2.new(0, 22, 0, 22)
titleLogo.Position = UDim2.new(0, 6, 0, 4)
titleLogo.BackgroundTransparency = 1
titleLogo.Image = LOGO_ID > 0 and ("rbxassetid://" .. LOGO_ID) or ""
titleLogo.Parent = titleBar
Instance.new("UICorner", titleLogo).CornerRadius = UDim.new(1, 0)

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, -60, 0, 30)
titleLabel.Position = UDim2.new(0, 32, 0, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "zeidop hub"
titleLabel.TextColor3 = Color3.fromRGB(160, 120, 255)
titleLabel.TextSize = 14
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Parent = titleBar

local minBtn = Instance.new("TextButton")
minBtn.Size = UDim2.new(0, 24, 0, 24)
minBtn.Position = UDim2.new(1, -28, 0, 3)
minBtn.BackgroundColor3 = Color3.fromRGB(45, 45, 60)
minBtn.Text = "-"
minBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
minBtn.TextSize = 16
minBtn.Font = Enum.Font.GothamBold
minBtn.BorderSizePixel = 0
minBtn.Parent = titleBar
Instance.new("UICorner", minBtn).CornerRadius = UDim.new(0, 6)

local accentLine = Instance.new("Frame")
accentLine.Size = UDim2.new(1, 0, 0, 2)
accentLine.Position = UDim2.new(0, 0, 0, 30)
accentLine.BackgroundColor3 = Color3.fromRGB(160, 120, 255)
accentLine.BorderSizePixel = 0
accentLine.Parent = menuFrame

local tabBar = Instance.new("Frame")
tabBar.Size = UDim2.new(1, -16, 0, 26)
tabBar.Position = UDim2.new(0, 8, 0, 36)
tabBar.BackgroundTransparency = 1
tabBar.Parent = menuFrame

local tabW = 46
local tabGap = 3

local function createTab(name, index)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0, tabW, 1, 0)
    btn.Position = UDim2.new(0, (tabW + tabGap) * (index - 1), 0, 0)
    btn.BackgroundColor3 = Color3.fromRGB(35, 35, 50)
    btn.Text = name
    btn.TextColor3 = Color3.fromRGB(180, 180, 190)
    btn.TextSize = 9
    btn.Font = Enum.Font.GothamBold
    btn.BorderSizePixel = 0
    btn.Parent = tabBar
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
    return btn
end

local tabLock = createTab("LOCK", 1)
local tabNoStun = createTab("STUN", 2)
local tabDash = createTab("DASH", 3)
local tabList = createTab("LISTA", 4)

local contentArea = Instance.new("Frame")
contentArea.Size = UDim2.new(1, -16, 1, -70)
contentArea.Position = UDim2.new(0, 8, 0, 66)
contentArea.BackgroundTransparency = 1
contentArea.Parent = menuFrame

-- ============================================
-- PÁGINA LOCK
-- ============================================
local lockPage = Instance.new("Frame")
lockPage.Size = UDim2.new(1, 0, 1, 0)
lockPage.BackgroundTransparency = 1
lockPage.Visible = true
lockPage.Parent = contentArea

local function halfBtn(text, y, isRight, color)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0.5, -2, 0, 24)
    b.Position = UDim2.new(isRight and 0.5 or 0, isRight and 2 or 0, 0, y)
    b.BackgroundColor3 = color
    b.Text = text
    b.TextColor3 = Color3.fromRGB(255, 255, 255)
    b.TextSize = 10
    b.Font = Enum.Font.GothamBold
    b.BorderSizePixel = 0
    b.Parent = lockPage
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
    return b
end

local function smallLabel(text, y, color)
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(0.55, 0, 0, 16)
    l.Position = UDim2.new(0, 0, 0, y)
    l.BackgroundTransparency = 1
    l.Text = text
    l.TextColor3 = color or Color3.fromRGB(200, 200, 210)
    l.TextSize = 10
    l.Font = Enum.Font.Gotham
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.Parent = lockPage
    return l
end

local function smallBtn(text, x, y, w, color)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0, w, 0, 22)
    b.Position = UDim2.new(0, x, 0, y)
    b.BackgroundColor3 = color or Color3.fromRGB(45, 45, 60)
    b.Text = text
    b.TextColor3 = Color3.fromRGB(255, 255, 255)
    b.TextSize = 12
    b.Font = Enum.Font.GothamBold
    b.BorderSizePixel = 0
    b.Parent = lockPage
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 5)
    return b
end

local showBtn = halfBtn("Boton: Visible", 0, false, Color3.fromRGB(45, 160, 70))
local dragBtn = halfBtn("Arrastrable: ON", 0, true, Color3.fromRGB(45, 160, 70))
local sizeLabel = smallLabel("Tamano: " .. config.buttonSize, 30)
local sizeMinus = smallBtn("-", 110, 28, 28)
local sizePlus = smallBtn("+", 142, 28, 28)

local predictLabel = smallLabel(string.format("Predict: %.3fs", config.predictAmount), 58, Color3.fromRGB(255, 220, 130))
local predictMinus = smallBtn("-0.001", 80, 56, 28)
local predictPlus = smallBtn("+0.001", 112, 56, 28)
local predictToggle = smallBtn(config.predictEnabled and "ON" or "OFF", 144, 56, 28, config.predictEnabled and Color3.fromRGB(45, 160, 70) or Color3.fromRGB(160, 50, 50))

local dist3DBtn = halfBtn("Direct 3D: " .. (config.useDistance3D and "ON" or "OFF"), 86, false, config.useDistance3D and Color3.fromRGB(45, 160, 70) or Color3.fromRGB(160, 50, 50))
local transBtn = halfBtn("Transp: " .. math.floor(config.menuTransparency * 100) .. "%", 86, true, Color3.fromRGB(45, 45, 60))

local aimSep = Instance.new("TextLabel")
aimSep.Size = UDim2.new(1, 0, 0, 14)
aimSep.Position = UDim2.new(0, 0, 0, 114)
aimSep.BackgroundTransparency = 1
aimSep.Text = "--- APUNTADO / TECLA ---"
aimSep.TextColor3 = Color3.fromRGB(160, 120, 255)
aimSep.TextSize = 9
aimSep.Font = Enum.Font.GothamBold
aimSep.Parent = lockPage

local partBtn = halfBtn("Parte: " .. (config.lockPart == "head" and "Cabeza" or "Torso"), 132, false, config.lockPart == "head" and Color3.fromRGB(160, 50, 50) or Color3.fromRGB(70, 130, 220))
local keyBtn = halfBtn("Tecla: " .. lockKey.Name, 132, true, Color3.fromRGB(70, 130, 220))

local aboveBtn = halfBtn("Above: " .. (config.aboveView and "ON" or "OFF"), 162, false, config.aboveView and Color3.fromRGB(45, 160, 70) or Color3.fromRGB(160, 50, 50))
local aboveHeightBtn = halfBtn("Altura: " .. config.aboveHeight, 162, true, Color3.fromRGB(70, 130, 220))

-- BOTÓN MODO NORMAL / LIBRE
local modeBtn = halfBtn("Modo: " .. (config.lockFree and "LIBRE" or "NORMAL"), 192, false, config.lockFree and Color3.fromRGB(80, 60, 140) or Color3.fromRGB(70, 130, 220))

-- ============================================
-- PÁGINA STUN
-- ============================================
local noStunPage = Instance.new("Frame")
noStunPage.Size = UDim2.new(1, 0, 1, 0)
noStunPage.BackgroundTransparency = 1
noStunPage.Visible = false
noStunPage.Parent = contentArea

local function nsBtn(text, y, isRight, color)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0.5, -2, 0, 22)
    b.Position = UDim2.new(isRight and 0.5 or 0, isRight and 2 or 0, 0, y)
    b.BackgroundColor3 = color
    b.Text = text
    b.TextColor3 = Color3.fromRGB(255, 255, 255)
    b.TextSize = 9
    b.Font = Enum.Font.GothamBold
    b.BorderSizePixel = 0
    b.Parent = noStunPage
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
    return b
end

local function nsLabel(text, y, color)
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(0.6, 0, 0, 14)
    l.Position = UDim2.new(0, 0, 0, y)
    l.BackgroundTransparency = 1
    l.Text = text
    l.TextColor3 = color or Color3.fromRGB(200, 200, 210)
    l.TextSize = 9
    l.Font = Enum.Font.Gotham
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.Parent = noStunPage
    return l
end

local function nsSmallBtn(text, x, y, w, color)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0, w, 0, 20)
    b.Position = UDim2.new(0, x, 0, y)
    b.BackgroundColor3 = color or Color3.fromRGB(45, 45, 60)
    b.Text = text
    b.TextColor3 = Color3.fromRGB(255, 255, 255)
    b.TextSize = 11
    b.Font = Enum.Font.GothamBold
    b.BorderSizePixel = 0
    b.Parent = noStunPage
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 5)
    return b
end

local nsToggleBtn = Instance.new("TextButton")
nsToggleBtn.Size = UDim2.new(1, 0, 0, 24)
nsToggleBtn.Position = UDim2.new(0, 0, 0, 0)
nsToggleBtn.BackgroundColor3 = Color3.fromRGB(160, 50, 50)
nsToggleBtn.Text = "ANTI-STUN: OFF"
nsToggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
nsToggleBtn.TextSize = 11
nsToggleBtn.Font = Enum.Font.GothamBold
nsToggleBtn.BorderSizePixel = 0
nsToggleBtn.Parent = noStunPage
Instance.new("UICorner", nsToggleBtn).CornerRadius = UDim.new(0, 6)

local nsJumpLabel = nsLabel("Jump Power: " .. config.jumpPower, 30)
local nsJumpMinus = nsSmallBtn("-", 75, 28, 24)
local nsJumpPlus = nsSmallBtn("+", 103, 28, 24)
local nsJumpGenBtn = nsSmallBtn("GEN", 131, 28, 32, Color3.fromRGB(80, 60, 140))

local nsDashLabel = nsLabel("Dash Force: " .. config.dashForce, 54)
local nsDashMinus = nsSmallBtn("-", 75, 52, 24)
local nsDashPlus = nsSmallBtn("+", 103, 52, 24)
local nsDashGenBtn = nsSmallBtn("GEN", 131, 52, 32, Color3.fromRGB(70, 130, 220))

local nsJumpSizeLabel = nsLabel("Jump Size: " .. config.jumpBtnSize, 78)
local nsJumpSizeMinus = nsSmallBtn("-", 75, 76, 24)
local nsJumpSizePlus = nsSmallBtn("+", 103, 76, 24)

local nsDashSizeLabel = nsLabel("Dash Size: " .. config.dashBtnSize, 102)
local nsDashSizeMinus = nsSmallBtn("-", 75, 100, 24)
local nsDashSizePlus = nsSmallBtn("+", 103, 100, 24)

local nsLockBtn = Instance.new("TextButton")
nsLockBtn.Size = UDim2.new(1, 0, 0, 22)
nsLockBtn.Position = UDim2.new(0, 0, 0, 128)
nsLockBtn.BackgroundColor3 = Color3.fromRGB(90, 90, 100)
nsLockBtn.Text = "LOCK FLOAT: OFF"
nsLockBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
nsLockBtn.TextSize = 10
nsLockBtn.Font = Enum.Font.GothamBold
nsLockBtn.BorderSizePixel = 0
nsLockBtn.Parent = noStunPage
Instance.new("UICorner", nsLockBtn).CornerRadius = UDim.new(0, 6)

local nsInfoLabel = Instance.new("TextLabel")
nsInfoLabel.Size = UDim2.new(1, 0, 0, 20)
nsInfoLabel.Position = UDim2.new(0, 0, 0, 154)
nsInfoLabel.BackgroundTransparency = 1
nsInfoLabel.Text = "Hotkeys: X=toggle Z=off Space=jump Q=dash"
nsInfoLabel.TextColor3 = Color3.fromRGB(120, 120, 140)
nsInfoLabel.TextSize = 8
nsInfoLabel.Font = Enum.Font.Gotham
nsInfoLabel.TextXAlignment = Enum.TextXAlignment.Left
nsInfoLabel.Parent = noStunPage

-- ============================================
-- PÁGINA DASH
-- ============================================
local dashPage = Instance.new("Frame")
dashPage.Size = UDim2.new(1, 0, 1, 0)
dashPage.BackgroundTransparency = 1
dashPage.Visible = false
dashPage.Parent = contentArea

local dashTitle = Instance.new("TextLabel")
dashTitle.Size = UDim2.new(1, -10, 0, 20)
dashTitle.Position = UDim2.new(0, 5, 0, 0)
dashTitle.BackgroundTransparency = 1
dashTitle.Text = "Dash Speed"
dashTitle.TextColor3 = Color3.fromRGB(160, 120, 255)
dashTitle.TextSize = 14
dashTitle.Font = Enum.Font.GothamBold
dashTitle.TextXAlignment = Enum.TextXAlignment.Left
dashTitle.Parent = dashPage

local dashValueLabel = Instance.new("TextLabel")
dashValueLabel.Size = UDim2.new(1, -10, 0, 18)
dashValueLabel.Position = UDim2.new(0, 5, 0, 24)
dashValueLabel.BackgroundTransparency = 1
dashValueLabel.Text = string.format("Multiplicador: %.1fx", config.dashMultiplier)
dashValueLabel.TextColor3 = Color3.fromRGB(200, 200, 210)
dashValueLabel.TextSize = 11
dashValueLabel.Font = Enum.Font.Gotham
dashValueLabel.TextXAlignment = Enum.TextXAlignment.Left
dashValueLabel.Parent = dashPage

local dashMinusBtn = Instance.new("TextButton")
dashMinusBtn.Size = UDim2.new(0.5, -4, 0, 28)
dashMinusBtn.Position = UDim2.new(0, 0, 0, 50)
dashMinusBtn.BackgroundColor3 = Color3.fromRGB(45, 45, 60)
dashMinusBtn.Text = "-"
dashMinusBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
dashMinusBtn.TextSize = 16
dashMinusBtn.Font = Enum.Font.GothamBold
dashMinusBtn.BorderSizePixel = 0
dashMinusBtn.Parent = dashPage
Instance.new("UICorner", dashMinusBtn).CornerRadius = UDim.new(0, 6)

local dashPlusBtn = Instance.new("TextButton")
dashPlusBtn.Size = UDim2.new(0.5, -4, 0, 28)
dashPlusBtn.Position = UDim2.new(0.5, 4, 0, 50)
dashPlusBtn.BackgroundColor3 = Color3.fromRGB(45, 45, 60)
dashPlusBtn.Text = "+"
dashPlusBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
dashPlusBtn.TextSize = 16
dashPlusBtn.Font = Enum.Font.GothamBold
dashPlusBtn.BorderSizePixel = 0
dashPlusBtn.Parent = dashPage
Instance.new("UICorner", dashPlusBtn).CornerRadius = UDim.new(0, 6)

local dashToggleBtn = Instance.new("TextButton")
dashToggleBtn.Size = UDim2.new(1, 0, 0, 28)
dashToggleBtn.Position = UDim2.new(0, 0, 0, 86)
dashToggleBtn.BackgroundColor3 = config.dashEnabled and Color3.fromRGB(45, 160, 70) or Color3.fromRGB(160, 50, 50)
dashToggleBtn.Text = config.dashEnabled and "ACTIVADO" or "DESACTIVADO"
dashToggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
dashToggleBtn.TextSize = 12
dashToggleBtn.Font = Enum.Font.GothamBold
dashToggleBtn.BorderSizePixel = 0
dashToggleBtn.Parent = dashPage
Instance.new("UICorner", dashToggleBtn).CornerRadius = UDim.new(0, 6)

local instantDashBtn = Instance.new("TextButton")
instantDashBtn.Size = UDim2.new(1, 0, 0, 28)
instantDashBtn.Position = UDim2.new(0, 0, 0, 120)
instantDashBtn.BackgroundColor3 = config.instantDash and Color3.fromRGB(45, 160, 70) or Color3.fromRGB(160, 50, 50)
instantDashBtn.Text = config.instantDash and "INSTANT DASH: ON" or "INSTANT DASH: OFF"
instantDashBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
instantDashBtn.TextSize = 12
instantDashBtn.Font = Enum.Font.GothamBold
instantDashBtn.BorderSizePixel = 0
instantDashBtn.Parent = dashPage
Instance.new("UICorner", instantDashBtn).CornerRadius = UDim.new(0, 6)

local dashDesc = Instance.new("TextLabel")
dashDesc.Size = UDim2.new(1, -10, 0, 50)
dashDesc.Position = UDim2.new(0, 5, 0, 152)
dashDesc.BackgroundTransparency = 1
dashDesc.Text = "Multiplica el impulso del dash. INSTANT DASH detecta el dash del juego y lo vuelve instantaneo."
dashDesc.TextColor3 = Color3.fromRGB(120, 120, 130)
dashDesc.TextSize = 10
dashDesc.Font = Enum.Font.Gotham
dashDesc.TextXAlignment = Enum.TextXAlignment.Left
dashDesc.TextWrapped = true
dashDesc.Parent = dashPage

-- ============================================
-- PÁGINA LISTA
-- ============================================
local listPage = Instance.new("Frame")
listPage.Size = UDim2.new(1, 0, 1, 0)
listPage.BackgroundTransparency = 1
listPage.Visible = false
listPage.Parent = contentArea

local function lpBtn(text, y, color)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, 0, 0, 26)
    b.Position = UDim2.new(0, 0, 0, y)
    b.BackgroundColor3 = color
    b.Text = text
    b.TextColor3 = Color3.fromRGB(255, 255, 255)
    b.TextSize = 10
    b.Font = Enum.Font.GothamBold
    b.BorderSizePixel = 0
    b.Parent = listPage
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
    return b
end

local wlBtn = lpBtn("WHITELIST: 0", 0, Color3.fromRGB(45, 160, 70))
local blBtn = lpBtn("BLACKLIST: 0", 30, Color3.fromRGB(190, 45, 45))

local listHint = Instance.new("TextLabel")
listHint.Size = UDim2.new(1, 0, 0, 44)
listHint.Position = UDim2.new(0, 0, 0, 62)
listHint.BackgroundTransparency = 1
listHint.Text = "Whitelist = aliados (nunca lock)\nBlacklist = objetivos prioritarios"
listHint.TextColor3 = Color3.fromRGB(120, 120, 140)
listHint.TextSize = 8
listHint.Font = Enum.Font.Gotham
listHint.TextXAlignment = Enum.TextXAlignment.Left
listHint.TextYAlignment = Enum.TextYAlignment.Top
listHint.TextWrapped = true
listHint.Parent = listPage

-- Selector de jugadores
local pickerGui = Instance.new("Frame")
pickerGui.Name = "ZeidopPicker"
pickerGui.Size = UDim2.new(0, 190, 0, 250)
pickerGui.Position = UDim2.new(0.5, -95, 0.5, -125)
pickerGui.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
pickerGui.BorderSizePixel = 0
pickerGui.Active = true
pickerGui.Visible = false
pickerGui.ZIndex = 50
pickerGui.Parent = screenGui
Instance.new("UICorner", pickerGui).CornerRadius = UDim.new(0, 10)

local pickerStroke = Instance.new("UIStroke")
pickerStroke.Color = Color3.fromRGB(160, 120, 255)
pickerStroke.Thickness = 1.5
pickerStroke.Parent = pickerGui

local pickerTitle = Instance.new("TextLabel")
pickerTitle.Size = UDim2.new(1, -34, 0, 22)
pickerTitle.Position = UDim2.new(0, 8, 0, 4)
pickerTitle.BackgroundTransparency = 1
pickerTitle.Text = "WHITELIST"
pickerTitle.TextColor3 = Color3.fromRGB(110, 255, 130)
pickerTitle.TextSize = 11
pickerTitle.Font = Enum.Font.GothamBold
pickerTitle.TextXAlignment = Enum.TextXAlignment.Left
pickerTitle.Parent = pickerGui

local pickerClose = Instance.new("TextButton")
pickerClose.Size = UDim2.new(0, 22, 0, 22)
pickerClose.Position = UDim2.new(1, -26, 0, 4)
pickerClose.BackgroundColor3 = Color3.fromRGB(160, 50, 50)
pickerClose.Text = "X"
pickerClose.TextColor3 = Color3.fromRGB(255, 255, 255)
pickerClose.TextSize = 12
pickerClose.Font = Enum.Font.GothamBold
pickerClose.BorderSizePixel = 0
pickerClose.Parent = pickerGui
Instance.new("UICorner", pickerClose).CornerRadius = UDim.new(0, 5)

local pickerScroll = Instance.new("ScrollingFrame")
pickerScroll.Size = UDim2.new(1, -12, 1, -34)
pickerScroll.Position = UDim2.new(0, 6, 0, 30)
pickerScroll.BackgroundTransparency = 1
pickerScroll.BorderSizePixel = 0
pickerScroll.ScrollBarThickness = 3
pickerScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
pickerScroll.Parent = pickerGui

local pickerLayout = Instance.new("UIListLayout")
pickerLayout.Padding = UDim.new(0, 3)
pickerLayout.Parent = pickerScroll

local pickerMode = "white"

local function inList(list, name)
    for _, n in ipairs(list) do if n == name then return true end end
    return false
end

local function toggleInList(list, name)
    if inList(list, name) then
        for i = #list, 1, -1 do if list[i] == name then table.remove(list, i) end end
    else
        table.insert(list, name)
    end
end

local function updateListCounts()
    wlBtn.Text = "WHITELIST: " .. #whitelist
    blBtn.Text = "BLACKLIST: " .. #blacklist
end

-- (v9) estas dos van antes del selector: rebuildPicker usa myRoot()
local function myRoot()
    local c = localPlayer.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end

local function myHum()
    local c = localPlayer.Character
    return c and c:FindFirstChildOfClass("Humanoid")
end

local rebuildPicker
do
    -- v8: selector con avatar, buscador por usuario de Roblox y orden por cercania (solo desde la lista)
    local thumbCache = {}

    local sb = Instance.new("TextBox")
    sb.Name = "ZeidopSearch"
    sb.Text = ""
    sb.PlaceholderText = "Buscar jugador..."
    sb.PlaceholderColor3 = Color3.fromRGB(130, 130, 150)
    sb.TextColor3 = Color3.fromRGB(235, 235, 245)
    sb.TextSize = 13
    sb.Font = Enum.Font.Gotham
    sb.TextXAlignment = Enum.TextXAlignment.Left
    sb.ClearTextOnFocus = false
    sb.BackgroundColor3 = Color3.fromRGB(28, 28, 36)
    sb.BorderSizePixel = 0
    sb.Position = UDim2.new(0, 8, 0, 34)
    sb.Size = UDim2.new(1, -56, 0, 30)
    sb.Parent = pickerGui
    Instance.new("UICorner", sb).CornerRadius = UDim.new(0, 8)
    local pad = Instance.new("UIPadding", sb)
    pad.PaddingLeft = UDim.new(0, 8)

    local rf = Instance.new("TextButton")
    rf.Name = "ZeidopRefresh"
    rf.Text = "🔄"
    rf.TextSize = 14
    rf.Font = Enum.Font.GothamBold
    rf.TextColor3 = Color3.fromRGB(255, 255, 255)
    rf.BackgroundColor3 = Color3.fromRGB(45, 45, 60)
    rf.BorderSizePixel = 0
    rf.Position = UDim2.new(1, -44, 0, 34)
    rf.Size = UDim2.new(0, 36, 0, 30)
    rf.Parent = pickerGui
    Instance.new("UICorner", rf).CornerRadius = UDim.new(0, 8)

    pickerLayout.SortOrder = Enum.SortOrder.LayoutOrder

    -- miniatura de la cabeza del jugador (se guarda para no pedirla otra vez)
    local function thumb(img, userId)
        local c = thumbCache[userId]
        if c then
            img.Image = c
            return
        end
        task.spawn(function()
            local ok, url = pcall(function()
                return (Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48))
            end)
            if ok and url then
                thumbCache[userId] = url
                if img and img.Parent then img.Image = url end
            end
        end)
    end

    rebuildPicker = function()
        for _, ch in ipairs(pickerScroll:GetChildren()) do
            if ch:IsA("Frame") then ch:Destroy() end
        end
        if pickerMode == "white" then
            pickerTitle.Text = "WHITELIST (aliados)"
            pickerTitle.TextColor3 = Color3.fromRGB(110, 255, 130)
        else
            pickerTitle.Text = "BLACKLIST (objetivos)"
            pickerTitle.TextColor3 = Color3.fromRGB(255, 120, 120)
        end
        local list = (pickerMode == "white") and whitelist or blacklist

        -- jugadores filtrados por el buscador y ordenados del mas cercano al mas lejano
        local q = string.lower(sb.Text or "")
        local mr = myRoot()
        local arr = {}
        for _, pl in ipairs(Players:GetPlayers()) do
            if pl ~= localPlayer then
                local nm = string.lower(pl.Name)
                if q == "" or string.find(nm, q, 1, true) then
                    local d = math.huge
                    local r = pl.Character and pl.Character:FindFirstChild("HumanoidRootPart")
                    if r and mr then d = (r.Position - mr.Position).Magnitude end
                    arr[#arr + 1] = { pl = pl, d = d }
                end
            end
        end
        table.sort(arr, function(a, b)
            if a.d ~= b.d then return a.d < b.d end
            return a.pl.Name < b.pl.Name
        end)

        if #arr == 0 then
            local empty = Instance.new("Frame")
            empty.LayoutOrder = 1
            empty.Size = UDim2.new(1, -4, 0, 36)
            empty.BackgroundTransparency = 1
            empty.Parent = pickerScroll
            local et = Instance.new("TextLabel")
            et.BackgroundTransparency = 1
            et.Size = UDim2.new(1, 0, 1, 0)
            et.Font = Enum.Font.Gotham
            et.TextSize = 12
            et.TextColor3 = Color3.fromRGB(130, 130, 150)
            et.Text = "Sin resultados"
            et.Parent = empty
        end

        for i, it in ipairs(arr) do
            local pl = it.pl
            local member = inList(list, pl.Name)
            local row = Instance.new("Frame")
            row.LayoutOrder = i
            row.Size = UDim2.new(1, -4, 0, 44)
            row.BackgroundColor3 = Color3.fromRGB(28, 28, 36)
            row.BorderSizePixel = 0
            row.Parent = pickerScroll
            Instance.new("UICorner", row).CornerRadius = UDim.new(0, 8)

            local av = Instance.new("ImageLabel")
            av.BackgroundColor3 = Color3.fromRGB(45, 45, 60)
            av.BorderSizePixel = 0
            av.Position = UDim2.new(0, 4, 0, 4)
            av.Size = UDim2.new(0, 36, 0, 36)
            av.Parent = row
            Instance.new("UICorner", av).CornerRadius = UDim.new(1, 0)
            thumb(av, pl.UserId)

            local top = Instance.new("TextLabel")
            top.BackgroundTransparency = 1
            top.Position = UDim2.new(0, 46, 0, 4)
            top.Size = UDim2.new(1, -128, 0, 18)
            top.Font = Enum.Font.GothamBold
            top.TextSize = 13
            top.TextColor3 = Color3.fromRGB(235, 235, 245)
            top.TextXAlignment = Enum.TextXAlignment.Left
            top.TextTruncate = Enum.TextTruncate.AtEnd
            top.Text = pl.Name
            top.Parent = row

            local sub = Instance.new("TextLabel")
            sub.BackgroundTransparency = 1
            sub.Position = UDim2.new(0, 46, 0, 23)
            sub.Size = UDim2.new(1, -128, 0, 16)
            sub.Font = Enum.Font.Gotham
            sub.TextSize = 10
            sub.TextColor3 = Color3.fromRGB(140, 140, 160)
            sub.TextXAlignment = Enum.TextXAlignment.Left
            sub.TextTruncate = Enum.TextTruncate.AtEnd
            local dtxt = (it.d < math.huge) and (math.floor(it.d + 0.5) .. " studs") or "sin personaje"
            sub.Text = dtxt
            sub.Parent = row

            local act = Instance.new("TextButton")
            act.Size = UDim2.new(0, 70, 0, 28)
            act.Position = UDim2.new(1, -76, 0, 8)
            act.BackgroundColor3 = member and Color3.fromRGB(160, 50, 50) or Color3.fromRGB(45, 160, 70)
            act.Text = member and "QUITAR" or "AGREGAR"
            act.TextColor3 = Color3.fromRGB(255, 255, 255)
            act.TextSize = 10
            act.Font = Enum.Font.GothamBold
            act.BorderSizePixel = 0
            act.Parent = row
            Instance.new("UICorner", act).CornerRadius = UDim.new(0, 6)

            act.MouseButton1Click:Connect(function()
                toggleInList(list, pl.Name)
                updateListCounts()
                rebuildPicker()
            end)
        end
    end

    rf.MouseButton1Click:Connect(function() rebuildPicker() end)
    sb:GetPropertyChangedSignal("Text"):Connect(function() rebuildPicker() end)
    Players.PlayerAdded:Connect(function()
        if pickerGui.Visible then rebuildPicker() end
    end)
end

local function openPicker(mode)
    pickerMode = mode
    pickerGui.Visible = true
    local sbx = pickerGui:FindFirstChild("ZeidopSearch")
    if sbx and sbx.Text ~= "" then
        sbx.Text = "" -- dispara el rebuild
    else
        rebuildPicker()
    end
end

wlBtn.MouseButton1Click:Connect(function() openPicker("white") end)
blBtn.MouseButton1Click:Connect(function() openPicker("black") end)
pickerClose.MouseButton1Click:Connect(function() pickerGui.Visible = false end)

-- IMAN / LUNGE
local reachOn = true
local imanOn = false
local lungeOn = true
local fuerza = 4
local lungeReach = 6
local maxRange = 14
local stopRange = 5
local lastLunge = 0

local function rBtn(text, y, color)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, 0, 0, 22)
    b.Position = UDim2.new(0, 0, 0, y)
    b.BackgroundColor3 = color
    b.Text = text
    b.TextColor3 = Color3.fromRGB(255, 255, 255)
    b.TextSize = 10
    b.Font = Enum.Font.GothamBold
    b.BorderSizePixel = 0
    b.Parent = listPage
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
    return b
end

local imanBtn = rBtn("IMAN: OFF", 106, Color3.fromRGB(160, 50, 50))
local lungeBtn = rBtn("LUNGE: ON", 130, Color3.fromRGB(45, 160, 70))
local fuerzaBtn = rBtn("Fuerza: 4", 154, Color3.fromRGB(70, 130, 220))

local function nearestEnemy()
    local r0 = myRoot()
    if not r0 then return nil, math.huge end
    local best, bd = nil, math.huge
    for _, pl in ipairs(Players:GetPlayers()) do
        if pl ~= localPlayer and pl.Character then
            local r = pl.Character:FindFirstChild("HumanoidRootPart")
            local h = pl.Character:FindFirstChildOfClass("Humanoid")
            if r and h and h.Health > 0 then
                if not inList(whitelist, pl.Name) then
                    local d = (r.Position - r0.Position).Magnitude
                    if d < bd then bd = d best = r end
                end
            end
        end
    end
    return best, bd
end

RunService.Heartbeat:Connect(function()
    if not reachOn or not imanOn then return end
    local hum = myHum(); local r0 = myRoot()
    if not hum or not r0 or hum.Health <= 0 then return end
    local t, d = nearestEnemy()
    if not t or d > maxRange or d <= stopRange then return end
    local dir = t.Position - r0.Position
    dir = Vector3.new(dir.X, 0, dir.Z)
    if dir.Magnitude > 0 then
        dir = dir.Unit
        local step = math.min(d - stopRange, fuerza * 0.05)
        pcall(function() r0.CFrame = r0.CFrame + dir * step end)
    end
end)

local function doLunge()
    if not reachOn or not lungeOn then return end
    if tick() - lastLunge < 0.25 then return end
    local hum = myHum(); local r0 = myRoot()
    if not hum or not r0 or hum.Health <= 0 then return end
    local t, d = nearestEnemy()
    if not t then return end
    local melee = 6
    local maxL = melee + lungeReach + 4
    if d < melee or d > maxL then return end
    local step = math.min(lungeReach, d - melee + 1)
    local dir = t.Position - r0.Position
    dir = Vector3.new(dir.X, 0, dir.Z)
    if dir.Magnitude > 0 then
        dir = dir.Unit
        lastLunge = tick()
        pcall(function() r0.CFrame = r0.CFrame + dir * step end)
    end
end

local function hookAnims(hum)
    local anim = hum and hum:FindFirstChildOfClass("Animator")
    if not anim then return end
    anim.AnimationPlayed:Connect(function(track)
        local n = (track.Animation and track.Animation.Name or ""):lower()
        if n:match("attack") or n:match("punch") or n:match("m1") or n:match("slash") or n:match("swing") or n:match("combo") or n:match("jab") or n:match("hit") or n:match("strike") then
            doLunge()
        end
    end)
end

if localPlayer.Character then hookAnims(localPlayer.Character:FindFirstChildOfClass("Humanoid")) end
localPlayer.CharacterAdded:Connect(function(c) hookAnims(c:FindFirstChildOfClass("Humanoid")) end)

local atkConn = false
local function tryAtkBtn()
    if atkConn then return end
    for _, gui in ipairs(playerGui:GetChildren()) do
        if gui:IsA("ScreenGui") and gui.Name ~= "ZeidopHub" then
            for _, o in ipairs(gui:GetDescendants()) do
                if (o:IsA("TextButton") or o:IsA("ImageButton")) then
                    local n = o.Name:lower()
                    if n:match("attack") or n:match("m1") or n:match("punch") or n:match("combat") or n:match("fight") or n:match("swing") or n:match("hit") or n:match("strike") or n:match("melee") then
                        o.Activated:Connect(doLunge)
                        atkConn = true
                        return
                    end
                end
            end
        end
    end
end
task.spawn(function() while not atkConn do task.wait(3) tryAtkBtn() end end)

imanBtn.MouseButton1Click:Connect(function()
    imanOn = not imanOn
    imanBtn.Text = "IMAN: " .. (imanOn and "ON" or "OFF")
    imanBtn.BackgroundColor3 = imanOn and Color3.fromRGB(45, 160, 70) or Color3.fromRGB(160, 50, 50)
end)

lungeBtn.MouseButton1Click:Connect(function()
    lungeOn = not lungeOn
    lungeBtn.Text = "LUNGE: " .. (lungeOn and "ON" or "OFF")
    lungeBtn.BackgroundColor3 = lungeOn and Color3.fromRGB(45, 160, 70) or Color3.fromRGB(160, 50, 50)
end)

fuerzaBtn.MouseButton1Click:Connect(function()
    fuerza = fuerza + 1
    if fuerza > 10 then fuerza = 1 end
    fuerzaBtn.Text = "Fuerza: " .. fuerza
end)

-- ============================================
-- SISTEMA DE PESTAÑAS
-- ============================================
local tabs = {
    {btn = tabLock, page = lockPage},
    {btn = tabNoStun, page = noStunPage},
    {btn = tabDash, page = dashPage},
    {btn = tabList, page = listPage}
}

local function setActiveTab(index)
    for i, data in ipairs(tabs) do
        if i == index then
            data.page.Visible = true
            data.btn.BackgroundColor3 = Color3.fromRGB(80, 60, 140)
            data.btn.TextColor3 = Color3.fromRGB(255, 255, 255)
        else
            data.page.Visible = false
            data.btn.BackgroundColor3 = Color3.fromRGB(35, 35, 50)
            data.btn.TextColor3 = Color3.fromRGB(180, 180, 190)
        end
    end
end

tabLock.MouseButton1Click:Connect(function() setActiveTab(1) end)
tabNoStun.MouseButton1Click:Connect(function() setActiveTab(2) end)
tabDash.MouseButton1Click:Connect(function() setActiveTab(3) end)
tabList.MouseButton1Click:Connect(function() setActiveTab(4) end)

-- ============================================
-- BOTONES FLOTANTES
-- ============================================
local lockButton = Instance.new("TextButton")
lockButton.Size = UDim2.new(0, config.buttonSize, 0, config.buttonSize)
lockButton.Position = UDim2.new(config.lockBtnXScale, config.lockBtnXOffset, config.lockBtnYScale, config.lockBtnYOffset)
lockButton.BackgroundColor3 = Color3.fromRGB(190, 45, 45)
lockButton.Text = "LOCK"
lockButton.TextColor3 = Color3.fromRGB(255, 255, 255)
lockButton.TextSize = 14
lockButton.Font = Enum.Font.GothamBold
lockButton.BorderSizePixel = 0
lockButton.Active = true
lockButton.Visible = config.buttonVisible
lockButton.Parent = screenGui
Instance.new("UICorner", lockButton).CornerRadius = UDim.new(1, 0)

local lockStroke = Instance.new("UIStroke")
lockStroke.Color = Color3.fromRGB(0, 0, 0)
lockStroke.Thickness = 1.5
lockStroke.Transparency = 0.3
lockStroke.Parent = lockButton

local miniMenuBtn = Instance.new("TextButton")
miniMenuBtn.Size = UDim2.new(0, 46, 0, 46)
miniMenuBtn.Position = UDim2.new(0.02, 0, 0.15, 0)
miniMenuBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
miniMenuBtn.Text = LOGO_ID > 0 and "" or "Z"
miniMenuBtn.TextColor3 = Color3.fromRGB(160, 120, 255)
miniMenuBtn.TextSize = 18
miniMenuBtn.Font = Enum.Font.GothamBlack
miniMenuBtn.BorderSizePixel = 0
miniMenuBtn.Visible = false
miniMenuBtn.Active = true
miniMenuBtn.Parent = screenGui
Instance.new("UICorner", miniMenuBtn).CornerRadius = UDim.new(1, 0)

local miniStroke = Instance.new("UIStroke")
miniStroke.Color = Color3.fromRGB(160, 120, 255)
miniStroke.Thickness = 2
miniStroke.Parent = miniMenuBtn

local miniLogo = Instance.new("ImageLabel")
miniLogo.Size = UDim2.new(1, -8, 1, -8)
miniLogo.Position = UDim2.new(0, 4, 0, 4)
miniLogo.BackgroundTransparency = 1
miniLogo.Image = LOGO_ID > 0 and ("rbxassetid://" .. LOGO_ID) or ""
miniLogo.Parent = miniMenuBtn
Instance.new("UICorner", miniLogo).CornerRadius = UDim.new(1, 0)

local jumpBtn = Instance.new("TextButton")
jumpBtn.Size = UDim2.new(0, config.jumpBtnSize, 0, config.jumpBtnSize)
jumpBtn.Position = UDim2.new(0.72, 0, 0.68, 0)
jumpBtn.BackgroundColor3 = Color3.fromRGB(80, 60, 140)
jumpBtn.Text = "JUMP"
jumpBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
jumpBtn.TextSize = 14
jumpBtn.Font = Enum.Font.GothamBold
jumpBtn.BorderSizePixel = 0
jumpBtn.Visible = false
jumpBtn.Parent = screenGui
Instance.new("UICorner", jumpBtn).CornerRadius = UDim.new(1, 0)

local jbStroke = Instance.new("UIStroke")
jbStroke.Color = Color3.fromRGB(0, 0, 0)
jbStroke.Thickness = 1.5
jbStroke.Transparency = 0.3
jbStroke.Parent = jumpBtn

local dashFloatBtn = Instance.new("TextButton")
dashFloatBtn.Size = UDim2.new(0, config.dashBtnSize, 0, config.dashBtnSize)
dashFloatBtn.Position = UDim2.new(0.72, 0, 0.55, 0)
dashFloatBtn.BackgroundColor3 = Color3.fromRGB(70, 130, 220)
dashFloatBtn.Text = "DASH"
dashFloatBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
dashFloatBtn.TextSize = 14
dashFloatBtn.Font = Enum.Font.GothamBold
dashFloatBtn.BorderSizePixel = 0
dashFloatBtn.Visible = false
dashFloatBtn.Parent = screenGui
Instance.new("UICorner", dashFloatBtn).CornerRadius = UDim.new(1, 0)

local dfStroke = Instance.new("UIStroke")
dfStroke.Color = Color3.fromRGB(0, 0, 0)
dfStroke.Thickness = 1.5
dfStroke.Transparency = 0.3
dfStroke.Parent = dashFloatBtn

-- ============================================
-- ARRASTRE
-- ============================================
local function makeDraggable(gui, condition)
    local dragging = false
    local dragStart = nil
    local startPos = nil
    gui.InputBegan:Connect(function(input)
        if not condition() then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = gui.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                    if gui == lockButton then
                        config.lockBtnXScale = lockButton.Position.X.Scale
                        config.lockBtnXOffset = lockButton.Position.X.Offset
                        config.lockBtnYScale = lockButton.Position.Y.Scale
                        config.lockBtnYOffset = lockButton.Position.Y.Offset
                        saveConfig()
                    end
                end
            end)
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if not dragging then return end
        if not condition() then return end
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            local delta = input.Position - dragStart
            gui.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)
end

makeDraggable(menuFrame, function() return true end)
makeDraggable(miniMenuBtn, function() return true end)
makeDraggable(lockButton, function() return config.isDraggable end)
makeDraggable(jumpBtn, function() return not stunLocked end)
makeDraggable(dashFloatBtn, function() return not stunLocked end)
makeDraggable(pickerGui, function() return true end)

-- ============================================
-- FUNCIONES ANTI-STUN Y DASH
-- ============================================
local character = nil
local humanoid = nil
local rootPart = nil

task.spawn(function()
    local char = localPlayer.Character or localPlayer.CharacterAdded:Wait()
    character = char
    humanoid = char:FindFirstChildOfClass("Humanoid")
    rootPart = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso")
end)

local function jump()
    if not humanoid or not rootPart or not jumping then return end
    jumping = false
    pcall(function()
        humanoid.PlatformStand = true
        rootPart.Velocity = Vector3.zero
        task.wait()
        rootPart.Velocity = Vector3.new(0, config.jumpPower, 0)
        humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
        task.wait(0.05)
        humanoid.PlatformStand = false
    end)
    task.wait(1.2)
    jumping = true
end

local function dash()
    if not humanoid or not rootPart then return end
    pcall(function()
        local lookVector = rootPart.CFrame.LookVector
        rootPart.Velocity = Vector3.new(lookVector.X * config.dashForce, rootPart.Velocity.Y, lookVector.Z * config.dashForce)
    end)
end

local function hookDash()
    local char = localPlayer.Character
    if not char then return end
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return end
    root.ChildAdded:Connect(function(child)
        if not config.dashEnabled then return end
        if child:IsA("BodyVelocity") or child:IsA("LinearVelocity") then
            task.wait()
            pcall(function()
                if child:IsA("BodyVelocity") then
                    child.Velocity = child.Velocity * config.dashMultiplier
                elseif child:IsA("LinearVelocity") then
                    child.VectorVelocity = child.VectorVelocity * config.dashMultiplier
                end
            end)
        end
    end)
end

-- ============================================
-- CEREBRO AUTO LOCK (Distancia 3D + Cámara Directa)
-- ============================================
local function getClosestPlayer()
    Camera = workspace.CurrentCamera
    if not Camera then return nil end
    local vp = Camera.ViewportSize
    local screenCenter = Vector2.new(vp.X / 2, vp.Y / 2)
    local myChar = localPlayer.Character
    local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
    
    local function valid(pl)
        if pl == localPlayer or not pl.Character then return nil end
        if inList(whitelist, pl.Name) then return nil end
        local root = pl.Character:FindFirstChild("HumanoidRootPart")
        local hum = pl.Character:FindFirstChildOfClass("Humanoid")
        if root and hum and hum.Health > 0 then return root end
        return nil
    end
    
    if #blacklist > 0 then
        local best, bestDist = nil, math.huge
        for _, name in ipairs(blacklist) do
            local pl = Players:FindFirstChild(name)
            if pl then
                local root = valid(pl)
                if root and myRoot then
                    local d = (root.Position - myRoot.Position).Magnitude
                    if d < bestDist then bestDist = d best = pl end
                end
            end
        end
        if best then return best end
    end
    
    local closestPlayer = nil
    local shortestDistance = math.huge
    for _, player in pairs(Players:GetPlayers()) do
        local root = valid(player)
        if root then
            local distance
            if config.useDistance3D and myRoot then
                distance = (root.Position - myRoot.Position).Magnitude
            else
                local screenPos, onScreen = Camera:WorldToViewportPoint(root.Position)
                if onScreen and screenPos.Z > 0 then
                    distance = (Vector2.new(screenPos.X, screenPos.Y) - screenCenter).Magnitude
                else
                    distance = math.huge
                end
            end
            if distance < shortestDistance then
                shortestDistance = distance
                closestPlayer = player
            end
        end
    end
    return closestPlayer
end

local FACE_TARGET = true
local lockAimPos = nil
local FACE_BIND_NAME = "ZeidopLockFace"

local function resetLock()
    targetLock = false
    lockedPlayer = nil
    lockAimPos = nil
    lockButton.BackgroundColor3 = Color3.fromRGB(190, 45, 45)
    lockButton.Text = "LOCK"
    TH.reset(nil)
end

local function toggleLock()
    if not targetLock then
        local closest = getClosestPlayer()
        if closest then
            lockedPlayer = closest
            targetLock = true
            lockButton.BackgroundColor3 = Color3.fromRGB(45, 170, 70)
            lockButton.Text = "ON"
            TH.reset(nil)
        end
    else
        resetLock()
    end
end

lockButton.MouseButton1Click:Connect(toggleLock)

local MAX_LEAD_RATIO = 0.20

local function cameraLockStep(dt)
    if not targetLock or not lockedPlayer or not lockedPlayer.Character then return end

    if inList(whitelist, lockedPlayer.Name) then resetLock() return end
    if #blacklist > 0 and not inList(blacklist, lockedPlayer.Name) then
        local b = getClosestPlayer()
        if b then lockedPlayer = b else resetLock() return end
    end

    Camera = workspace.CurrentCamera
    if not Camera then return end

    local root = lockedPlayer.Character:FindFirstChild("HumanoidRootPart")
    local hum = lockedPlayer.Character:FindFirstChildOfClass("Humanoid")
    if not root or not hum or hum.Health <= 0 then resetLock() return end

    local aimPart = root
    if config.lockPart == "head" then
        local head = lockedPlayer.Character:FindFirstChild("Head")
        if head then aimPart = head end
    end

    local targetPos = aimPart.Position
    local aimPosition = targetPos

    -- v9: el historial se alimenta siempre (asi ya esta listo si enciendes el predict con lock activo)
    TH.push(os.clock(), root)

    if config.predictEnabled then
        local vel = TH.velocity(root)

        if vel.Magnitude >= 1.5 then
            local toTarget = targetPos - Camera.CFrame.Position
            local dist = toTarget.Magnitude
            if dist > 0.1 then
                local dir = toTarget.Unit
                local velPerp = vel - dir * vel:Dot(dir)
                -- predict efectivo = el tuyo + ajuste por ping/FPS (config.liveComp, en segundos)
                local pt = PREDICT_TIME
                if PREDICT_TIME > 0 then pt = PREDICT_TIME + (config.liveComp or 0) end
                local lead = velPerp * pt

                -- tope original del lock (ya no depende del ajuste de ping)
                local maxLead = math.min(dist * MAX_LEAD_RATIO, 16)
                if lead.Magnitude > maxLead then
                    lead = lead.Unit * maxLead
                end

                aimPosition = targetPos + lead
            end
        end
    end

    lockAimPos = aimPosition

    -- MODO LIBRE: no tocar la cámara, solo actualizar lockAimPos
    if config.lockFree then return end

    -- MODO NORMAL: mover la cámara hacia el objetivo
    local camPos = Camera.CFrame.Position
    local look = aimPosition - camPos
    if look.Magnitude < 0.1 then return end
    look = look.Unit

    if config.aboveView and #blacklist > 0 and inList(blacklist, lockedPlayer.Name) then
        local flat = Vector3.new(look.X, 0, look.Z)
        if flat.Magnitude > 0.01 then
            local fu = flat.Unit
            local pitch = math.atan2(look.Y, flat.Magnitude) - math.rad(config.aboveHeight)
            pitch = math.clamp(pitch, -math.rad(80), math.rad(80))
            look = Vector3.new(fu.X * math.cos(pitch), math.sin(pitch), fu.Z * math.cos(pitch))
        end
    end

    Camera.CFrame = CFrame.new(camPos, camPos + look)
end

local function faceStep()
    if not FACE_TARGET or not targetLock or not lockAimPos then return end
    local mr, mh = myRoot(), myHum()
    if not mr or not mh or mh.Health <= 0 or mh.PlatformStand or mh.Sit then return end

    local p = mr.Position

    if config.lockFree then
        -- MODO LIBRE: girar el personaje directamente hacia el objetivo
        local d = lockAimPos - p
        local flat = Vector3.new(d.X, 0, d.Z)
        if flat.Magnitude > 0.05 then
            mr.CFrame = CFrame.new(p, p + flat)
        end
    else
        -- MODO NORMAL: girar el personaje hacia donde mira la cámara
        local cam = workspace.CurrentCamera
        if not cam then return end
        local look = cam.CFrame.LookVector
        local flat = Vector3.new(look.X, 0, look.Z)
        if flat.Magnitude > 0.05 then
            mr.CFrame = CFrame.new(p, p + flat)
        end
    end
end

pcall(function() RunService:UnbindFromRenderStep(FACE_BIND_NAME) end)
RunService:BindToRenderStep(FACE_BIND_NAME, Enum.RenderPriority.Last.Value, faceStep)

local CAM_PRIORITY = (Enum.RenderPriority.Camera.Value - 1)
RunService:BindToRenderStep(CAMERA_LOCK_NAME, CAM_PRIORITY, cameraLockStep)

-- ============================================
-- EVENTOS DEL MENÚ LOCK
-- ============================================
showBtn.MouseButton1Click:Connect(function()
    config.buttonVisible = not config.buttonVisible
    lockButton.Visible = config.buttonVisible
    showBtn.Text = config.buttonVisible and "Boton: Visible" or "Boton: Oculto"
    showBtn.BackgroundColor3 = config.buttonVisible and Color3.fromRGB(45, 160, 70) or Color3.fromRGB(160, 50, 50)
    saveConfig()
end)

dragBtn.MouseButton1Click:Connect(function()
    config.isDraggable = not config.isDraggable
    dragBtn.Text = "Arrastrable: " .. (config.isDraggable and "ON" or "OFF")
    dragBtn.BackgroundColor3 = config.isDraggable and Color3.fromRGB(45, 160, 70) or Color3.fromRGB(160, 50, 50)
    saveConfig()
end)

sizeMinus.MouseButton1Click:Connect(function()
    config.buttonSize = math.max(35, config.buttonSize - 5)
    lockButton.Size = UDim2.new(0, config.buttonSize, 0, config.buttonSize)
    sizeLabel.Text = "Tamano: " .. tostring(config.buttonSize)
    saveConfig()
end)

sizePlus.MouseButton1Click:Connect(function()
    config.buttonSize = math.min(90, config.buttonSize + 5)
    lockButton.Size = UDim2.new(0, config.buttonSize, 0, config.buttonSize)
    sizeLabel.Text = "Tamano: " .. tostring(config.buttonSize)
    saveConfig()
end)

predictMinus.MouseButton1Click:Connect(function()
    config.predictAmount = math.max(0, config.predictAmount - 0.001)
    config.predictAmount = math.floor(config.predictAmount * 1000 + 0.5) / 1000
    PREDICT_TIME = config.predictAmount
    predictLabel.Text = string.format("Predict: %.3fs", config.predictAmount)
    saveConfig()
end)

predictPlus.MouseButton1Click:Connect(function()
    config.predictAmount = math.min(0.5, config.predictAmount + 0.001)
    config.predictAmount = math.floor(config.predictAmount * 1000 + 0.5) / 1000
    PREDICT_TIME = config.predictAmount
    predictLabel.Text = string.format("Predict: %.3fs", config.predictAmount)
    saveConfig()
end)

predictToggle.MouseButton1Click:Connect(function()
    config.predictEnabled = not config.predictEnabled
    predictToggle.Text = config.predictEnabled and "ON" or "OFF"
    predictToggle.BackgroundColor3 = config.predictEnabled and Color3.fromRGB(45, 160, 70) or Color3.fromRGB(160, 50, 50)
    predictLabel.TextColor3 = config.predictEnabled and Color3.fromRGB(255, 220, 130) or Color3.fromRGB(150, 150, 150)
    saveConfig()
end)

dist3DBtn.MouseButton1Click:Connect(function()
    config.useDistance3D = not config.useDistance3D
    dist3DBtn.Text = "Direct 3D: " .. (config.useDistance3D and "ON" or "OFF")
    dist3DBtn.BackgroundColor3 = config.useDistance3D and Color3.fromRGB(45, 160, 70) or Color3.fromRGB(160, 50, 50)
    saveConfig()
end)

transBtn.MouseButton1Click:Connect(function()
    config.menuTransparency = config.menuTransparency + 0.15
    if config.menuTransparency > 0.75 then config.menuTransparency = 0 end
    menuFrame.BackgroundTransparency = config.menuTransparency
    transBtn.Text = "Transp: " .. tostring(math.floor(config.menuTransparency * 100 + 0.5)) .. "%"
    saveConfig()
end)

partBtn.MouseButton1Click:Connect(function()
    config.lockPart = (config.lockPart == "torso") and "head" or "torso"
    partBtn.Text = "Parte: " .. (config.lockPart == "head" and "Cabeza" or "Torso")
    partBtn.BackgroundColor3 = config.lockPart == "head" and Color3.fromRGB(160, 50, 50) or Color3.fromRGB(70, 130, 220)
    saveConfig()
end)

keyBtn.MouseButton1Click:Connect(function()
    listeningForKey = not listeningForKey
    keyBtn.Text = listeningForKey and "Presiona..." or ("Tecla: " .. lockKey.Name)
    keyBtn.BackgroundColor3 = listeningForKey and Color3.fromRGB(255, 220, 130) or Color3.fromRGB(70, 130, 220)
    keyBtn.TextColor3 = listeningForKey and Color3.fromRGB(20, 20, 20) or Color3.fromRGB(255, 255, 255)
end)

aboveBtn.MouseButton1Click:Connect(function()
    config.aboveView = not config.aboveView
    aboveBtn.Text = "Above: " .. (config.aboveView and "ON" or "OFF")
    aboveBtn.BackgroundColor3 = config.aboveView and Color3.fromRGB(45, 160, 70) or Color3.fromRGB(160, 50, 50)
    saveConfig()
end)

aboveHeightBtn.MouseButton1Click:Connect(function()
    local h = config.aboveHeight + 3
    if h > 24 then h = 6 end
    config.aboveHeight = h
    aboveHeightBtn.Text = "Altura: " .. h
    saveConfig()
end)

modeBtn.MouseButton1Click:Connect(function()
    config.lockFree = not config.lockFree
    modeBtn.Text = "Modo: " .. (config.lockFree and "LIBRE" or "NORMAL")
    modeBtn.BackgroundColor3 = config.lockFree and Color3.fromRGB(80, 60, 140) or Color3.fromRGB(70, 130, 220)
    saveConfig()
end)

minBtn.MouseButton1Click:Connect(function()
    menuFrame.Visible = false
    miniMenuBtn.Visible = true
    miniMenuBtn.Position = menuFrame.Position
    saveConfig()
end)

miniMenuBtn.MouseButton1Click:Connect(function()
    miniMenuBtn.Visible = false
    menuFrame.Visible = true
    menuFrame.Position = miniMenuBtn.Position
end)

-- ============================================
-- EVENTOS STUN
-- ============================================
local function updateNsToggle()
    nsToggleBtn.Text = config.antiStun and "ANTI-STUN: ON" or "ANTI-STUN: OFF"
    nsToggleBtn.BackgroundColor3 = config.antiStun and Color3.fromRGB(45, 160, 70) or Color3.fromRGB(160, 50, 50)
end

nsToggleBtn.MouseButton1Click:Connect(function()
    config.antiStun = not config.antiStun
    jumping = true
    updateNsToggle()
    saveConfig()
end)

nsJumpMinus.MouseButton1Click:Connect(function()
    config.jumpPower = math.max(10, config.jumpPower - 5)
    nsJumpLabel.Text = "Jump Power: " .. config.jumpPower
    saveConfig()
end)
nsJumpPlus.MouseButton1Click:Connect(function()
    config.jumpPower = math.min(150, config.jumpPower + 5)
    nsJumpLabel.Text = "Jump Power: " .. config.jumpPower
    saveConfig()
end)
nsDashMinus.MouseButton1Click:Connect(function()
    config.dashForce = math.max(10, config.dashForce - 5)
    nsDashLabel.Text = "Dash Force: " .. config.dashForce
    saveConfig()
end)
nsDashPlus.MouseButton1Click:Connect(function()
    config.dashForce = math.min(150, config.dashForce + 5)
    nsDashLabel.Text = "Dash Force: " .. config.dashForce
    saveConfig()
end)
nsJumpSizeMinus.MouseButton1Click:Connect(function()
    config.jumpBtnSize = math.max(30, config.jumpBtnSize - 2)
    jumpBtn.Size = UDim2.new(0, config.jumpBtnSize, 0, config.jumpBtnSize)
    nsJumpSizeLabel.Text = "Jump Size: " .. config.jumpBtnSize
    saveConfig()
end)
nsJumpSizePlus.MouseButton1Click:Connect(function()
    config.jumpBtnSize = math.min(100, config.jumpBtnSize + 2)
    jumpBtn.Size = UDim2.new(0, config.jumpBtnSize, 0, config.jumpBtnSize)
    nsJumpSizeLabel.Text = "Jump Size: " .. config.jumpBtnSize
    saveConfig()
end)
nsDashSizeMinus.MouseButton1Click:Connect(function()
    config.dashBtnSize = math.max(30, config.dashBtnSize - 2)
    dashFloatBtn.Size = UDim2.new(0, config.dashBtnSize, 0, config.dashBtnSize)
    nsDashSizeLabel.Text = "Dash Size: " .. config.dashBtnSize
    saveConfig()
end)
nsDashSizePlus.MouseButton1Click:Connect(function()
    config.dashBtnSize = math.min(100, config.dashBtnSize + 2)
    dashFloatBtn.Size = UDim2.new(0, config.dashBtnSize, 0, config.dashBtnSize)
    nsDashSizeLabel.Text = "Dash Size: " .. config.dashBtnSize
    saveConfig()
end)
nsJumpGenBtn.MouseButton1Click:Connect(function() jumpBtn.Visible = not jumpBtn.Visible end)
nsDashGenBtn.MouseButton1Click:Connect(function() dashFloatBtn.Visible = not dashFloatBtn.Visible end)
nsLockBtn.MouseButton1Click:Connect(function()
    stunLocked = not stunLocked
    nsLockBtn.Text = stunLocked and "LOCK FLOAT: ON" or "LOCK FLOAT: OFF"
    nsLockBtn.BackgroundColor3 = stunLocked and Color3.fromRGB(180, 60, 60) or Color3.fromRGB(90, 90, 100)
end)
jumpBtn.MouseButton1Click:Connect(function() jump() end)
dashFloatBtn.MouseButton1Click:Connect(function() dash() end)

-- ============================================
-- EVENTOS DASH
-- ============================================
dashMinusBtn.MouseButton1Click:Connect(function()
    config.dashMultiplier = math.max(0.5, config.dashMultiplier - 0.1)
    dashValueLabel.Text = string.format("Multiplicador: %.1fx", config.dashMultiplier)
    saveConfig()
end)
dashPlusBtn.MouseButton1Click:Connect(function()
    config.dashMultiplier = math.min(4, config.dashMultiplier + 0.1)
    dashValueLabel.Text = string.format("Multiplicador: %.1fx", config.dashMultiplier)
    saveConfig()
end)
dashToggleBtn.MouseButton1Click:Connect(function()
    config.dashEnabled = not config.dashEnabled
    dashToggleBtn.BackgroundColor3 = config.dashEnabled and Color3.fromRGB(45, 160, 70) or Color3.fromRGB(160, 50, 50)
    dashToggleBtn.Text = config.dashEnabled and "ACTIVADO" or "DESACTIVADO"
    saveConfig()
end)
instantDashBtn.MouseButton1Click:Connect(function()
    config.instantDash = not config.instantDash
    instantDashBtn.BackgroundColor3 = config.instantDash and Color3.fromRGB(45, 160, 70) or Color3.fromRGB(160, 50, 50)
    instantDashBtn.Text = config.instantDash and "INSTANT DASH: ON" or "INSTANT DASH: OFF"
    instantDashLastVel = Vector3.new(0, 0, 0)
    saveConfig()
end)

-- ============================================
-- HEARTBEAT ANTI-STUN
-- ============================================
RunService.Heartbeat:Connect(function()
    if not config.antiStun or not humanoid or not humanoid.Parent or not jumping then return end
    local state = humanoid:GetState()
    if state == Enum.HumanoidStateType.FallingDown
    or state == Enum.HumanoidStateType.GettingUp
    or state == Enum.HumanoidStateType.PlatformStanding
    or state == Enum.HumanoidStateType.Ragdoll
    or state == Enum.HumanoidStateType.Physics then
        jump()
    end
end)

-- ============================================
-- HEARTBEAT INSTANT DASH
-- ============================================
local lastInstant = 0
RunService.Heartbeat:Connect(function()
    if not config.instantDash then return end
    local char = localPlayer.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    
    local currentVel = hrp.AssemblyLinearVelocity
    local horizontalVel = Vector3.new(currentVel.X, 0, currentVel.Z)
    
    if horizontalVel.Magnitude > 45
   and horizontalVel.Magnitude - instantDashLastVel.Magnitude > 20
   and tick() - lastInstant > 0.35 then
    lastInstant = tick()
        local dir = horizontalVel.Unit
        pcall(function()
            hrp.CFrame = hrp.CFrame + dir * (18 * 0.3)
        end)
    end
    instantDashLastVel = horizontalVel
end)

-- ============================================
-- HOTKEYS
-- ============================================
UserInputService.InputBegan:Connect(function(input, processed)
    if listeningForKey then
        if input.KeyCode ~= Enum.KeyCode.Unknown then
            lockKey = input.KeyCode
            config.lockKeyName = lockKey.Name
            listeningForKey = false
            keyBtn.Text = "Tecla: " .. lockKey.Name
            keyBtn.BackgroundColor3 = Color3.fromRGB(70, 130, 220)
            keyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
            saveConfig()
        end
        return
    end
    if processed then return end
    
    if input.KeyCode == lockKey then
        toggleLock()
    elseif input.KeyCode == Enum.KeyCode.X then
        config.antiStun = not config.antiStun
        jumping = true
        updateNsToggle()
        saveConfig()
    elseif input.KeyCode == Enum.KeyCode.Z then
        config.antiStun = false
        updateNsToggle()
        saveConfig()
    elseif input.KeyCode == Enum.KeyCode.Space and config.antiStun then
        jump()
    elseif input.KeyCode == Enum.KeyCode.Q then
        dash()
    end
end)

-- ============================================
-- SEGURIDAD Y LIMPIEZA
-- ============================================
Players.PlayerRemoving:Connect(function(pl)
    for i = #whitelist, 1, -1 do if whitelist[i] == pl.Name then table.remove(whitelist, i) end end
    for i = #blacklist, 1, -1 do if blacklist[i] == pl.Name then table.remove(blacklist, i) end end
    updateListCounts()
    if pickerGui.Visible then rebuildPicker() end
    if lockedPlayer == pl then resetLock() end
end)

localPlayer.CharacterAdded:Connect(function(c)
    character = c
    humanoid = c:WaitForChild("Humanoid")
    rootPart = c:WaitForChild("HumanoidRootPart", 3) or c:FindFirstChild("Torso")
    jumping = true
    instantDashLastVel = Vector3.new(0, 0, 0)
    task.wait(0.5)
    if targetLock then resetLock() end
    hookDash()
end)

if localPlayer.Character then hookDash() end

-- Mostrar menú
task.delay(2, function()
    if loadGui and loadGui.Parent then loadGui:Destroy() end
    menuFrame.Visible = true
end)

-- Aplicar visuales iniciales
local function refreshAllVisuals()
    lockButton.Size = UDim2.new(0, config.buttonSize, 0, config.buttonSize)
    lockButton.Visible = config.buttonVisible
    sizeLabel.Text = "Tamano: " .. tostring(config.buttonSize)
    showBtn.Text = config.buttonVisible and "Boton: Visible" or "Boton: Oculto"
    showBtn.BackgroundColor3 = config.buttonVisible and Color3.fromRGB(45, 160, 70) or Color3.fromRGB(160, 50, 50)
    dragBtn.Text = config.isDraggable and "Arrastrable: ON" or "Arrastrable: OFF"
    dragBtn.BackgroundColor3 = config.isDraggable and Color3.fromRGB(45, 160, 70) or Color3.fromRGB(160, 50, 50)
    predictLabel.Text = string.format("Predict: %.3fs", config.predictAmount)
    PREDICT_TIME = config.predictAmount
    predictToggle.Text = config.predictEnabled and "ON" or "OFF"
    predictToggle.BackgroundColor3 = config.predictEnabled and Color3.fromRGB(45, 160, 70) or Color3.fromRGB(160, 50, 50)
    predictLabel.TextColor3 = config.predictEnabled and Color3.fromRGB(255, 220, 130) or Color3.fromRGB(150, 150, 150)
    dist3DBtn.Text = "Direct 3D: " .. (config.useDistance3D and "ON" or "OFF")
    dist3DBtn.BackgroundColor3 = config.useDistance3D and Color3.fromRGB(45, 160, 70) or Color3.fromRGB(160, 50, 50)
    partBtn.Text = "Parte: " .. (config.lockPart == "head" and "Cabeza" or "Torso")
    partBtn.BackgroundColor3 = config.lockPart == "head" and Color3.fromRGB(160, 50, 50) or Color3.fromRGB(70, 130, 220)
    keyBtn.Text = "Tecla: " .. lockKey.Name
    transBtn.Text = "Transp: " .. math.floor(config.menuTransparency * 100) .. "%"
    aboveBtn.Text = "Above: " .. (config.aboveView and "ON" or "OFF")
    aboveBtn.BackgroundColor3 = config.aboveView and Color3.fromRGB(45, 160, 70) or Color3.fromRGB(160, 50, 50)
    aboveHeightBtn.Text = "Altura: " .. config.aboveHeight
    modeBtn.Text = "Modo: " .. (config.lockFree and "LIBRE" or "NORMAL")
    modeBtn.BackgroundColor3 = config.lockFree and Color3.fromRGB(80, 60, 140) or Color3.fromRGB(70, 130, 220)
    updateNsToggle()
    updateListCounts()
    nsJumpLabel.Text = "Jump Power: " .. config.jumpPower
    nsDashLabel.Text = "Dash Force: " .. config.dashForce
    nsJumpSizeLabel.Text = "Jump Size: " .. config.jumpBtnSize
    nsDashSizeLabel.Text = "Dash Size: " .. config.dashBtnSize
    jumpBtn.Size = UDim2.new(0, config.jumpBtnSize, 0, config.jumpBtnSize)
    dashFloatBtn.Size = UDim2.new(0, config.dashBtnSize, 0, config.dashBtnSize)
    dashValueLabel.Text = string.format("Multiplicador: %.1fx", config.dashMultiplier)
    dashToggleBtn.BackgroundColor3 = config.dashEnabled and Color3.fromRGB(45, 160, 70) or Color3.fromRGB(160, 50, 50)
    dashToggleBtn.Text = config.dashEnabled and "ACTIVADO" or "DESACTIVADO"
    instantDashBtn.Text = config.instantDash and "INSTANT DASH: ON" or "INSTANT DASH: OFF"
    instantDashBtn.BackgroundColor3 = config.instantDash and Color3.fromRGB(45, 160, 70) or Color3.fromRGB(160, 50, 50)
end

refreshAllVisuals()

-- Autoguardado
task.spawn(function()
    while true do
        task.wait(5)
        saveConfig()
    end
end)

print("Zeidop Hub cargado OK - LOCK + INSTANT DASH + STUN + DASH + LISTA + DASH ASSIST")

-- FIX SCROLL DEL SELECTOR
task.spawn(function()
    local pg2 = Players.LocalPlayer:WaitForChild("PlayerGui")
    local hub2 = pg2:FindFirstChild("ZeidopHub")
    local picker2 = hub2 and hub2:FindFirstChild("ZeidopPicker")
    if picker2 then
        local scroll2 = picker2:FindFirstChildOfClass("ScrollingFrame")
        if scroll2 then
            pcall(function()
                scroll2.AutomaticCanvasSize = Enum.AutomaticCanvasSize.Y
            end)
            local layout2 = scroll2:FindFirstChildOfClass("UIListLayout")
            if layout2 then
                local function fit()
                    scroll2.CanvasSize = UDim2.new(0, 0, 0, layout2.AbsoluteContentSize.Y + 8)
                end
                fit()
                layout2:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(fit)
            end
        end
    end
end)


-- ============================================
-- DASH ASSIST (CON MENÚ DE CONFIGURACIÓN)
-- ============================================
do
    local STEER_MAX_ANGLE = math.rad(config.assistAngle or 50)
    local MAX_T = config.assistMaxT or 0.44
    local STOP_DIST = config.assistStopDist or 3
    local SPIKE_ON = config.assistSpikeOn or 50
    local SPIKE_OFF = config.assistSpikeOff or 35
    local WINDOW = config.assistWindow or 0.35
    local LAG = config.assistLag or 0.06
    local SPIKE_JUMP = 25

    if config.dashAssist == nil then config.dashAssist = true end

    local assistBtn = Instance.new("TextButton")
    assistBtn.Size = UDim2.new(0.75, 0, 0, 24)
    assistBtn.Position = UDim2.new(0, 0, 0, 190)
    assistBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    assistBtn.TextSize = 11
    assistBtn.Font = Enum.Font.GothamBold
    assistBtn.BorderSizePixel = 0
    assistBtn.Parent = dashPage
    Instance.new("UICorner", assistBtn).CornerRadius = UDim.new(0, 6)

    local gearBtn = Instance.new("TextButton")
    gearBtn.Size = UDim2.new(0.23, 0, 0, 24)
    gearBtn.Position = UDim2.new(0.77, 0, 0, 190)
    gearBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 75)
    gearBtn.Text = "⚙️"
    gearBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    gearBtn.TextSize = 14
    gearBtn.Font = Enum.Font.GothamBold
    gearBtn.BorderSizePixel = 0
    gearBtn.Parent = dashPage
    Instance.new("UICorner", gearBtn).CornerRadius = UDim.new(0, 6)

    local function refreshAssistBtn()
        assistBtn.Text = "DASH ASSIST: " .. (config.dashAssist and "ON" or "OFF")
        assistBtn.BackgroundColor3 = config.dashAssist and Color3.fromRGB(45, 160, 70) or Color3.fromRGB(160, 50, 50)
    end
    refreshAssistBtn()

    assistBtn.MouseButton1Click:Connect(function()
        config.dashAssist = not config.dashAssist
        refreshAssistBtn()
        saveConfig()
    end)

    local assistSettingsGui = Instance.new("Frame")
    assistSettingsGui.Name = "AssistSettings"
    assistSettingsGui.Size = UDim2.new(0, 180, 0, 230)
    assistSettingsGui.Position = UDim2.new(0.5, -90, 0.5, -115)
    assistSettingsGui.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
    assistSettingsGui.BorderSizePixel = 0
    assistSettingsGui.Visible = false
    assistSettingsGui.ZIndex = 60
    assistSettingsGui.Parent = screenGui
    Instance.new("UICorner", assistSettingsGui).CornerRadius = UDim.new(0, 10)

    local assistStroke = Instance.new("UIStroke")
    assistStroke.Color = Color3.fromRGB(160, 120, 255)
    assistStroke.Thickness = 1.5
    assistStroke.Parent = assistSettingsGui

    local assistTitle = Instance.new("TextLabel")
    assistTitle.Size = UDim2.new(1, -30, 0, 24)
    assistTitle.Position = UDim2.new(0, 8, 0, 4)
    assistTitle.BackgroundTransparency = 1
    assistTitle.Text = "Dash Assist Config"
    assistTitle.TextColor3 = Color3.fromRGB(160, 120, 255)
    assistTitle.TextSize = 11
    assistTitle.Font = Enum.Font.GothamBold
    assistTitle.TextXAlignment = Enum.TextXAlignment.Left
    assistTitle.ZIndex = 62
    assistTitle.Parent = assistSettingsGui

    local assistClose = Instance.new("TextButton")
    assistClose.Size = UDim2.new(0, 20, 0, 20)
    assistClose.Position = UDim2.new(1, -24, 0, 6)
    assistClose.BackgroundColor3 = Color3.fromRGB(160, 50, 50)
    assistClose.Text = "X"
    assistClose.TextColor3 = Color3.fromRGB(255, 255, 255)
    assistClose.TextSize = 10
    assistClose.Font = Enum.Font.GothamBold
    assistClose.BorderSizePixel = 0
    assistClose.ZIndex = 62
    assistClose.Parent = assistSettingsGui
    Instance.new("UICorner", assistClose).CornerRadius = UDim.new(0, 5)

    local assistScroll = Instance.new("ScrollingFrame")
    assistScroll.Size = UDim2.new(1, -12, 1, -34)
    assistScroll.Position = UDim2.new(0, 6, 0, 30)
    assistScroll.BackgroundTransparency = 1
    assistScroll.BorderSizePixel = 0
    assistScroll.ScrollBarThickness = 3
    assistScroll.CanvasSize = UDim2.new(0, 0, 0, 205)
    assistScroll.ZIndex = 62
    assistScroll.Parent = assistSettingsGui

    local assistLayout = Instance.new("UIListLayout")
    assistLayout.Padding = UDim.new(0, 6)
    assistLayout.Parent = assistScroll

    local function createSetting(name, min, max, step, isFloat, getConfigVal, setConfigVal)
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, -5, 0, 22)
        row.BackgroundTransparency = 1
        row.ZIndex = 63
        row.Parent = assistScroll

        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(0.55, 0, 1, 0)
        label.Position = UDim2.new(0, 0, 0, 0)
        label.BackgroundTransparency = 1
        label.TextColor3 = Color3.fromRGB(200, 200, 210)
        label.TextSize = 9
        label.Font = Enum.Font.Gotham
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.ZIndex = 64
        label.Parent = row

        local minus = Instance.new("TextButton")
        minus.Size = UDim2.new(0, 20, 1, 0)
        minus.Position = UDim2.new(0.55, 2, 0, 0)
        minus.BackgroundColor3 = Color3.fromRGB(160, 50, 50)
        minus.Text = "-"
        minus.TextColor3 = Color3.fromRGB(255, 255, 255)
        minus.TextSize = 12
        minus.Font = Enum.Font.GothamBold
        minus.BorderSizePixel = 0
        minus.ZIndex = 64
        minus.Parent = row
        Instance.new("UICorner", minus).CornerRadius = UDim.new(0, 4)

        local plus = Instance.new("TextButton")
        plus.Size = UDim2.new(0, 20, 1, 0)
        plus.Position = UDim2.new(1, -22, 0, 0)
        plus.BackgroundColor3 = Color3.fromRGB(45, 160, 70)
        plus.Text = "+"
        plus.TextColor3 = Color3.fromRGB(255, 255, 255)
        plus.TextSize = 12
        plus.Font = Enum.Font.GothamBold
        plus.BorderSizePixel = 0
        plus.ZIndex = 64
        plus.Parent = row
        Instance.new("UICorner", plus).CornerRadius = UDim.new(0, 4)

        local function update()
            local val = getConfigVal()
            if isFloat then
                label.Text = name .. ": " .. string.format("%.2f", val)
            else
                label.Text = name .. ": " .. math.floor(val + 0.5)
            end
        end

        minus.MouseButton1Click:Connect(function()
            local val = math.floor(math.max(min, getConfigVal() - step) * 100 + 0.5) / 100
            setConfigVal(val)
            update()
            saveConfig()
        end)

        plus.MouseButton1Click:Connect(function()
            local val = math.floor(math.min(max, getConfigVal() + step) * 100 + 0.5) / 100
            setConfigVal(val)
            update()
            saveConfig()
        end)

        update()
    end

    createSetting("Angle", 10, 180, 1, false,
        function() return config.assistAngle or 50 end,
        function(v) config.assistAngle = v STEER_MAX_ANGLE = math.rad(v) end)

    createSetting("Max T", 0.1, 2.0, 0.01, true,
        function() return config.assistMaxT or 0.44 end,
        function(v) config.assistMaxT = v MAX_T = v end)

    createSetting("Lag", 0, 0.3, 0.01, true,
        function() return config.assistLag or 0.06 end,
        function(v) config.assistLag = v LAG = v end)

    createSetting("Stop Dist", 1, 20, 1, false,
        function() return config.assistStopDist or 3 end,
        function(v) config.assistStopDist = v STOP_DIST = v end)

    createSetting("Spike ON", 10, 200, 1, false,
        function() return config.assistSpikeOn or 50 end,
        function(v) config.assistSpikeOn = v SPIKE_ON = v end)

    createSetting("Spike OFF", 10, 200, 1, false,
        function() return config.assistSpikeOff or 35 end,
        function(v) config.assistSpikeOff = v SPIKE_OFF = v end)

    createSetting("Window", 0.05, 2.0, 0.01, true,
        function() return config.assistWindow or 0.35 end,
        function(v) config.assistWindow = v WINDOW = v end)

    gearBtn.MouseButton1Click:Connect(function()
        assistSettingsGui.Visible = not assistSettingsGui.Visible
    end)

    assistClose.MouseButton1Click:Connect(function()
        assistSettingsGui.Visible = false
    end)

    local active = false
    local driver = nil
    local origDir = nil
    local untilT = 0
    local lastH = 0
    -- v9: estado del filtro de dashes con salto (en una tabla para no gastar variables locales)
    local J = { airSince = nil, lastJump = -10, lastReq = -10, rejectUntil = 0, startT = 0 }

    local function usable(c)
        if c:IsA("BodyVelocity") then return true end
        if c:IsA("LinearVelocity") then
            local ok, rel = pcall(function() return c.RelativeTo end)
            return ok and rel == Enum.ActuatorRelativeTo.World
        end
        return false
    end
    local function getVel(c) return c:IsA("BodyVelocity") and c.Velocity or c.VectorVelocity end
    local function setVel(c, v)
        if c:IsA("BodyVelocity") then c.Velocity = v else c.VectorVelocity = v end
    end
    local function findDriver(hrp)
        for _, c in ipairs(hrp:GetChildren()) do
            if usable(c) then return c end
        end
        return nil
    end

    local function getTargetRoot()
        if not targetLock or not lockedPlayer then return nil end
        local ch = lockedPlayer.Character
        local r = ch and ch:FindFirstChild("HumanoidRootPart")
        local h = ch and ch:FindFirstChildOfClass("Humanoid")
        if r and h and h.Health > 0 then return r end
        return nil
    end

    local function interceptDir(myPos, tRoot, speed)
        -- v5: con predict encendido, el dash va al MISMO punto al que mira el lock
        if config.assistFollowLock and config.predictEnabled and lockAimPos then
            local f = Vector3.new(lockAimPos.X - myPos.X, 0, lockAimPos.Z - myPos.Z)
            if f.Magnitude < 0.01 then return nil end
            return f.Unit
        end
        local r = Vector3.new(tRoot.Position.X - myPos.X, 0, tRoot.Position.Z - myPos.Z)
        local v = TH.velocity(tRoot)

        r = r + v * LAG

        local a = v:Dot(v) - speed * speed
        local b = 2 * r:Dot(v)
        local cc = r:Dot(r)
        local t = nil
        if math.abs(a) < 1e-4 then
            if b < 0 then t = -cc / b end
        else
            local disc = b * b - 4 * a * cc
            if disc >= 0 then
                local sq = math.sqrt(disc)
                local t1, t2 = (-b - sq) / (2 * a), (-b + sq) / (2 * a)
                if t1 > 0 and t2 > 0 then t = math.min(t1, t2)
                elseif t1 > 0 then t = t1
                elseif t2 > 0 then t = t2 end
            end
        end
        t = math.clamp(t or 0, 0, MAX_T)
        local aim = r + v * t
        if aim.Magnitude < 0.01 then return nil end
        return aim.Unit
    end

    local function startAssist(hrp, drv, t0)
        if active then
            if drv and not driver then
                driver = drv
                untilT = tick() + 1.5
            end
            return
        end
        local now = os.clock()
        if now < J.rejectUntil then return end
        local v = drv and getVel(drv) or hrp.AssemblyLinearVelocity
        local h = Vector3.new(v.X, 0, v.Z)
        if h.Magnitude < 10 then return end
        -- v9: ignorar dashes con salto (estabas en el aire o acabas de saltar)
        if config.assistIgnoreJump then
            local t = t0 or now
            local why = nil
            if J.airSince and t - J.airSince > 0.06 then
                why = "estabas en el aire"
            elseif t - J.lastJump >= 0 and t - J.lastJump < 0.25 then
                why = "saltaste justo antes"
            end
            if why then
                J.rejectUntil = now + 0.6
                TH.dashStatus = "ignorado (" .. why .. ")"
                return
            end
        end
        active = true
        driver = drv
        origDir = h.Unit
        untilT = tick() + (drv and 1.5 or WINDOW)
        J.startT = now
        TH.dashStatus = "asistiendo"
    end

    local function steer(hrp)
        local tRoot = getTargetRoot()
        if not tRoot or not origDir then return end
        local cur = (driver and driver.Parent) and getVel(driver) or hrp.AssemblyLinearVelocity
        local speedH = Vector3.new(cur.X, 0, cur.Z).Magnitude
        if speedH < 10 then return end

        local toT = Vector3.new(tRoot.Position.X - hrp.Position.X, 0, tRoot.Position.Z - hrp.Position.Z)
        if toT.Magnitude < STOP_DIST then return end

        local ang = math.acos(math.clamp(origDir:Dot(toT.Unit), -1, 1))
        if ang > STEER_MAX_ANGLE then return end

        local dir = interceptDir(hrp.Position, tRoot, speedH)
        if not dir then return end
        local nv = Vector3.new(dir.X * speedH, cur.Y, dir.Z * speedH)
        if driver and driver.Parent then
            setVel(driver, nv)
        else
            hrp.AssemblyLinearVelocity = nv
        end
    end

    local conn = nil
    local function hookChar(char)
        if conn then conn:Disconnect() conn = nil end
        local hrp = char:WaitForChild("HumanoidRootPart", 5)
        if not hrp then return end
        conn = hrp.ChildAdded:Connect(function(child)
            if not config.dashAssist or not usable(child) then return end
            -- v6: espera >= 16 ms Y que el juego ya haya puesto velocidad (a 120 FPS = 2 frames como antes)
            local w0 = os.clock()
            for _ = 1, 3 do
                RunService.Heartbeat:Wait()
                if not child.Parent then return end
                if os.clock() - w0 >= 0.016 then
                    local vv = getVel(child)
                    if Vector3.new(vv.X, 0, vv.Z).Magnitude >= 10 then break end
                end
            end
            if child.Parent and getTargetRoot() then startAssist(hrp, child, w0) end
        end)
    end
    if localPlayer.Character then task.spawn(hookChar, localPlayer.Character) end
    localPlayer.CharacterAdded:Connect(function(c)
        active = false
        driver = nil
        task.spawn(hookChar, c)
    end)

    UserInputService.JumpRequest:Connect(function()
        local now = os.clock()
        J.lastJump, J.lastReq = now, now
    end)

    RunService.Heartbeat:Connect(function()
        -- seguimiento de aire / salto (para el filtro de dashes con salto)
        local now = os.clock()
        local hm = humanoid
        if hm and hm.Parent then
            if hm.FloorMaterial == Enum.Material.Air then
                J.airSince = J.airSince or now
            else
                J.airSince = nil
            end
            if hm:GetState() == Enum.HumanoidStateType.Jumping then J.lastJump = now end
        end

        if not config.dashAssist then active = false driver = nil return end
        local tr = getTargetRoot()
        local char = localPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp then return end

        local v = hrp.AssemblyLinearVelocity
        local h = Vector3.new(v.X, 0, v.Z).Magnitude

        if not active then
            if h > SPIKE_ON and (lastH < SPIKE_OFF or h - lastH > SPIKE_JUMP) and tr then
                startAssist(hrp, findDriver(hrp), now)
            end
        else
            if (driver and not driver.Parent) or tick() > untilT then
                active = false
                driver = nil
                TH.dashStatus = "dash terminado"
            elseif config.assistIgnoreJump and J.lastReq > J.startT then
                active = false
                driver = nil
                TH.dashStatus = "cancelado (saltaste durante el dash)"
            else
                steer(hrp)
            end
        end
        lastH = h
    end)
end

-- ============================================
-- SKIN VISUAL (SOLO INTERFAZ - no cambia ninguna logica ni funcion)
-- Pegar al FINAL del hub. Para quitarlo: borra este bloque completo.
-- ============================================
do
    local R = {
        screenGui = screenGui, menuFrame = menuFrame, menuStroke = menuStroke,
        titleBar = titleBar, titleFix = titleFix, titleLogo = titleLogo, titleLabel = titleLabel,
        minBtn = minBtn, accentLine = accentLine, tabBar = tabBar, miniMenuBtn = miniMenuBtn,
        tabLock = tabLock, tabNoStun = tabNoStun, tabDash = tabDash, tabList = tabList,
        lockPage = lockPage, showBtn = showBtn, dragBtn = dragBtn, sizeLabel = sizeLabel,
        sizeMinus = sizeMinus, sizePlus = sizePlus, predictLabel = predictLabel,
        predictMinus = predictMinus, predictPlus = predictPlus, predictToggle = predictToggle,
        dist3DBtn = dist3DBtn, transBtn = transBtn, aimSep = aimSep, partBtn = partBtn,
        keyBtn = keyBtn, aboveBtn = aboveBtn, aboveHeightBtn = aboveHeightBtn, modeBtn = modeBtn,
        noStunPage = noStunPage, nsToggleBtn = nsToggleBtn, nsJumpLabel = nsJumpLabel,
        nsJumpMinus = nsJumpMinus, nsJumpPlus = nsJumpPlus, nsJumpGenBtn = nsJumpGenBtn,
        nsDashLabel = nsDashLabel, nsDashMinus = nsDashMinus, nsDashPlus = nsDashPlus,
        nsDashGenBtn = nsDashGenBtn, nsJumpSizeLabel = nsJumpSizeLabel,
        nsJumpSizeMinus = nsJumpSizeMinus, nsJumpSizePlus = nsJumpSizePlus,
        nsDashSizeLabel = nsDashSizeLabel, nsDashSizeMinus = nsDashSizeMinus,
        nsDashSizePlus = nsDashSizePlus, nsLockBtn = nsLockBtn, nsInfoLabel = nsInfoLabel,
        dashPage = dashPage, dashTitle = dashTitle, dashValueLabel = dashValueLabel,
        dashMinusBtn = dashMinusBtn, dashPlusBtn = dashPlusBtn, dashToggleBtn = dashToggleBtn,
        instantDashBtn = instantDashBtn, dashDesc = dashDesc,
        listPage = listPage, wlBtn = wlBtn, blBtn = blBtn, listHint = listHint,
        imanBtn = imanBtn, lungeBtn = lungeBtn, fuerzaBtn = fuerzaBtn,
        pickerGui = pickerGui, pickerStroke = pickerStroke, pickerTitle = pickerTitle,
        pickerClose = pickerClose, pickerLayout = pickerLayout,
        lockButton = lockButton, lockStroke = lockStroke, jumpBtn = jumpBtn, jbStroke = jbStroke,
        dashFloatBtn = dashFloatBtn, dfStroke = dfStroke,
    }

    local ok, err = pcall(function()
        local C_BG = Color3.fromRGB(14, 14, 20)
        local C_CARD = Color3.fromRGB(23, 23, 33)
        local C_LINE = Color3.fromRGB(48, 48, 68)
        local C_ACC = Color3.fromRGB(160, 120, 255)
        local WHITE = Color3.fromRGB(255, 255, 255)
        local RH, PAD, GAP = 32, 8, 8
        local FB = Enum.Font.GothamBold
        local H = {}

        local function step(name, fn)
            local s, e = pcall(fn)
            if not s then warn("[zeidop skin] " .. name .. ": " .. tostring(e)) end
        end
        local function corner(o, r)
            local c = o:FindFirstChildOfClass("UICorner")
            if not c then
                c = Instance.new("UICorner")
                c.Parent = o
            end
            c.CornerRadius = UDim.new(0, r)
        end
        local function stroke(o, col, tr, th)
            local s = Instance.new("UIStroke")
            s.Color = col
            s.Transparency = tr
            s.Thickness = th
            s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
            s.Parent = o
            return s
        end
        local function grad(o, c0, c1, rot)
            local g = Instance.new("UIGradient")
            g.Color = ColorSequence.new(c0, c1)
            g.Rotation = rot
            g.Parent = o
        end
        -- estilo comun de boton (los colores de estado ON/OFF los sigue manejando tu logica)
        local function btn(o, size)
            corner(o, 8)
            grad(o, WHITE, Color3.fromRGB(205, 205, 205), 90)
            stroke(o, WHITE, 0.86, 1)
            o.Font = FB
            o.TextSize = size
            o.ZIndex = 2
        end
        -- rejilla: media fila, fila completa, columnas desde la derecha, etiqueta
        local function half(o, right, y)
            o.Position = UDim2.new(right and 0.5 or 0, right and 4 or 8, 0, y)
            o.Size = UDim2.new(0.5, -12, 0, RH)
        end
        local function full(o, y)
            o.Position = UDim2.new(0, 8, 0, y)
            o.Size = UDim2.new(1, -16, 0, RH)
        end
        local function col(o, n, y)
            o.Position = UDim2.new(1, -(4 + 48 * n), 0, y)
            o.Size = UDim2.new(0, 44, 0, RH)
        end
        local function lab(o, n, y, size)
            o.Position = UDim2.new(0, 10, 0, y)
            o.Size = UDim2.new(1, -(20 + 48 * n), 0, RH)
            o.TextSize = size
            o.TextXAlignment = Enum.TextXAlignment.Left
            o.TextYAlignment = Enum.TextYAlignment.Center
            o.ZIndex = 2
        end
        local function header(page, cur, text)
            local l = Instance.new("TextLabel")
            l.BackgroundTransparency = 1
            l.Text = text
            l.Font = FB
            l.TextSize = 11
            l.TextColor3 = C_ACC
            l.TextXAlignment = Enum.TextXAlignment.Left
            l.Position = UDim2.new(0, 6, 0, cur.y)
            l.Size = UDim2.new(1, -12, 0, 14)
            l.ZIndex = 2
            l.Parent = page
            cur.y = cur.y + 18
        end
        local function card(page, cur, rows)
            local h = PAD * 2 + rows * RH + (rows - 1) * GAP
            local c = Instance.new("Frame")
            c.BackgroundColor3 = C_CARD
            c.BorderSizePixel = 0
            c.Position = UDim2.new(0, 0, 0, cur.y)
            c.Size = UDim2.new(1, 0, 0, h)
            c.ZIndex = 1
            c.Parent = page
            corner(c, 10)
            stroke(c, C_LINE, 0.2, 1)
            local top = cur.y + PAD
            cur.y = cur.y + h + 14
            return top
        end
        local function rowY(top, i) return top + (i - 1) * (RH + GAP) end

        -- ===== MENU, TITULO Y PESTANAS LATERALES =====
        step("menu", function()
            local m = R.menuFrame
            m.Size = UDim2.new(0, 400, 0, 300)
            m.Position = UDim2.new(0.02, 0, 0.06, 0)
            m.BackgroundColor3 = C_BG
            corner(m, 14)
            R.menuStroke.Color = Color3.fromRGB(110, 80, 210)
            R.menuStroke.Thickness = 2
            R.miniMenuBtn.Position = m.Position

            R.titleBar.Size = UDim2.new(1, 0, 0, 40)
            R.titleBar.BackgroundColor3 = WHITE
            R.titleFix.BackgroundColor3 = WHITE
            corner(R.titleBar, 14)
            grad(R.titleBar, Color3.fromRGB(64, 46, 124), Color3.fromRGB(24, 24, 36), 0)
            grad(R.titleFix, Color3.fromRGB(64, 46, 124), Color3.fromRGB(24, 24, 36), 0)
            R.titleLogo.Size = UDim2.new(0, 28, 0, 28)
            R.titleLogo.Position = UDim2.new(0, 10, 0, 6)
            R.titleLabel.Position = UDim2.new(0, 46, 0, 0)
            R.titleLabel.Size = UDim2.new(1, -96, 1, 0)
            R.titleLabel.TextSize = 18
            R.titleLabel.Font = Enum.Font.GothamBlack
            R.minBtn.Size = UDim2.new(0, 28, 0, 28)
            R.minBtn.Position = UDim2.new(1, -38, 0, 6)
            btn(R.minBtn, 18)
            R.accentLine.Position = UDim2.new(0, 0, 0, 40)
            R.accentLine.BackgroundColor3 = WHITE
            grad(R.accentLine, Color3.fromRGB(160, 120, 255), Color3.fromRGB(80, 200, 255), 0)
        end)

        step("tabs", function()
            local tb = R.tabBar
            tb.Position = UDim2.new(0, 10, 0, 52)
            tb.Size = UDim2.new(0, 84, 1, -64)
            local ll = Instance.new("UIListLayout")
            ll.Padding = UDim.new(0, 8)
            ll.SortOrder = Enum.SortOrder.LayoutOrder
            ll.Parent = tb
            for i, b in ipairs({R.tabLock, R.tabNoStun, R.tabDash, R.tabList}) do
                b.LayoutOrder = i
                b.Size = UDim2.new(1, 0, 0, 38)
                btn(b, 12)
            end
            local sep = Instance.new("Frame")
            sep.BackgroundColor3 = C_LINE
            sep.BorderSizePixel = 0
            sep.Position = UDim2.new(0, 102, 0, 52)
            sep.Size = UDim2.new(0, 1, 1, -64)
            sep.ZIndex = 1
            sep.Parent = R.menuFrame
        end)

        -- ===== PAGINA LOCK =====
        step("lock", function()
            local P, cur = R.lockPage, {y = 0}
            header(P, cur, "BOTON FLOTANTE")
            local t = card(P, cur, 2)
            half(R.showBtn, false, rowY(t, 1)); btn(R.showBtn, 11)
            half(R.dragBtn, true, rowY(t, 1)); btn(R.dragBtn, 11)
            lab(R.sizeLabel, 2, rowY(t, 2), 12)
            col(R.sizeMinus, 2, rowY(t, 2)); btn(R.sizeMinus, 18)
            col(R.sizePlus, 1, rowY(t, 2)); btn(R.sizePlus, 18)

            header(P, cur, "PREDICT")
            t = card(P, cur, 1)
            lab(R.predictLabel, 3, rowY(t, 1), 11)
            col(R.predictMinus, 3, rowY(t, 1)); btn(R.predictMinus, 10)
            col(R.predictPlus, 2, rowY(t, 1)); btn(R.predictPlus, 10)
            col(R.predictToggle, 1, rowY(t, 1)); btn(R.predictToggle, 11)

            local a = R.aimSep -- se reutiliza como encabezado de seccion
            a.Text = "APUNTADO / TECLA"
            a.Font = FB
            a.TextSize = 11
            a.TextColor3 = C_ACC
            a.TextXAlignment = Enum.TextXAlignment.Left
            a.Position = UDim2.new(0, 6, 0, cur.y)
            a.Size = UDim2.new(1, -12, 0, 14)
            a.ZIndex = 2
            cur.y = cur.y + 18
            t = card(P, cur, 3)
            half(R.dist3DBtn, false, rowY(t, 1)); btn(R.dist3DBtn, 11)
            half(R.partBtn, true, rowY(t, 1)); btn(R.partBtn, 11)
            half(R.keyBtn, false, rowY(t, 2)); btn(R.keyBtn, 11)
            half(R.modeBtn, true, rowY(t, 2)); btn(R.modeBtn, 11)
            half(R.aboveBtn, false, rowY(t, 3)); btn(R.aboveBtn, 11)
            half(R.aboveHeightBtn, true, rowY(t, 3)); btn(R.aboveHeightBtn, 11)

            header(P, cur, "MENU")
            t = card(P, cur, 1)
            full(R.transBtn, rowY(t, 1)); btn(R.transBtn, 11)
            H[P] = cur.y - 8
        end)

        -- ===== PAGINA STUN =====
        step("stun", function()
            local P, cur = R.noStunPage, {y = 0}
            header(P, cur, "ANTI-STUN")
            local t = card(P, cur, 1)
            full(R.nsToggleBtn, rowY(t, 1)); btn(R.nsToggleBtn, 12)

            header(P, cur, "SALTO Y DASH")
            t = card(P, cur, 2)
            lab(R.nsJumpLabel, 3, rowY(t, 1), 12)
            col(R.nsJumpMinus, 3, rowY(t, 1)); btn(R.nsJumpMinus, 18)
            col(R.nsJumpPlus, 2, rowY(t, 1)); btn(R.nsJumpPlus, 18)
            col(R.nsJumpGenBtn, 1, rowY(t, 1)); btn(R.nsJumpGenBtn, 10)
            lab(R.nsDashLabel, 3, rowY(t, 2), 12)
            col(R.nsDashMinus, 3, rowY(t, 2)); btn(R.nsDashMinus, 18)
            col(R.nsDashPlus, 2, rowY(t, 2)); btn(R.nsDashPlus, 18)
            col(R.nsDashGenBtn, 1, rowY(t, 2)); btn(R.nsDashGenBtn, 10)

            header(P, cur, "TAMANO DE BOTONES")
            t = card(P, cur, 2)
            lab(R.nsJumpSizeLabel, 2, rowY(t, 1), 12)
            col(R.nsJumpSizeMinus, 2, rowY(t, 1)); btn(R.nsJumpSizeMinus, 18)
            col(R.nsJumpSizePlus, 1, rowY(t, 1)); btn(R.nsJumpSizePlus, 18)
            lab(R.nsDashSizeLabel, 2, rowY(t, 2), 12)
            col(R.nsDashSizeMinus, 2, rowY(t, 2)); btn(R.nsDashSizeMinus, 18)
            col(R.nsDashSizePlus, 1, rowY(t, 2)); btn(R.nsDashSizePlus, 18)

            header(P, cur, "BOTONES FLOTANTES")
            t = card(P, cur, 1)
            full(R.nsLockBtn, rowY(t, 1)); btn(R.nsLockBtn, 12)

            local i = R.nsInfoLabel
            i.Position = UDim2.new(0, 6, 0, cur.y - 8)
            i.Size = UDim2.new(1, -12, 0, 30)
            i.TextSize = 10
            i.TextWrapped = true
            i.TextYAlignment = Enum.TextYAlignment.Top
            i.ZIndex = 2
            H[P] = cur.y + 28
        end)

        -- ===== PAGINA DASH (incluye el boton de Dash Assist, que vive en un do-block) =====
        step("dash", function()
            local P, cur = R.dashPage, {y = 0}
            local assistB, gearB
            for _, c in ipairs(P:GetChildren()) do
                if c:IsA("TextButton") then
                    if math.abs(c.Size.X.Scale - 0.75) < 0.01 then assistB = c
                    elseif math.abs(c.Size.X.Scale - 0.23) < 0.01 then gearB = c end
                end
            end
            local d = R.dashTitle
            d.Position = UDim2.new(0, 6, 0, 0)
            d.Size = UDim2.new(1, -12, 0, 22)
            d.TextSize = 16
            d.ZIndex = 2
            cur.y = 30

            header(P, cur, "MULTIPLICADOR")
            local t = card(P, cur, 2)
            local v = R.dashValueLabel
            v.Position = UDim2.new(0, 10, 0, rowY(t, 1))
            v.Size = UDim2.new(1, -20, 0, RH)
            v.TextSize = 13
            v.ZIndex = 2
            half(R.dashMinusBtn, false, rowY(t, 2)); btn(R.dashMinusBtn, 18)
            half(R.dashPlusBtn, true, rowY(t, 2)); btn(R.dashPlusBtn, 18)

            header(P, cur, "ESTADO")
            t = card(P, cur, 2)
            full(R.dashToggleBtn, rowY(t, 1)); btn(R.dashToggleBtn, 12)
            full(R.instantDashBtn, rowY(t, 2)); btn(R.instantDashBtn, 12)

            header(P, cur, "DASH ASSIST")
            t = card(P, cur, 1)
            if assistB then
                assistB.Position = UDim2.new(0, 8, 0, rowY(t, 1))
                assistB.Size = UDim2.new(1, -68, 0, RH)
                btn(assistB, 12)
            end
            if gearB then
                gearB.Position = UDim2.new(1, -52, 0, rowY(t, 1))
                gearB.Size = UDim2.new(0, 44, 0, RH)
                btn(gearB, 16)
            end

            local ds = R.dashDesc
            ds.Position = UDim2.new(0, 6, 0, cur.y - 8)
            ds.Size = UDim2.new(1, -12, 0, 56)
            ds.TextSize = 11
            ds.TextYAlignment = Enum.TextYAlignment.Top
            ds.ZIndex = 2
            H[P] = cur.y + 56
        end)

        -- ===== PAGINA LISTA =====
        step("list", function()
            local P, cur = R.listPage, {y = 0}
            header(P, cur, "LISTAS")
            local t = card(P, cur, 1)
            half(R.wlBtn, false, rowY(t, 1)); btn(R.wlBtn, 11)
            half(R.blBtn, true, rowY(t, 1)); btn(R.blBtn, 11)
            local h = R.listHint
            h.Position = UDim2.new(0, 6, 0, cur.y - 8)
            h.Size = UDim2.new(1, -12, 0, 34)
            h.TextSize = 10
            h.ZIndex = 2
            cur.y = cur.y + 34

            header(P, cur, "IMAN / LUNGE")
            t = card(P, cur, 2)
            half(R.imanBtn, false, rowY(t, 1)); btn(R.imanBtn, 11)
            half(R.lungeBtn, true, rowY(t, 1)); btn(R.lungeBtn, 11)
            full(R.fuerzaBtn, rowY(t, 2)); btn(R.fuerzaBtn, 11)
            H[P] = cur.y - 8
        end)

        -- ===== AREA CON SCROLL (las paginas ahora tienen espacio de sobra) =====
        step("scroll", function()
            local sc = Instance.new("ScrollingFrame")
            sc.Name = "ZeidopSkinScroll"
            sc.BackgroundTransparency = 1
            sc.BorderSizePixel = 0
            sc.Position = UDim2.new(0, 108, 0, 52)
            sc.Size = UDim2.new(1, -118, 1, -64)
            sc.ScrollBarThickness = 4
            sc.ScrollBarImageColor3 = C_ACC
            sc.ScrollingDirection = Enum.ScrollingDirection.Y
            sc.VerticalScrollBarInset = Enum.ScrollBarInset.Always
            sc.CanvasSize = UDim2.new(0, 0, 0, H[R.lockPage] or 420)
            sc.Parent = R.menuFrame
            local pages = {R.lockPage, R.noStunPage, R.dashPage, R.listPage}
            local tabsB = {R.tabLock, R.tabNoStun, R.tabDash, R.tabList}
            for i, p in ipairs(pages) do
                p.Parent = sc
                p.Position = UDim2.new(0, 0, 0, 0)
                p.Size = UDim2.new(1, 0, 0, H[p] or 420)
                tabsB[i].MouseButton1Click:Connect(function()
                    sc.CanvasPosition = Vector2.new(0, 0)
                    sc.CanvasSize = UDim2.new(0, 0, 0, p.Size.Y.Offset)
                end)
            end
        end)

        -- ===== VENTANAS EMERGENTES (selector de jugadores y config de Dash Assist) =====
        step("popups", function()
            local pk = R.pickerGui
            pk.Size = UDim2.new(0, 300, 0, 320)
            pk.Position = UDim2.new(0.5, -150, 0.5, -160)
            corner(pk, 12)
            R.pickerStroke.Thickness = 2
            R.pickerTitle.TextSize = 13
            R.pickerClose.Size = UDim2.new(0, 26, 0, 26)
            R.pickerClose.Position = UDim2.new(1, -32, 0, 4)
            R.pickerLayout.Padding = UDim.new(0, 6)
            local ps = pk:FindFirstChildOfClass("ScrollingFrame")
            if ps then
                ps.ScrollBarImageColor3 = C_ACC
                ps.Position = UDim2.new(0, 8, 0, 72)
                ps.Size = UDim2.new(1, -16, 1, -80)
            end

            local asg = R.screenGui:FindFirstChild("AssistSettings")
            if asg then
                asg.Size = UDim2.new(0, 220, 0, 270)
                asg.Position = UDim2.new(0.5, -110, 0.5, -135)
                corner(asg, 12)
                local sc2 = asg:FindFirstChildOfClass("ScrollingFrame")
                if sc2 then
                    sc2.CanvasSize = UDim2.new(0, 0, 0, 280)
                    sc2.ScrollBarImageColor3 = C_ACC
                    local lay = sc2:FindFirstChildOfClass("UIListLayout")
                    if lay then lay.Padding = UDim.new(0, 12) end
                    for _, row in ipairs(sc2:GetChildren()) do
                        if row:IsA("Frame") then
                            row.Size = UDim2.new(1, -6, 0, 28)
                            for _, c in ipairs(row:GetChildren()) do
                                if c:IsA("TextLabel") then c.TextSize = 11 end
                                if c:IsA("TextButton") then c.TextSize = 14 end
                            end
                        end
                    end
                end
            end
        end)

        -- ===== BOTONES FLOTANTES (solo apariencia; tamano y posicion siguen siendo tuyos) =====
        step("float", function()
            for _, b in ipairs({R.lockButton, R.jumpBtn, R.dashFloatBtn}) do
                b.Font = Enum.Font.GothamBlack
                grad(b, WHITE, Color3.fromRGB(200, 200, 200), 90)
            end
            for _, s in ipairs({R.lockStroke, R.jbStroke, R.dfStroke}) do
                s.Color = WHITE
                s.Transparency = 0.55
                s.Thickness = 2
            end
        end)
    end)
    if not ok then warn("[zeidop skin] " .. tostring(err)) end
end

-- ============================================================
-- ZEIDOP EXTRAS v9  (ya integrado en el hub)
-- Incluye: predict adaptativo, Jump Sync, pestana ESTILO y selector de listas.
-- Un solo Dash Assist (el clasico, con filtro de saltos). Sin V2, sin Lag automatico.
-- El cerebro del lock (cameraLockStep / faceStep / CAM_PRIORITY) NO se toca.
-- ============================================================
do
local X = {} -- todo cuelga de aqui para no pasar el limite de 200 locales del hub

-- ---------- CONFIG NUEVA (el loadConfig original no conoce estas llaves) ----------
do
    local defaults = {
        jumpSync = true, jumpSyncNeedLock = true, jumpSyncRange = 25, jumpSyncDelay = 0, jumpSyncVy = 25,
        btnOpacity = 0, opacityMini = false,
        btnShape = { lock = "circle", jump = "circle", dash = "circle", mini = "circle" },
        assistFollowLock = true, assistIgnoreJump = true, predictAdaptive = true, predictComp = 1.0,
    }
    for k, v in pairs(defaults) do
        if config[k] == nil then config[k] = v end
    end
    pcall(function()
        if readfile and isfile and isfile(SAVE_FILE) then
            local d = HttpService:JSONDecode(readfile(SAVE_FILE))
            if type(d) == "table" then
                for k in pairs(defaults) do
                    if d[k] ~= nil then
                        if type(defaults[k]) == "table" then
                            if type(d[k]) == "table" then
                                for kk, vv in pairs(d[k]) do config[k][kk] = vv end
                            end
                        else
                            config[k] = d[k]
                        end
                    end
                end
            end
        end
    end)
end

-- ---------- MEDIDOR DE FPS / PING (solo mide, no toca nada) ----------
X.perf = { fps = 60, p90 = 1 / 60, ping = 50, pingP90 = 50 }
do
    local N, i = 40, 0
    local buf, tmp = {}, {}
    local pbuf, ptmp, pi = {}, {}, 0 -- ~5 s de ping (20 muestras)
    for k = 1, N do buf[k] = 1 / 60 end
    RunService.Heartbeat:Connect(function(dt)
        i = i % N + 1
        buf[i] = dt
    end)
    task.spawn(function()
        local Stats = game:GetService("Stats")
        while true do
            task.wait(0.25)
            for k = 1, N do tmp[k] = buf[k] end
            table.sort(tmp)
            X.perf.fps = 1 / math.max(tmp[math.floor(N / 2)], 0.001)
            X.perf.p90 = tmp[math.floor(N * 0.9)]
            local ok, p = pcall(function()
                return Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
            end)
            if ok and type(p) == "number" then
                X.perf.ping = p
                pi = pi % 20 + 1
                pbuf[pi] = p
            end
            local cnt = #pbuf
            if cnt > 0 then
                for k = 1, cnt do ptmp[k] = pbuf[k] end
                table.sort(ptmp)
                X.perf.pingP90 = ptmp[math.max(1, math.floor(cnt * 0.9 + 0.5))]
            end
            -- ajuste del predict: solo suma lo que SOBRA respecto a 28 ms de ping y 120 FPS
            if config.predictAdaptive then
                local dPing = math.max(0, X.perf.pingP90 - 28) / 1000
                local dFrame = math.max(0, X.perf.p90 - 1 / 120)
                config.liveComp = math.min(0.20, (dPing * 0.7 + dFrame) * (config.predictComp or 1))
            else
                config.liveComp = 0
            end
        end
    end)
end

-- ---------- JUMP SYNC: saltar cuando el enemigo salta ----------
-- Detecta el salto por la ALTURA del enemigo (historial de posicion), no por la velocidad
-- replicada, que en movil llega tarde. Si el enemigo sube >= umbral en 0.15 s, tu personaje salta.
-- El historial es un anillo fijo: no crea tablas por frame (cero basura = cero tirones).
X.jstatus = "-"
do
    local HN = 96
    local J = { root = nil, lastJumpAt = -10, lastNear = 0, near = nil, ht = {}, hy = {}, n = 0, head = 0 }
    local BAD = {
        [Enum.HumanoidStateType.FallingDown] = true, [Enum.HumanoidStateType.GettingUp] = true,
        [Enum.HumanoidStateType.Ragdoll] = true, [Enum.HumanoidStateType.PlatformStanding] = true,
        [Enum.HumanoidStateType.Physics] = true, [Enum.HumanoidStateType.Dead] = true,
    }

    local function pickTarget(now)
        if targetLock and lockedPlayer then
            local ch = lockedPlayer.Character
            return ch and ch:FindFirstChild("HumanoidRootPart")
        end
        if config.jumpSyncNeedLock then return nil end
        if now - J.lastNear > 0.15 then
            J.lastNear = now
            J.near = (nearestEnemy())
        end
        return J.near
    end

    -- altura del enemigo hace "age" segundos (muestra guardada mas cercana, max 0.1 s de error)
    local function heightAgo(now, age)
        local want = now - age
        local best, bestDt = nil, 0.1
        for k = 0, J.n - 1 do
            local idx = (J.head - 1 - k) % HN + 1
            local t = J.ht[idx]
            local dt = math.abs(t - want)
            if dt < bestDt then
                bestDt, best = dt, J.hy[idx]
            end
            if t < want - 0.1 then break end
        end
        return best
    end

    RunService.Heartbeat:Connect(function()
        if not config.jumpSync then
            J.root, J.n, J.head = nil, 0, 0
            return
        end
        local now = os.clock()
        local tr = pickTarget(now)
        if not tr or not tr.Parent then
            J.root, J.n, J.head = nil, 0, 0
            return
        end
        if J.root ~= tr then J.root, J.n, J.head = tr, 0, 0 end

        local y = tr.Position.Y
        J.head = J.head % HN + 1
        J.ht[J.head], J.hy[J.head] = now, y
        if J.n < HN then J.n = J.n + 1 end

        -- el enemigo subio al menos "umbral" en los ultimos 0.15 s?  (umbral 25 = ~1.25 studs)
        local hBefore = heightAgo(now, 0.15)
        if not hBefore then return end
        if y - hBefore < config.jumpSyncVy / 20 then return end
        if now - J.lastJumpAt < 0.6 then return end -- un solo salto por salto del enemigo

        local mr, hum = myRoot(), humanoid
        if not hum or not hum.Parent or hum.Health <= 0 or not mr then return end
        if (tr.Position - mr.Position).Magnitude > config.jumpSyncRange then
            X.jstatus = "el enemigo salto, fuera de alcance"
            return
        end
        if BAD[hum:GetState()] or hum.PlatformStand or hum.Sit then
            X.jstatus = "no salte (aturdido / en el suelo)"
            return
        end
        if hum.FloorMaterial == Enum.Material.Air then
            X.jstatus = "no salte (ya estabas en el aire)"
            return
        end

        J.lastJumpAt = now
        local function go()
            if not hum.Parent or hum.Health <= 0 then return end
            hum.Jump = true
            pcall(function() hum:ChangeState(Enum.HumanoidStateType.Jumping) end)
            X.jstatus = "salte con el enemigo"
        end
        local d = config.jumpSyncDelay / 1000
        if d > 0 then task.delay(d, go) else go() end
    end)
end

-- ---------- INTERFAZ: cada seccion en su pestana + pestana ESTILO ----------
do
    local C = {
        acc = Color3.fromRGB(160, 120, 255), card = Color3.fromRGB(23, 23, 33), line = Color3.fromRGB(48, 48, 68),
        on = Color3.fromRGB(45, 160, 70), off = Color3.fromRGB(160, 50, 50), blue = Color3.fromRGB(70, 130, 220),
        white = Color3.fromRGB(255, 255, 255), dim = Color3.fromRGB(200, 200, 210),
    }
    local U = { y = 0, RH = 32, PAD = 8, GAP = 8, page = nil }
    local host = menuFrame:FindFirstChild("ZeidopSkinScroll")
    local W = {}

    -- ===== opacidad y forma de los botones flotantes =====
    X.floating = { lock = lockButton, jump = jumpBtn, dash = dashFloatBtn, mini = miniMenuBtn }
    X.preview = false
    X.orig = {}

    local function collect(b)
        local list = { { b, "BackgroundTransparency", b.BackgroundTransparency } }
        if b:IsA("TextButton") then list[#list + 1] = { b, "TextTransparency", b.TextTransparency } end
        for _, d in ipairs(b:GetDescendants()) do
            if d:IsA("UIStroke") then
                list[#list + 1] = { d, "Transparency", d.Transparency }
            elseif d:IsA("ImageLabel") or d:IsA("ImageButton") then
                list[#list + 1] = { d, "ImageTransparency", d.ImageTransparency }
                list[#list + 1] = { d, "BackgroundTransparency", d.BackgroundTransparency }
            elseif d:IsA("TextLabel") or d:IsA("TextButton") then
                list[#list + 1] = { d, "TextTransparency", d.TextTransparency }
                list[#list + 1] = { d, "BackgroundTransparency", d.BackgroundTransparency }
            end
        end
        return list
    end

    -- 0% = como siempre, 100% = invisible (el boton sigue ahi y sigue recibiendo toques)
    function X.applyStyle()
        local o = (config.btnOpacity or 0) / 100
        if X.preview then o = math.min(o, 0.5) end -- mientras mueves la barra se ven al 50% como maximo
        for key, b in pairs(X.floating) do
            local list = X.orig[b]
            if not list then
                list = collect(b)
                X.orig[b] = list
            end
            local this = o
            if key == "mini" and not config.opacityMini then this = 0 end
            for _, e in ipairs(list) do
                pcall(function() e[1][e[2]] = e[3] + (1 - e[3]) * this end)
            end
        end
    end

    function X.applyShape()
        for key, b in pairs(X.floating) do
            local r = (config.btnShape[key] == "square") and UDim.new(0, 4) or UDim.new(1, 0)
            local c = b:FindFirstChildOfClass("UICorner")
            if c then c.CornerRadius = r end
            for _, d in ipairs(b:GetDescendants()) do
                if d:IsA("UICorner") then d.CornerRadius = r end
            end
        end
    end

    -- ===== helpers de interfaz (mismo estilo que el skin) =====
    function U.use(page, y)
        U.page = page
        U.y = y or (page.Size.Y.Offset + 8)
    end
    function U.finish()
        U.page.Size = UDim2.new(1, 0, 0, U.y - 8)
    end
    function U.corner(o, r)
        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, r)
        c.Parent = o
    end
    function U.style(b, size)
        U.corner(b, 8)
        local g = Instance.new("UIGradient")
        g.Color = ColorSequence.new(C.white, Color3.fromRGB(205, 205, 205))
        g.Rotation = 90
        g.Parent = b
        local s = Instance.new("UIStroke")
        s.Color = C.white
        s.Transparency = 0.86
        s.Thickness = 1
        s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        s.Parent = b
        b.Font = Enum.Font.GothamBold
        b.TextSize = size
        b.TextColor3 = C.white
        b.BorderSizePixel = 0
        b.ZIndex = 2
    end
    function U.rowY(top, i) return top + (i - 1) * (U.RH + U.GAP) end
    function U.header(text)
        local l = Instance.new("TextLabel")
        l.BackgroundTransparency = 1
        l.Text = text
        l.Font = Enum.Font.GothamBold
        l.TextSize = 11
        l.TextColor3 = C.acc
        l.TextXAlignment = Enum.TextXAlignment.Left
        l.Position = UDim2.new(0, 6, 0, U.y)
        l.Size = UDim2.new(1, -12, 0, 14)
        l.ZIndex = 2
        l.Parent = U.page
        U.y = U.y + 18
    end
    function U.card(rows)
        local h = U.PAD * 2 + rows * U.RH + (rows - 1) * U.GAP
        local f = Instance.new("Frame")
        f.BackgroundColor3 = C.card
        f.BorderSizePixel = 0
        f.Position = UDim2.new(0, 0, 0, U.y)
        f.Size = UDim2.new(1, 0, 0, h)
        f.ZIndex = 1
        f.Parent = U.page
        U.corner(f, 10)
        local s = Instance.new("UIStroke")
        s.Color = C.line
        s.Transparency = 0.2
        s.Thickness = 1
        s.Parent = f
        local top = U.y + U.PAD
        U.y = U.y + h + 14
        return top
    end
    function U.hint(text, h)
        local l = Instance.new("TextLabel")
        l.BackgroundTransparency = 1
        l.Text = text
        l.Font = Enum.Font.Gotham
        l.TextSize = 10
        l.TextColor3 = Color3.fromRGB(130, 130, 150)
        l.TextXAlignment = Enum.TextXAlignment.Left
        l.TextYAlignment = Enum.TextYAlignment.Top
        l.TextWrapped = true
        l.Position = UDim2.new(0, 6, 0, U.y - 8)
        l.Size = UDim2.new(1, -12, 0, h)
        l.ZIndex = 2
        l.Parent = U.page
        U.y = U.y - 8 + h + 10
    end
    function U.label(text, top, i, ncols, size)
        local l = Instance.new("TextLabel")
        l.BackgroundTransparency = 1
        l.Text = text
        l.Font = Enum.Font.GothamBold
        l.TextSize = size or 12
        l.TextColor3 = C.dim
        l.TextXAlignment = Enum.TextXAlignment.Left
        l.TextWrapped = true
        l.Position = UDim2.new(0, 10, 0, U.rowY(top, i))
        l.Size = UDim2.new(1, -(20 + 48 * ncols), 0, U.RH)
        l.ZIndex = 2
        l.Parent = U.page
        return l
    end
    function U.btn(text, top, i, side, color, size)
        local b = Instance.new("TextButton")
        b.Text = text
        b.BackgroundColor3 = color or C.blue
        local y = U.rowY(top, i)
        if side == "F" then
            b.Position = UDim2.new(0, 8, 0, y)
            b.Size = UDim2.new(1, -16, 0, U.RH)
        elseif side == "L" then
            b.Position = UDim2.new(0, 8, 0, y)
            b.Size = UDim2.new(0.5, -12, 0, U.RH)
        else
            b.Position = UDim2.new(0.5, 4, 0, y)
            b.Size = UDim2.new(0.5, -12, 0, U.RH)
        end
        b.Parent = U.page
        U.style(b, size or 12)
        return b
    end
    function U.col(text, top, i, n)
        local b = Instance.new("TextButton")
        b.Text = text
        b.BackgroundColor3 = Color3.fromRGB(45, 45, 60)
        b.Position = UDim2.new(1, -(4 + 48 * n), 0, U.rowY(top, i))
        b.Size = UDim2.new(0, 44, 0, U.RH)
        b.Parent = U.page
        U.style(b, 18)
        return b
    end
    function U.toggle(b, text, get, set)
        local function paint()
            local on = get()
            b.Text = text .. ": " .. (on and "ON" or "OFF")
            b.BackgroundColor3 = on and C.on or C.off
        end
        paint()
        b.MouseButton1Click:Connect(function()
            set(not get())
            paint()
            saveConfig()
        end)
    end
    function U.stepper(lbl, minus, plus, fmt, get, set, lo, hi, step)
        local function paint() lbl.Text = string.format(fmt, get()) end
        paint()
        local function bump(d)
            local v = math.clamp(get() + d, lo, hi)
            set(math.floor(v * 100 + 0.5) / 100)
            paint()
            saveConfig()
        end
        minus.MouseButton1Click:Connect(function() bump(-step) end)
        plus.MouseButton1Click:Connect(function() bump(step) end)
    end

    -- barra arrastrable 0-100. Es un TextButton (Active) para que arrastrarla NO mueva el menu,
    -- y mientras la arrastras se apaga el scroll de la pagina para que no se vaya hacia arriba/abajo.
    function U.slider(top, i, get, set, onDrag)
        local tr = Instance.new("TextButton")
        tr.Text = ""
        tr.AutoButtonColor = false
        tr.BackgroundColor3 = Color3.fromRGB(34, 34, 48)
        tr.BorderSizePixel = 0
        tr.Position = UDim2.new(0, 8, 0, U.rowY(top, i))
        tr.Size = UDim2.new(1, -16, 0, U.RH)
        tr.ZIndex = 2
        tr.Parent = U.page
        U.corner(tr, 10)

        local bar = Instance.new("Frame")
        bar.BackgroundColor3 = Color3.fromRGB(58, 58, 78)
        bar.BorderSizePixel = 0
        bar.Position = UDim2.new(0, 16, 0.5, -4)
        bar.Size = UDim2.new(1, -32, 0, 8)
        bar.ZIndex = 3
        bar.Parent = tr
        U.corner(bar, 4)

        local fill = Instance.new("Frame")
        fill.BackgroundColor3 = C.acc
        fill.BorderSizePixel = 0
        fill.Size = UDim2.new(0, 0, 1, 0)
        fill.ZIndex = 4
        fill.Parent = bar
        U.corner(fill, 4)

        local knob = Instance.new("Frame")
        knob.BackgroundColor3 = C.white
        knob.BorderSizePixel = 0
        knob.Size = UDim2.new(0, 24, 0, 24)
        knob.ZIndex = 5
        knob.Parent = bar
        U.corner(knob, 12)

        local function paint()
            local v = math.clamp((get() or 0) / 100, 0, 1)
            fill.Size = UDim2.new(v, 0, 1, 0)
            knob.Position = UDim2.new(v, -12, 0.5, -12)
        end
        paint()

        local dragging = false
        local function fromX(x)
            local v = math.clamp((x - bar.AbsolutePosition.X) / math.max(bar.AbsoluteSize.X, 1), 0, 1)
            set(math.floor(v * 100 + 0.5))
            paint()
        end
        tr.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging = true
                if onDrag then onDrag(true) end
                fromX(input.Position.X)
                input.Changed:Connect(function()
                    if input.UserInputState == Enum.UserInputState.End then
                        dragging = false
                        if onDrag then onDrag(false) end
                    end
                end)
            end
        end)
        UserInputService.InputChanged:Connect(function(input)
            if not dragging then return end
            if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
                fromX(input.Position.X)
            end
        end)
        return paint
    end

    -- =====================================================================
    -- PESTANA ESTILO (nueva): opacidad + forma de los botones flotantes
    -- =====================================================================
    local stylePage = Instance.new("Frame")
    stylePage.Name = "ZeidopStylePage"
    stylePage.BackgroundTransparency = 1
    stylePage.Visible = false
    stylePage.Position = UDim2.new(0, 0, 0, 0)
    stylePage.Size = UDim2.new(1, 0, 0, 10)
    stylePage.Parent = host or contentArea
    U.use(stylePage, 0)

    U.header("OPACIDAD DE LOS BOTONES")
    do
        local t = U.card(3)
        local lbl = U.label("", t, 1, 2, 13)
        local vis = nil
        local function refresh()
            lbl.Text = string.format("Opacidad: %d%%", math.floor((config.btnOpacity or 0) + 0.5))
            if vis then vis() end
        end
        vis = U.slider(t, 2, function() return config.btnOpacity or 0 end, function(v)
            config.btnOpacity = v
            X.applyStyle()
            lbl.Text = string.format("Opacidad: %d%%", v)
        end, function(dragging)
            if host then host.ScrollingEnabled = not dragging end
            X.preview = dragging
            X.applyStyle()
            if not dragging then saveConfig() end
        end)
        local mn, pl = U.col("-", t, 1, 2), U.col("+", t, 1, 1)
        local function bump(d)
            config.btnOpacity = math.clamp(math.floor((config.btnOpacity or 0) / 5 + 0.5) * 5 + d, 0, 100)
            X.applyStyle()
            refresh()
            saveConfig()
        end
        mn.MouseButton1Click:Connect(function() bump(-5) end)
        pl.MouseButton1Click:Connect(function() bump(5) end)
        local rs = U.btn("Reiniciar (0%)", t, 3, "L", C.blue, 12)
        rs.MouseButton1Click:Connect(function()
            config.btnOpacity = 0
            X.applyStyle()
            refresh()
            saveConfig()
        end)
        local im = U.btn("", t, 3, "R", nil, 12)
        U.toggle(im, "Incluir menu", function() return config.opacityMini end, function(v)
            config.opacityMini = v
            X.applyStyle()
        end)
        refresh()
    end
    U.hint("100% = invisible, pero el boton sigue ahi y se toca igual. Mientras mueves la barra se ven al 50% para que no los pierdas. 'Incluir menu' tambien oculta el circulo pequeno del menu minimizado.", 44)

    U.header("FORMA DE CADA BOTON")
    do
        local t = U.card(2)
        local items = {
            { "lock", "LOCK", 1, "L" }, { "jump", "JUMP", 1, "R" },
            { "dash", "DASH", 2, "L" }, { "mini", "MENU", 2, "R" },
        }
        for _, n in ipairs(items) do
            local b = U.btn("", t, n[3], n[4], C.blue, 12)
            local function paint()
                b.Text = n[2] .. ": " .. ((config.btnShape[n[1]] == "square") and "CUADRADO" or "CIRCULO")
            end
            paint()
            b.MouseButton1Click:Connect(function()
                config.btnShape[n[1]] = (config.btnShape[n[1]] == "square") and "circle" or "square"
                X.applyShape()
                paint()
                saveConfig()
            end)
        end
    end
    U.hint("Cada boton cambia por separado. JUMP y DASH aparecen con los botones GEN de la pestana STUN.", 30)
    U.finish()

    -- pestana
    local tabB = Instance.new("TextButton")
    tabB.Text = "ESTILO"
    tabB.LayoutOrder = 5
    tabB.Size = UDim2.new(1, 0, 0, 38)
    tabB.BackgroundColor3 = Color3.fromRGB(35, 35, 50)
    tabB.Parent = tabBar
    U.style(tabB, 12)
    tabB.TextColor3 = Color3.fromRGB(180, 180, 190)
    tabs[#tabs + 1] = { btn = tabB, page = stylePage }
    tabB.MouseButton1Click:Connect(function()
        setActiveTab(#tabs)
        if host then
            host.CanvasPosition = Vector2.new(0, 0)
            host.CanvasSize = UDim2.new(0, 0, 0, stylePage.Size.Y.Offset)
        end
    end)

    -- =====================================================================
    -- PESTANA LOCK: predict adaptativo (va junto al predict)
    -- =====================================================================
    U.use(lockPage)
    U.header("PREDICT ADAPTATIVO")
    do
        local t = U.card(3)
        local b = U.btn("", t, 1, "F", nil, 12)
        U.toggle(b, "Predict adaptativo", function() return config.predictAdaptive end, function(v)
            config.predictAdaptive = v
            if not v then config.liveComp = 0 end
        end)
        local l = U.label("", t, 2, 2, 12)
        U.stepper(l, U.col("-", t, 2, 2), U.col("+", t, 2, 1), "Fuerza: x%.1f",
            function() return config.predictComp end, function(v) config.predictComp = v end, 0, 2, 0.1)
        W.pc = U.label("", t, 3, 0, 11)
    end
    U.finish()

    -- =====================================================================
    -- PESTANA STUN: saltar con el enemigo (va junto a los saltos)
    -- =====================================================================
    U.use(noStunPage)
    U.header("SALTAR CON EL ENEMIGO")
    do
        local t = U.card(5)
        local a = U.btn("", t, 1, "L")
        U.toggle(a, "Jump sync", function() return config.jumpSync end, function(v) config.jumpSync = v end)
        local b = U.btn("", t, 1, "R")
        U.toggle(b, "Solo con lock", function() return config.jumpSyncNeedLock end, function(v) config.jumpSyncNeedLock = v end)
        local l1 = U.label("", t, 2, 2, 12)
        U.stepper(l1, U.col("-", t, 2, 2), U.col("+", t, 2, 1), "Alcance: %.0f studs",
            function() return config.jumpSyncRange end, function(v) config.jumpSyncRange = v end, 5, 80, 5)
        local l2 = U.label("", t, 3, 2, 12)
        U.stepper(l2, U.col("-", t, 3, 2), U.col("+", t, 3, 1), "Retraso: %.0f ms",
            function() return config.jumpSyncDelay end, function(v) config.jumpSyncDelay = v end, 0, 300, 10)
        local l3 = U.label("", t, 4, 2, 12)
        U.stepper(l3, U.col("-", t, 4, 2), U.col("+", t, 4, 1), "Umbral salto: %.0f",
            function() return config.jumpSyncVy end, function(v) config.jumpSyncVy = v end, 10, 60, 5)
        W.js = U.label("", t, 5, 0, 11)
    end
    U.finish()

    -- =====================================================================
    -- PESTANA DASH: ajustes del assist (va junto al boton del assist)
    -- =====================================================================
    U.use(dashPage)
    U.header("AJUSTES DEL ASSIST")
    do
        local t = U.card(3)
        local a = U.btn("", t, 1, "L", nil, 11)
        U.toggle(a, "Sigue al lock", function() return config.assistFollowLock end, function(v) config.assistFollowLock = v end)
        local j = U.btn("", t, 1, "R", nil, 11)
        U.toggle(j, "Ignorar salto", function() return config.assistIgnoreJump end, function(v) config.assistIgnoreJump = v end)
        W.eff = U.label("", t, 2, 0, 11)
        W.dbg = U.label("", t, 3, 0, 11)
    end
    U.hint("Sigue al lock: con predict encendido el dash va al mismo punto que la camara. Ignorar salto: no corrige dashes hechos con salto.", 44)
    U.finish()

    -- la pestana LOCK es la que esta abierta al inicio: ajusta su scroll al nuevo largo
    if host then host.CanvasSize = UDim2.new(0, 0, 0, lockPage.Size.Y.Offset) end

    X.applyShape()
    X.applyStyle()

    -- etiquetas vivas (solo se actualizan en la pestana abierta)
    task.spawn(function()
        local P = X.perf
        while true do
            task.wait(0.5)
            if dashPage.Visible then
                local l2
                if config.assistFollowLock and config.predictEnabled then
                    l2 = string.format("Dash apunta como el lock (predict %d ms)",
                        math.floor((config.predictAmount + (config.liveComp or 0)) * 1000 + 0.5))
                else
                    l2 = "Dash con Lag / Max T fijos (engranaje)"
                end
                W.eff.Text = string.format("FPS %d  -  Ping %d ms\n", math.floor(P.fps + 0.5), math.floor(P.ping + 0.5)) .. l2
                W.dbg.Text = "Ultimo dash: " .. TH.dashStatus
            end
            if lockPage.Visible then
                if config.predictEnabled then
                    local cm = (config.predictAmount > 0) and (config.liveComp or 0) or 0
                    W.pc.Text = string.format("Predict %d ms + ajuste %d ms = %d ms  (ping peor %d)",
                        math.floor(config.predictAmount * 1000 + 0.5), math.floor(cm * 1000 + 0.5),
                        math.floor((config.predictAmount + cm) * 1000 + 0.5), math.floor(P.pingP90 + 0.5))
                else
                    W.pc.Text = "Predict apagado: no aplica"
                end
            end
            if noStunPage.Visible then
                W.js.Text = "Salto: " .. X.jstatus
            end
        end
    end)
end

print("Zeidop Hub v9 OK - LOCK + ASSIST + PREDICT ADAPTATIVO + JUMP SYNC + ESTILO + SELECTOR")
end
