--[[ Bsj Hub | Gunung Sumbing | WindUI ]]

if getgenv and getgenv().BsjHubLoaded then
    warn("Bsj Hub sudah berjalan")
    return
end
if getgenv then getgenv().BsjHubLoaded = true end

----------------------------------------------------------------
-- SERVICES
----------------------------------------------------------------
local WindUI = loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()

local Players         = game:GetService("Players")
local UIS             = game:GetService("UserInputService")
local RunService      = game:GetService("RunService")
local RS              = game:GetService("ReplicatedStorage")
local Lighting        = game:GetService("Lighting")
local TeleportService = game:GetService("TeleportService")
local HttpService     = game:GetService("HttpService")
local Loc             = game:GetService("LocalizationService")
local lp              = Players.LocalPlayer

----------------------------------------------------------------
-- STATE
----------------------------------------------------------------
local S = {
    move    = { infJump = false, noFall = false, speedOn = false, speed = 16,
                jumpOn = false, jump = 50, noclip = false, fovOn = false, fov = 70 },
    survive = { hunger = false, thirst = false },
    auto    = { eat = false, drink = false, threshold = 50 },
    weather = { freezeTemp = false, temp = 25, noRain = false, hideDmg = false, forceClear = false },
    anti    = { cold = false, minTemp = 25, god = false, noRagdoll = false, blockRemote = false, afk = false },
    visual  = { fullbright = false, esp = false },
    flag    = { id = "", on = false },
    tp      = { target = "", saved = nil },
}

local dmgLog, remoteLog = {}, {}
local origVolume = setmetatable({}, { __mode = "k" })

----------------------------------------------------------------
-- UTIL
----------------------------------------------------------------
local function notify(title, content)
    pcall(function()
        WindUI:Notify({ Title = title, Content = content, Duration = 5 })
    end)
end

local function copy(text)
    local ok = false
    if setclipboard then pcall(function() setclipboard(text) ok = true end) end
    return ok
end

local function getHumanoid()
    local c = lp.Character
    return c and c:FindFirstChildOfClass("Humanoid")
end

local function getRoot()
    local c = lp.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end

local function getCond(name)
    local cond = lp:FindFirstChild("Condition")
    return cond and cond:FindFirstChild(name)
end

local function setConnections(remote, enable)
    if not remote or not getconnections then return end
    pcall(function()
        for _, c in ipairs(getconnections(remote.OnClientEvent)) do
            if enable then c:Enable() else c:Disable() end
        end
    end)
end

local function pushLog(list, line, max)
    table.insert(list, line)
    if #list > (max or 50) then table.remove(list, 1) end
end

----------------------------------------------------------------
-- MOVEMENT
----------------------------------------------------------------
UIS.JumpRequest:Connect(function()
    if S.move.infJump then
        local hum = getHumanoid()
        if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
    end
end)

RunService.Heartbeat:Connect(function()
    local hum, hrp = getHumanoid(), getRoot()
    if not hum or not hrp then return end

    if S.move.noFall then
        local v = hrp.AssemblyLinearVelocity
        if v.Y < -50 then
            hrp.AssemblyLinearVelocity = Vector3.new(v.X, -50, v.Z)
        end
    end

    if S.move.speedOn then hum.WalkSpeed = S.move.speed end

    if S.move.jumpOn then
        hum.UseJumpPower = true
        hum.JumpPower = S.move.jump
    end

    if S.move.fovOn and workspace.CurrentCamera then
        workspace.CurrentCamera.FieldOfView = S.move.fov
    end
end)

-- Noclip
RunService.Stepped:Connect(function()
    if not S.move.noclip then return end
    local c = lp.Character
    if not c then return end
    for _, p in ipairs(c:GetDescendants()) do
        if p:IsA("BasePart") and p.CanCollide then
            p.CanCollide = false
        end
    end
end)

----------------------------------------------------------------
-- SURVIVAL (freeze lapar, haus, suhu)
----------------------------------------------------------------
task.spawn(function()
    while true do
        task.wait(0.2)
        local h, t, tp = getCond("Hunger"), getCond("Thirst"), getCond("Temperature")
        if S.survive.hunger and h then h.Value = 100 end
        if S.survive.thirst and t then t.Value = 100 end
        if S.weather.freezeTemp and tp then tp.Value = S.weather.temp end
    end
end)

----------------------------------------------------------------
-- AUTO MAKAN / MINUM
----------------------------------------------------------------
local busy = false

local function findItem(animName)
    local char, bp = lp.Character, lp:FindFirstChild("Backpack")
    for _, container in ipairs({ char, bp }) do
        if container then
            for _, tool in ipairs(container:GetChildren()) do
                if tool:IsA("Tool") and tool:FindFirstChild(animName, true) then
                    return tool
                end
            end
        end
    end
end

local function useItem(tool)
    local hum = getHumanoid()
    if not hum or hum.Health <= 0 or not tool then return end
    busy = true
    hum:EquipTool(tool)
    task.wait(0.4)
    pcall(function() tool:Activate() end)
    task.wait(2.5)
    pcall(function() hum:UnequipTools() end)
    busy = false
end

task.spawn(function()
    while true do
        task.wait(1)
        if not busy then
            local h, t = getCond("Hunger"), getCond("Thirst")
            if S.auto.eat and h and h.Value < S.auto.threshold then
                useItem(findItem("EatAnim"))
            elseif S.auto.drink and t and t.Value < S.auto.threshold then
                useItem(findItem("DrinkAnim"))
            end
        end
    end
end)

----------------------------------------------------------------
-- ANTI DINGIN
----------------------------------------------------------------
task.spawn(function()
    local hooked
    while true do
        task.wait(0.1)
        local t = getCond("Temperature")
        if t then
            if S.anti.cold and t.Value < S.anti.minTemp then
                t.Value = S.anti.minTemp
            end
            if t ~= hooked then
                hooked = t
                t:GetPropertyChangedSignal("Value"):Connect(function()
                    if S.anti.cold and t.Value < S.anti.minTemp then
                        t.Value = S.anti.minTemp
                    end
                end)
            end
        end
    end
end)

----------------------------------------------------------------
-- CUACA
----------------------------------------------------------------
local function muteSound(snd, mute)
    if mute then
        if origVolume[snd] == nil then origVolume[snd] = snd.Volume end
        snd.Volume = 0
    elseif origVolume[snd] ~= nil then
        snd.Volume = origVolume[snd]
        origVolume[snd] = nil
    end
end

local rainWasOn = false
task.spawn(function()
    while true do
        task.wait(0.5)

        local rainOff = S.weather.noRain
        local rain = lp.PlayerScripts:FindFirstChild("Rain")

        if rainOff then
            local amt = rain and rain:FindFirstChild("Settings") and rain.Settings:FindFirstChild("Rain Amount")
            if amt then amt.Value = 0 end
            for _, n in ipairs({ "Rain", "TorchRain" }) do
                setConnections(RS:FindFirstChild(n), false)
            end
        elseif rainWasOn then
            for _, n in ipairs({ "Rain", "TorchRain" }) do
                setConnections(RS:FindFirstChild(n), true)
            end
        end

        if rainOff or rainWasOn then
            local rs = rain and rain:FindFirstChild("Sounds")
            local rsnd = rs and rs:FindFirstChild("Rain")
            if rsnd then muteSound(rsnd, rainOff) end

            local main = lp.PlayerGui:FindFirstChild("MainFrame")
            local amb = main and main:FindFirstChild("AmbientWeather", true)
            if amb then
                for _, snd in ipairs(amb:GetChildren()) do
                    if snd:IsA("Sound") then muteSound(snd, rainOff) end
                end
            end
        end
        rainWasOn = rainOff

        if S.weather.forceClear then
            local cs = RS:FindFirstChild("CuacaSaatIni")
            if cs and cs.Value ~= "Terang" then cs.Value = "Terang" end
        end

        local di = lp.PlayerGui:FindFirstChild("DamageIndicator")
        if di and S.weather.hideDmg then di.Enabled = false end
    end
end)

local function applyHypoBlock(on)
    setConnections(RS:FindFirstChild("HypothermiaEffect"), not on)
end

----------------------------------------------------------------
-- PROTEKSI UMUM
----------------------------------------------------------------
local function setupCharacter(char)
    local hum = char:WaitForChild("Humanoid")
    local last = hum.Health

    hum.HealthChanged:Connect(function(hp)
        if hp < last then
            local t, cs = getCond("Temperature"), RS:FindFirstChild("CuacaSaatIni")
            local recent = #remoteLog > 0 and table.concat(remoteLog, ",") or "-"
            pushLog(dmgLog, ("-%.1f HP | suhu=%s | cuaca=%s | remote=%s"):format(
                last - hp,
                t and tostring(t.Value) or "?",
                cs and tostring(cs.Value) or "?",
                recent))
            if S.anti.god and hum.Health > 0 then
                hum.Health = hum.MaxHealth
            end
        end
        last = hp
    end)
end

if lp.Character then task.spawn(setupCharacter, lp.Character) end
lp.CharacterAdded:Connect(setupCharacter)

task.spawn(function()
    local states = {
        Enum.HumanoidStateType.FallingDown,
        Enum.HumanoidStateType.Ragdoll,
        Enum.HumanoidStateType.PlatformStanding,
    }
    while true do
        task.wait(0.5)
        local hum = getHumanoid()
        if hum then
            for _, st in ipairs(states) do
                pcall(function() hum:SetStateEnabled(st, not S.anti.noRagdoll) end)
            end
            if S.anti.god then hum.Health = math.max(hum.Health, 1) end
        end
    end
end)

local blockWords = { "damage", "dmg", "hurt", "fall", "harm", "hit" }
local function isDamageRemote(name)
    name = name:lower()
    for _, w in ipairs(blockWords) do
        if name:find(w, 1, true) then return true end
    end
    return false
end

if hookmetamethod and getnamecallmethod then
    local old
    old = hookmetamethod(game, "__namecall", function(self, ...)
        if getnamecallmethod() == "FireServer" and typeof(self) == "Instance" then
            local n = self.Name
            if n ~= "DeviceHandler" then pushLog(remoteLog, n, 5) end
            if S.anti.blockRemote and isDamageRemote(n) then return end
        end
        return old(self, ...)
    end)
end

local function copyDmgLog()
    local text = #dmgLog > 0 and table.concat(dmgLog, "\n") or "Belum ada damage tercatat."
    print(text)
    notify("Log Damage", #dmgLog .. " entri" .. (copy(text) and ", disalin" or ", cek console (F9)"))
end

-- Anti AFK
lp.Idled:Connect(function()
    if not S.anti.afk then return end
    pcall(function()
        local vu = game:GetService("VirtualUser")
        vu:CaptureController()
        vu:ClickButton2(Vector2.new())
    end)
end)

----------------------------------------------------------------
-- VISUAL: FULLBRIGHT & ESP
----------------------------------------------------------------
local origLight = {
    Brightness = Lighting.Brightness,
    ClockTime = Lighting.ClockTime,
    FogEnd = Lighting.FogEnd,
    GlobalShading = Lighting.GlobalShading,
    Ambient = Lighting.Ambient,
}

local function setFullbright(on)
    if on then
        Lighting.Brightness = 2
        Lighting.ClockTime = 14
        Lighting.FogEnd = 1e6
        Lighting.GlobalShading = false
        Lighting.Ambient = Color3.fromRGB(170, 170, 170)
    else
        for k, v in pairs(origLight) do pcall(function() Lighting[k] = v end) end
    end
end

task.spawn(function()
    while true do
        task.wait(1)
        if S.visual.fullbright then setFullbright(true) end
    end
end)

local espObjects = {}

local function clearEsp()
    for _, h in pairs(espObjects) do pcall(function() h:Destroy() end) end
    table.clear(espObjects)
end

task.spawn(function()
    while true do
        task.wait(1)
        if S.visual.esp then
            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= lp and p.Character and not espObjects[p] then
                    local h = Instance.new("Highlight")
                    h.FillColor = Color3.fromRGB(255, 80, 80)
                    h.FillTransparency = 0.6
                    h.OutlineColor = Color3.new(1, 1, 1)
                    h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                    h.Adornee = p.Character
                    h.Parent = p.Character
                    espObjects[p] = h
                end
            end
            for p, h in pairs(espObjects) do
                if not p.Parent or not p.Character or h.Adornee ~= p.Character then
                    pcall(function() h:Destroy() end)
                    espObjects[p] = nil
                end
            end
        elseif next(espObjects) then
            clearEsp()
        end
    end
end)

----------------------------------------------------------------
-- TELEPORT & SERVER
----------------------------------------------------------------
local function findPlayer(query)
    query = query:lower()
    if query == "" then return nil end
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= lp and (p.Name:lower():find(query, 1, true) or p.DisplayName:lower():find(query, 1, true)) then
            return p
        end
    end
end

local function teleportToPlayer()
    local p = findPlayer(S.tp.target)
    local root, targetRoot = getRoot(), p and p.Character and p.Character:FindFirstChild("HumanoidRootPart")
    if root and targetRoot then
        root.CFrame = targetRoot.CFrame * CFrame.new(0, 0, 3)
        notify("Teleport", "Ke " .. p.Name)
    else
        notify("Teleport", "Pemain tidak ditemukan")
    end
end

local function savePosition()
    local root = getRoot()
    if root then
        S.tp.saved = root.CFrame
        notify("Posisi", "Tersimpan")
    end
end

local function loadPosition()
    local root = getRoot()
    if root and S.tp.saved then
        root.CFrame = S.tp.saved
    else
        notify("Posisi", "Belum ada posisi tersimpan")
    end
end

local function copyCoords()
    local root = getRoot()
    if root then
        local p = root.Position
        notify("Koordinat", ("%.1f, %.1f, %.1f%s"):format(p.X, p.Y, p.Z, copy(("%.1f, %.1f, %.1f"):format(p.X, p.Y, p.Z)) and " (disalin)" or ""))
    end
end

local function rejoin()
    pcall(function() TeleportService:Teleport(game.PlaceId, lp) end)
end

local function serverHop()
    local ok, err = pcall(function()
        local url = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100"):format(game.PlaceId)
        local data = HttpService:JSONDecode(game:HttpGet(url))
        for _, s in ipairs(data.data or {}) do
            if s.id ~= game.JobId and s.playing < s.maxPlayers then
                TeleportService:TeleportToPlaceInstance(game.PlaceId, s.id, lp)
                return
            end
        end
        notify("Server Hop", "Tidak ada server lain yang tersedia")
    end)
    if not ok then notify("Server Hop", "Gagal: " .. tostring(err)) end
end

----------------------------------------------------------------
-- SCANNER
----------------------------------------------------------------
local function scanKeys(keys, roots)
    local function match(name)
        name = name:lower()
        for _, k in ipairs(keys) do
            if name:find(k, 1, true) then return true end
        end
        return false
    end
    local results = {}
    for _, r in ipairs(roots) do
        local root, label = r[1], r[2]
        if root then
            for _, o in ipairs(root:GetDescendants()) do
                if match(o.Name) then
                    local val = ""
                    if o:IsA("ValueBase") then val = tostring(o.Value) end
                    if o:IsA("ImageLabel") or o:IsA("ImageButton") then val = o.Image end
                    table.insert(results, ("[%s] %s (%s) %s"):format(label, o:GetFullName(), o.ClassName, val))
                end
                for attr, val in pairs(o:GetAttributes()) do
                    if match(attr) then
                        table.insert(results, ("[%s][Attr] %s.%s = %s"):format(label, o:GetFullName(), attr, tostring(val)))
                    end
                end
            end
        end
    end
    return results
end

local function finishScan(title, results)
    local text = #results > 0 and table.concat(results, "\n") or "Tidak ada yang ditemukan."
    print("===== " .. title .. " =====")
    print(text)
    notify(title, #results .. " hasil" .. (copy(text) and ", disalin ke clipboard" or ", cek console (F9)"))
end

local function scanSurvival()
    finishScan("Scan Lapar/Haus", scanKeys(
        { "hunger", "thirst", "food", "water", "lapar", "haus", "makan", "minum", "stamina", "energy" },
        { { lp, "Player" }, { lp.Character, "Character" }, { RS, "ReplicatedStorage" } }
    ))
end

local function scanWeather()
    local out = {}
    for _, fname in ipairs({ "Condition", "Stats" }) do
        local f = lp:FindFirstChild(fname)
        if f then
            for _, o in ipairs(f:GetChildren()) do
                local val = o:IsA("ValueBase") and tostring(o.Value) or ""
                table.insert(out, ("[%s] %s = %s"):format(fname, o.Name, val))
            end
        end
    end
    local tf = RS:FindFirstChild("Temperature")
    if tf then
        for _, o in ipairs(tf:GetDescendants()) do
            local val = o:IsA("ValueBase") and tostring(o.Value) or ""
            table.insert(out, ("[RS.Temperature] %s (%s) %s"):format(o:GetFullName(), o.ClassName, val))
        end
    end
    local cs = RS:FindFirstChild("CuacaSaatIni")
    if cs then table.insert(out, "[Cuaca] CuacaSaatIni = " .. tostring(cs.Value)) end
    local hum = getHumanoid()
    if hum then table.insert(out, ("[Health] %s / %s"):format(hum.Health, hum.MaxHealth)) end
    finishScan("Scan Cuaca & Suhu", out)
end

local function scanDamageSources()
    local out = {}
    local keys = { "damage", "dmg", "hurt", "harm", "lava", "kill", "fall", "lightning", "petir", "poison", "racun" }
    for _, line in ipairs(scanKeys(keys, { { RS, "ReplicatedStorage" }, { lp.PlayerScripts, "Scripts" }, { lp.PlayerGui, "Gui" } })) do
        table.insert(out, line)
    end
    table.insert(out, "--- remote yang baru dikirim ---")
    table.insert(out, #remoteLog > 0 and table.concat(remoteLog, ", ") or "-")
    finishScan("Scan Sumber Damage", out)
end

local function scanRemotes()
    local out = {}
    for _, o in ipairs(RS:GetDescendants()) do
        if (o:IsA("RemoteEvent") or o:IsA("RemoteFunction")) and not o:GetFullName():find("HDAdmin") then
            table.insert(out, ("%s (%s)"):format(o:GetFullName(), o.ClassName))
        end
    end
    finishScan("Daftar Remote Game", out)
end

local function scanFlag()
    local out = {}
    local ok, region = pcall(function() return Loc:GetCountryRegionForPlayerAsync(lp) end)
    table.insert(out, "Region akun: " .. tostring(ok and region or "gagal"))
    table.insert(out, "Country_Code: " .. tostring(lp:GetAttribute("Country_Code")))
    for _, line in ipairs(scanKeys(
        { "flag", "bendera", "country", "negara", "nation" },
        { { RS, "RS" }, { lp.PlayerScripts, "Scripts" }, { lp.PlayerGui, "Gui" } }
    )) do
        table.insert(out, line)
    end
    finishScan("Scan Bendera", out)
end

----------------------------------------------------------------
-- BENDERA
----------------------------------------------------------------
local function normId(id)
    id = tostring(id):gsub("%s", "")
    if id == "" then return nil end
    if id:match("^%d+$") then return "rbxassetid://" .. id end
    return id
end

task.spawn(function()
    while true do
        task.wait(0.3)
        if S.flag.on then
            local head = lp.Character and lp.Character:FindFirstChild("Head")
            local tag = head and head:FindFirstChild("NameTag")
            local frame = tag and tag:FindFirstChild("Frame")
            local detail = frame and frame:FindFirstChild("FrameDetail")
            local country = detail and detail:FindFirstChild("Country")
            local img = normId(S.flag.id)
            if country and img then country.Image = img end
        end
    end
end)

----------------------------------------------------------------
-- UI
----------------------------------------------------------------
local Window = WindUI:CreateWindow({
    Title = "Bsj Hub",
    Icon = "zap",
    Author = "Bsj",
    Folder = "BsjHub",
    Size = UDim2.fromOffset(520, 400),
    Theme = "Dark",
})

local function section(tab, title)
    pcall(function() tab:Section({ Title = title }) end)
end

-- Gerak
local MoveTab = Window:Tab({ Title = "Gerak", Icon = "footprints" })
section(MoveTab, "Lompat & Kecepatan")
MoveTab:Toggle({ Title = "Unlimited Jump", Default = false, Callback = function(v) S.move.infJump = v end })
MoveTab:Toggle({
    Title = "Aktifkan Speed",
    Default = false,
    Callback = function(v)
        S.move.speedOn = v
        if not v then
            local hum = getHumanoid()
            if hum then hum.WalkSpeed = 16 end
        end
    end,
})
MoveTab:Slider({
    Title = "Walk Speed",
    Value = { Min = 16, Max = 200, Default = 16 },
    Callback = function(v) S.move.speed = v end,
})
MoveTab:Toggle({
    Title = "Aktifkan Jump Power",
    Default = false,
    Callback = function(v)
        S.move.jumpOn = v
        if not v then
            local hum = getHumanoid()
            if hum then hum.JumpPower = 50 end
        end
    end,
})
MoveTab:Slider({
    Title = "Jump Power",
    Value = { Min = 50, Max = 300, Default = 50 },
    Callback = function(v) S.move.jump = v end,
})
section(MoveTab, "Lainnya")
MoveTab:Toggle({ Title = "Noclip", Default = false, Callback = function(v) S.move.noclip = v end })
MoveTab:Toggle({ Title = "Aktifkan FOV", Default = false, Callback = function(v)
    S.move.fovOn = v
    if not v and workspace.CurrentCamera then workspace.CurrentCamera.FieldOfView = 70 end
end })
MoveTab:Slider({
    Title = "Field of View",
    Value = { Min = 40, Max = 120, Default = 70 },
    Callback = function(v) S.move.fov = v end,
})

-- Bertahan
local SurviveTab = Window:Tab({ Title = "Bertahan", Icon = "utensils" })
section(SurviveTab, "Auto Makan / Minum (disarankan)")
SurviveTab:Toggle({ Title = "Auto Makan", Default = false, Callback = function(v) S.auto.eat = v end })
SurviveTab:Toggle({ Title = "Auto Minum", Default = false, Callback = function(v) S.auto.drink = v end })
SurviveTab:Slider({
    Title = "Makan/Minum di bawah",
    Value = { Min = 10, Max = 90, Default = 50 },
    Callback = function(v) S.auto.threshold = v end,
})
section(SurviveTab, "Freeze (tampilan client)")
SurviveTab:Toggle({ Title = "Freeze Lapar", Default = false, Callback = function(v) S.survive.hunger = v end })
SurviveTab:Toggle({ Title = "Freeze Haus", Default = false, Callback = function(v) S.survive.thirst = v end })

-- Cuaca
local WeatherTab = Window:Tab({ Title = "Cuaca", Icon = "cloud-rain" })
section(WeatherTab, "Suhu")
WeatherTab:Toggle({ Title = "Freeze Suhu", Default = false, Callback = function(v) S.weather.freezeTemp = v end })
WeatherTab:Slider({
    Title = "Nilai Suhu",
    Value = { Min = 10, Max = 40, Default = 25 },
    Callback = function(v) S.weather.temp = v end,
})
section(WeatherTab, "Hujan & Efek")
WeatherTab:Toggle({ Title = "Matikan Hujan (visual + suara)", Default = false, Callback = function(v) S.weather.noRain = v end })
WeatherTab:Toggle({ Title = "Paksa Cuaca Terang (lokal)", Default = false, Callback = function(v) S.weather.forceClear = v end })
WeatherTab:Toggle({ Title = "Sembunyikan Damage Indicator", Default = false, Callback = function(v)
    S.weather.hideDmg = v
    local di = lp.PlayerGui:FindFirstChild("DamageIndicator")
    if di then di.Enabled = not v end
end })

-- Proteksi
local ProtTab = Window:Tab({ Title = "Proteksi", Icon = "shield" })
section(ProtTab, "Damage Cuaca")
ProtTab:Toggle({ Title = "Anti Damage Dingin", Default = false, Callback = function(v)
    S.anti.cold = v
    applyHypoBlock(v)
end })
ProtTab:Slider({
    Title = "Batas Suhu Minimum",
    Value = { Min = 15, Max = 36, Default = 25 },
    Callback = function(v) S.anti.minTemp = v end,
})
ProtTab:Toggle({ Title = "Anti Damage Hujan", Default = false, Callback = function(v) S.weather.noRain = v end })
section(ProtTab, "Damage Umum")
ProtTab:Toggle({ Title = "Anti Fall Damage", Default = false, Callback = function(v) S.move.noFall = v end })
ProtTab:Toggle({ Title = "Health Lock (client)", Default = false, Callback = function(v) S.anti.god = v end })
ProtTab:Toggle({ Title = "Anti Ragdoll / Jatuh", Default = false, Callback = function(v) S.anti.noRagdoll = v end })
ProtTab:Toggle({ Title = "Blokir Remote Damage", Default = false, Callback = function(v) S.anti.blockRemote = v end })
section(ProtTab, "Lainnya")
ProtTab:Toggle({ Title = "Anti AFK", Default = false, Callback = function(v) S.anti.afk = v end })
ProtTab:Button({ Title = "Salin Log Damage", Desc = "Darah turun + suhu + cuaca + remote", Callback = copyDmgLog })

-- Visual
local VisualTab = Window:Tab({ Title = "Visual", Icon = "eye" })
VisualTab:Toggle({ Title = "Fullbright (terang di malam hari)", Default = false, Callback = function(v)
    S.visual.fullbright = v
    setFullbright(v)
end })
VisualTab:Toggle({ Title = "ESP Pemain", Default = false, Callback = function(v) S.visual.esp = v end })

-- Teleport
local TpTab = Window:Tab({ Title = "Teleport", Icon = "map-pin" })
section(TpTab, "Ke Pemain")
TpTab:Input({
    Title = "Nama Pemain",
    Placeholder = "sebagian nama juga bisa",
    Callback = function(v) S.tp.target = v end,
})
TpTab:Button({ Title = "Teleport ke Pemain", Callback = teleportToPlayer })
section(TpTab, "Posisi Tersimpan")
TpTab:Button({ Title = "Simpan Posisi Sekarang", Callback = savePosition })
TpTab:Button({ Title = "Teleport ke Posisi Tersimpan", Callback = loadPosition })
TpTab:Button({ Title = "Salin Koordinat", Callback = copyCoords })
section(TpTab, "Server")
TpTab:Button({ Title = "Rejoin", Callback = rejoin })
TpTab:Button({ Title = "Server Hop", Callback = serverHop })

-- Scanner
local ScanTab = Window:Tab({ Title = "Scanner", Icon = "search" })
ScanTab:Button({ Title = "Scan Lapar / Haus", Callback = scanSurvival })
ScanTab:Button({ Title = "Scan Cuaca & Suhu", Callback = scanWeather })
ScanTab:Button({ Title = "Scan Sumber Damage", Desc = "Cari remote/objek damage", Callback = scanDamageSources })
ScanTab:Button({ Title = "Daftar Semua Remote", Desc = "Remote game (tanpa HD Admin)", Callback = scanRemotes })
ScanTab:Button({ Title = "Scan Bendera / Negara", Callback = scanFlag })

-- Bendera
local FlagTab = Window:Tab({ Title = "Bendera", Icon = "flag" })
FlagTab:Input({
    Title = "ID Gambar Bendera",
    Placeholder = "contoh: 123456789",
    Callback = function(v) S.flag.id = v end,
})
FlagTab:Toggle({ Title = "Ganti Bendera", Default = false, Callback = function(v) S.flag.on = v end })

notify("Bsj Hub", "Script berhasil dimuat")
