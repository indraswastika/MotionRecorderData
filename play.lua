-- Hazel Path Player (Rayfield Edition)
-- 100% Playback Only - No Recording Features
-- Optimized for performance and scalability

local function runPlayer()
    -- Services
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local HttpService = game:GetService("HttpService")
    local UserInputService = game:GetService("UserInputService")
    local TweenService = game:GetService("TweenService")
    local StarterGui = game:GetService("StarterGui")

    local Player = Players.LocalPlayer
    if not Player then return end

    -- Wait for character
    local Character = Player.Character or Player.CharacterAdded:Wait()
    local Humanoid = Character:WaitForChild("Humanoid")
    local RootPart = Character:WaitForChild("HumanoidRootPart")
    local Animator = Humanoid:FindFirstChild("Animator") or Humanoid:WaitForChild("Animator")

    -- State & Config
    local State = {
        isPlaying = false,
        isPaused = false,
        isLooping = false,
        repSpeed = 1.0,
        repData = nil, -- Full data
        localPlayCopy = nil, -- Lightweight copy for playback
        curFrame = 1,
        pbElapsed = 0,
        wallBase = 0,
        elapsedAtBase = 0,
        realElapsedBase = 0,
        realWallBase = 0,
        loopCount = 0,
        lastWipeFrame = 0,
        playConn = nil,
        
        -- Loop Target System
        lsEnabled = false,
        lsTarget = 0,
        lsReached = false,
        initSummit = 0,
        
        -- Memory / Performance
        activeRepTracks = {},
        animPool = {},
        cfCache = {idxA=-1, idxB=-1, cfA=nil, cfB=nil},
        MAX_FRAMES = 108000,
        RAM_WIPE = 30,
        HAS_IO = (typeof(readfile) == "function" and typeof(writefile) == "function"),
        SAVE_FOLDER = "MTP_Replays"
    }

    -- Helper Functions
    local function Notify(title, text, duration)
        StarterGui:SetCore("SendNotification", {
            Title = title or "Hazel Path",
            Text = text or "",
            Duration = duration or 3
        })
    end

    local function FormatTime(s)
        s = math.max(0, s or 0)
        local h = math.floor(s / 3600)
        local m = math.floor((s % 3600) / 60)
        local sc = math.floor(s % 60)
        if h > 0 then
            return string.format("%02d:%02d:%02d", h, m, sc)
        else
            return string.format("%02d:%02d", m, sc)
        end
    end

    local function FormatTimeDec(s)
        s = math.max(0, s or 0)
        return string.format("%02d:%04.1f", math.floor(s/60), s%60)
    end

    -- Math & CFrames (Optimized)
    local function CfFromData(cfd)
        if not cfd then return CFrame.new() end
        local p, lv, rv, uv = cfd.p, cfd.lv, cfd.rv, cfd.uv
        if not (p and lv and rv and uv) then return CFrame.new() end
        -- Construct CFrame from components (Matrix)
        return CFrame.fromMatrix(
            Vector3.new(p[1], p[2], p[3]),
            Vector3.new(rv[1], rv[2], rv[3]),
            Vector3.new(uv[1], uv[2], uv[3]),
            -Vector3.new(lv[1], lv[2], lv[3])
        )
    end

    local function CfToQuat(cf)
        local rx, ry, rz = cf.RightVector.X, cf.RightVector.Y, cf.RightVector.Z
        local ux, uy, uz = cf.UpVector.X, cf.UpVector.Y, cf.UpVector.Z
        local bx, by, bz = -cf.LookVector.X, -cf.LookVector.Y, -cf.LookVector.Z
        local tr = rx + uy + bz
        local w, x, y, z
        if tr > 0 then
            local s = 0.5 / math.sqrt(tr + 1)
            w, x, y, z = 0.25 / s, (uz - by) * s, (bx - rz) * s, (ry - ux) * s
        elseif rx > uy and rx > bz then
            local s = 2 * math.sqrt(1 + rx - uy - bz)
            w, x, y, z = (uz - by) / s, 0.25 * s, (uy + rx) / s, (bx + rz) / s
        elseif uy > bz then
            local s = 2 * math.sqrt(1 + uy - rx - bz)
            w, x, y, z = (bx - rz) / s, (ux + ry) / s, 0.25 * s, (uz + by) / s
        else
            local s = 2 * math.sqrt(1 + bz - rx - uy)
            w, x, y, z = (ry - ux) / s, (bx + rz) / s, (uz + by) / s, 0.25 * s
        end
        return {w=w, x=x, y=y, z=z}
    end

    local function QuatSlerp(a, b, t)
        local dot = a.w * b.w + a.x * b.x + a.y * b.y + a.z * b.z
        if dot < 0 then b = {w=-b.w, x=-b.x, y=-b.y, z=-b.z}; dot = -dot end
        dot = math.clamp(dot, -1, 1)
        local s0, s1
        if dot > 0.9995 then
            s0, s1 = 1 - t, t
        else
            local th = math.acos(dot)
            local sth = math.sin(th)
            s0, s1 = math.sin((1 - t) * th) / sth, math.sin(t * th) / sth
        end
        local r = {
            w = s0 * a.w + s1 * b.w,
            x = s0 * a.x + s1 * b.x,
            y = s0 * a.y + s1 * b.y,
            z = s0 * a.z + s1 * b.z
        }
        local l = math.sqrt(r.w*r.w + r.x*r.x + r.y*r.y + r.z*r.z)
        if l < 1e-6 then return a end
        return {w=r.w/l, x=r.x/l, y=r.y/l, z=r.z/l}
    end

    local function QuatToCF(q, pos)
        local w, x, y, z = q.w, q.x, q.y, q.z
        local xx, yy, zz = x*x, y*y, z*z
        local xy, xz, yz = x*y, x*z, y*z
        local wx, wy, wz = w*x, w*y, w*z
        return CFrame.new(
            pos.X, pos.Y, pos.Z,
            1 - 2*(yy+zz), 2*(xy-wz), 2*(xz+wy),
            2*(xy+wz), 1 - 2*(xx+zz), 2*(yz-wx),
            2*(xz-wy), 2*(yz+wx), 1 - 2*(xx+yy)
        )
    end

    local function LerpCF(a, b, t)
        return QuatToCF(QuatSlerp(CfToQuat(a), CfToQuat(b), t), a.Position:Lerp(b.Position, t))
    end

    -- Core Logic
    local function GetSummit()
        local ls = Player:FindFirstChild("leaderstats")
        if ls then
            for _, v in ipairs(ls:GetChildren()) do
                if v.Name:lower():find("summit") then return v.Value or 0 end
            end
        end
        -- Fallback search
        for _, v in ipairs(Player:GetDescendants()) do
            if v.Name:lower():find("summit") and (v:IsA("IntValue") or v:IsA("NumberValue")) then
                return v.Value or 0
            end
        end
        return 0
    end

    local function ClearAllAnims()
        for _, tr in pairs(State.activeRepTracks) do
            pcall(function() if tr and tr.IsPlaying then tr:Stop(0.05) end end)
        end
        State.activeRepTracks = {}
    end

    local function PlayAnimData(aA, aB, alpha)
        local tp = aA.tp
        if aB and alpha and alpha > 0 then
            tp = aA.tp + (aB.tp - aA.tp) * alpha
        end

        local ex = State.activeRepTracks[aA.id]
        if ex and not ex.IsPlaying then
            State.activeRepTracks[aA.id] = nil
            ex = nil
        end

        if ex then
            pcall(function() ex:AdjustSpeed(aA.sp * State.repSpeed) end)
            pcall(function() 
                if math.abs(ex.TimePosition - tp) > 0.15 then 
                    ex.TimePosition = tp 
                end 
            end)
            return
        end

        local anim = State.animPool[aA.id]
        if not anim then
            anim = Instance.new("Animation")
            anim.AnimationId = aA.id
            State.animPool[aA.id] = anim
        end

        local animator = Animator
        if not animator then return end

        local ok, track = pcall(function() return animator:LoadAnimation(anim) end)
        if not ok or not track then return end

        local pri = Enum.AnimationPriority.Core
        if aA.pri:find("Action") then pri = Enum.AnimationPriority.Action end
        if aA.pri:find("Movement") then pri = Enum.AnimationPriority.Movement end
        
        pcall(function()
            track.Priority = pri
            track:Play(0.05)
            track:AdjustSpeed(aA.sp * State.repSpeed)
            track.TimePosition = tp
        end)
        State.activeRepTracks[aA.id] = track
    end

    local function FindFrame(data, targetT)
        if targetT <= data[1].t then return 1 end
        if targetT >= data[#data].t then return math.max(1, #data - 1) end
        local lo, hi = 1, #data - 1
        while lo < hi do
            local mid = math.floor((lo + hi + 1) / 2)
            if data[mid].t <= targetT then
                lo = mid
            else
                hi = mid - 1
            end
        end
        return lo
    end

    local function MakeLocalCopy(d)
        local c = table.create(#d)
        for i = 1, #d do
            local s = d[i]
            c[i] = {t = s.t, dt = s.dt, ws = s.ws, cfd = s.cfd, anims = s.anims}
        end
        return c
    end

    local function StopReplay()
        if not State.isPlaying then return end
        State.isPlaying = false
        State.isPaused = false
        
        if State.playConn then
            State.playConn:Disconnect()
            State.playConn = nil
        end

        ClearAllAnims()
        if State.localPlayCopy then
            for i = 1, #State.localPlayCopy do
                if State.localPlayCopy[i] then
                    State.localPlayCopy[i].cfd = nil
                    State.localPlayCopy[i].anims = nil
                    State.localPlayCopy[i] = nil
                end
            end
            State.localPlayCopy = nil
        end

        -- Reset Character State
        pcall(function()
            Humanoid.AutoRotate = true
            Humanoid.WalkSpeed = 16
            Humanoid.PlatformStand = false
        end)
        
        -- Cleanup UI
        Rayfield:Notify("Playback Stopped", "Loop count: " .. State.loopCount)
    end

    local function PlayReplay()
        local rd = State.repData
        if not rd or #rd == 0 then
            Rayfield:Notify("Error", "No data loaded. Load a file or URL first.")
            return
        end

        if State.isPlaying then
            -- Pause Logic
            State.isPaused = not State.isPaused
            if State.isPaused then
                State.pbElapsed = State.pbElapsed + (tick() - State.wallBase) * State.repSpeed
                Rayfield:Notify("Paused", FormatTime(State.pbElapsed))
            else
                State.wallBase = tick()
                State.elapsedAtBase = State.pbElapsed
            end
            return
        end

        -- Start Logic
        State.isPlaying = true
        State.isPaused = false
        State.curFrame = 1
        State.loopCount = 0
        State.pbElapsed = 0
        State.elapsedAtBase = 0
        State.wallBase = tick()
        State.realElapsedBase = 0
        State.realWallBase = tick()
        State.lastWipeFrame = 0
        State.lsReached = false
        State.initSummit = GetSummit()

        -- Prepare Data Copy
        State.localPlayCopy = MakeLocalCopy(rd)

        pcall(function() Humanoid.AutoRotate = false end)
        Rayfield:Notify("Playing", "Started replay")

        State.playConn = RunService.Heartbeat:Connect(function(dt)
            if not State.isPlaying or State.isPaused then return end

            State.pbElapsed = State.elapsedAtBase + (tick() - State.wallBase) * State.repSpeed
            
            local dur = rd[#rd].t - rd[1].t
            if State.pbElapsed >= dur then
                if State.isLooping then
                    -- Loop Stop Target Check
                    if State.lsEnabled and not State.lsReached then
                        local curS = GetSummit()
                        if curS >= State.lsTarget then
                            State.lsReached = true
                            StopReplay()
                            Rayfield:Notify("Target Reached!", "Summit " .. State.lsTarget .. " hit.")
                            return
                        end
                    end

                    -- Reset Loop
                    State.loopCount = State.loopCount + 1
                    State.pbElapsed = 0
                    State.elapsedAtBase = 0
                    State.wallBase = tick()
                    State.curFrame = 1
                    State.lastWipeFrame = 0
                    State.cfCache.idxA = -1
                    State.cfCache.idxB = -1
                else
                    StopReplay()
                    Rayfield:Notify("Finished", "Replay completed.")
                    return
                end
            end

            local targetT = rd[1].t + State.pbElapsed
            local fA = FindFrame(rd, targetT)
            local fB = math.min(fA + 1, #rd)
            State.curFrame = fA

            -- Memory Wipe
            if not State.isLooping and fA > State.lastWipeFrame + State.RAM_WIPE then
                local wt = fA - State.RAM_WIPE
                for i = State.lastWipeFrame + 1, wt do
                    if State.localPlayCopy[i] then
                        State.localPlayCopy[i].cfd = nil
                        State.localPlayCopy[i].anims = nil
                        State.localPlayCopy[i] = nil
                    end
                end
                State.lastWipeFrame = wt
            end

            local frmA = State.localPlayCopy[fA]
            local frmB = State.localPlayCopy[fB]
            if not frmA or not frmA.cfd then return end

            -- Interpolation
            local alpha = 0
            if frmB and frmB.cfd then
                local span = frmB.t - frmA.t
                if span > 0.0001 then alpha = math.clamp((targetT - frmA.t) / span, 0, 1) end
            end

            -- CFrame Calc
            local cfA, cfB2
            if State.cfCache.idxA == fA then
                cfA = State.cfCache.cfA
            else
                cfA = CfFromData(frmA.cfd)
                State.cfCache.idxA = fA
                State.cfCache.cfA = cfA
            end

            local targetCF
            if frmB and frmB.cfd then
                if State.cfCache.idxB == fB then
                    cfB2 = State.cfCache.cfB
                else
                    cfB2 = CfFromData(frmB.cfd)
                    State.cfCache.idxB = fB
                    State.cfCache.cfB = cfB2
                end
                targetCF = LerpCF(cfA, cfB2, alpha)
            else
                targetCF = cfA
            end

            -- Apply to Character
            pcall(function()
                RootPart.CFrame = targetCF
                if frmB and frmB.cfd then
                    local wsA = frmA.ws or 16
                    local wsB = frmB.ws or 16
                    Humanoid.WalkSpeed = wsA + (wsB - wsA) * alpha
                end
            end)

            -- Animations
            if frmA.anims and #frmA.anims > 0 then
                local animMapB = {}
                if frmB and frmB.anims then
                    for _, ab in ipairs(frmB.anims) do animMapB[ab.id] = ab end
                end
                for _, ad in ipairs(frmA.anims) do
                    pcall(PlayAnimData, ad, animMapB[ad.id], alpha)
                end
            end
        end)
    end

    -- File I/O
    local function EnsureFolder()
        if not State.HAS_IO then return end
        pcall(function()
            if not isfolder(State.SAVE_FOLDER) then
                makefolder(State.SAVE_FOLDER)
            end
        end)
    end

    local function NormalizeFrame(fd)
        -- Ensure data structure consistency
        if fd.cframe and not fd.cfd then
            fd.cfd = {p=fd.cframe.position, lv=fd.cframe.lookVector, rv=fd.cframe.rightVector, uv=fd.cframe.upVector}
        end
        if not fd.t then fd.t = fd.time or 0 end
    end

    local function LoadFromURL(url)
        Rayfield:Notify("Loading", "Fetching from URL...", 5)
        task.spawn(function()
            local raw
            local ok = pcall(function()
                local res = request({ Url = url, Method = "GET" })
                raw = res.Body
            end)
            
            if not ok or not raw or raw == "" then
                Rayfield:Notify("Error", "Failed to fetch URL.")
                return
            end

            local dok, data = pcall(HttpService.JSONDecode, HttpService, raw)
            if not dok or type(data) ~= "table" or #data == 0 then
                Rayfield:Notify("Error", "Invalid JSON format.")
                return
            end

            for _, fd in ipairs(data) do NormalizeFrame(fd) end
            -- Reset time to start at 0 if offset is huge
            if #data > 1 and data[2].t - data[1].t > 10 then
                local t0 = data[1].t
                for _, fd in ipairs(data) do fd.t = fd.t - t0 end
            end

            State.repData = data
            Rayfield:Notify("Success", "Loaded " .. #data .. " frames from URL.")
        end)
    end

    local function ListFiles()
        if not State.HAS_IO then return {} end
        local files = {}
        pcall(function()
            EnsureFolder()
            for _, path in ipairs(listfiles(State.SAVE_FOLDER)) do
                if path:sub(-5) == ".json" then
                    local n = path:match("([^/\\]+)%.json$") or path
                    table.insert(files, {name = n, path = path})
                end
            end
        end)
        return files
    end

    local function LoadFromFile(path)
        if not State.HAS_IO then
            Rayfield:Notify("Error", "File IO not supported by executor.")
            return
        end
        local raw
        local ok = pcall(function() raw = readfile(path) end)
        if not ok or not raw then
            Rayfield:Notify("Error", "Read failed.")
            return
        end
        
        local dok, data = pcall(HttpService.JSONDecode, HttpService, raw)
        if not dok or type(data) ~= "table" or #data == 0 then
            Rayfield:Notify("Error", "Invalid file format.")
            return
        end
        
        for _, fd in ipairs(data) do NormalizeFrame(fd) end
        State.repData = data
        Rayfield:Notify("Loaded", "Loaded " .. #data .. " frames from file.")
    end

    local function MergeReplays(fileList)
        if #fileList < 1 then 
            Rayfield:Notify("Error", "Select files to merge.") 
            return 
        end
        
        local merged = {}
        local tOff = 0
        
        for _, path in ipairs(fileList) do
            local raw
            local ok = pcall(function() raw = readfile(path) end)
            if ok and raw then
                local dok, data = pcall(HttpService.JSONDecode, HttpService, raw)
                if dok and type(data) == "table" then
                    local t0 = data[1].t
                    local tEnd = data[#data].t - t0
                    for _, fd in ipairs(data) do
                        local fr = {}
                        for k, v in pairs(fd) do fr[k] = v end
                        fr.t = tOff + (fd.t - t0)
                        table.insert(merged, fr)
                    end
                    tOff = tOff + tEnd + 0.05 -- Small gap between replays
                end
            end
        end
        
        if #merged > 0 then
            State.repData = merged
            Rayfield:Notify("Merged", "Created " .. #merged .. " frame replay.")
        else
            Rayfield:Notify("Error", "Merge failed.")
        end
    end

    -- ==========================================
    -- RAYFIELD UI SETUP
    -- ==========================================
    
    local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

    local Window = Rayfield:CreateWindow({
        Name = "Hazel Path Player",
        LoadingTitle = "Hazel Path Suite",
        LoadingSubtitle = "by Hazel",
        ConfigurationSaving = {
            Enabled = false,
        },
        Discord = {
            Enabled = false,
        },
        KeySystem = false,
    })

    -- Main Tab
    local Tab = Window:CreateTab("Playback", 4483362458) -- Icon

    -- Section: Playback Controls
    local PlaySection = Tab:CreateSection("Playback Controls")

    local PlayButton = Tab:CreateButton({
        Name = "Play / Pause",
        Callback = function()
            PlayReplay()
        end,
    })

    local StopButton = Tab:CreateButton({
        Name = "Stop",
        Callback = function()
            StopReplay()
        end,
    })

    local LoopToggle = Tab:CreateToggle({
        Name = "Loop Replay",
        CurrentValue = false,
        Flag = "LoopToggle",
        Callback = function(Value)
            State.isLooping = Value
            Rayfield:Notify("Loop", Value and "Enabled" or "Disabled")
        end,
    })

    local SpeedSlider = Tab:CreateSlider({
        Name = "Playback Speed",
        Range = {0.1, 5.0},
        Increment = 0.1,
        Suffix = "x",
        CurrentValue = 1.0,
        Flag = "SpeedSlider",
        Callback = function(Value)
            State.repSpeed = Value
            -- Update base if playing to prevent jump
            if State.isPlaying and not State.isPaused then
                State.pbElapsed = State.elapsedAtBase + (tick() - State.wallBase) * (State.repSpeed) -- Approx fix
                -- Better: just update the multiplier used in heartbeat
            end
        end,
    })

    -- Section: Data Loading
    local LoadSection = Tab:CreateSection("Load Data")

    Tab:CreateInput({
        Name = "Load from URL (Pastebin)",
        PlaceholderText = "https://pastebin.com/raw/...",
        RemoveTextAfterFocusLost = false,
        Callback = function(Text)
            if Text ~= "" then
                LoadFromURL(Text)
            end
        end,
    })

    local FileDropdown
    local RefreshFiles = function()
        local files = ListFiles()
        local list = {}
        for _, f in ipairs(files) do table.insert(list, f.name) end
        
        if FileDropdown then
            FileDropdown:Refresh(list)
        end
    end

    FileDropdown = Tab:CreateDropdown({
        Name = "Local Files",
        Options = {},
        CurrentOption = "",
        MultipleOptions = false,
        Flag = "FileDropdown",
        Callback = function(Option)
            -- Find path
            local files = ListFiles()
            for _, f in ipairs(files) do
                if f.name == Option then
                    LoadFromFile(f.path)
                    break
                end
            end
        end,
    })

    Tab:CreateButton({
        Name = "Refresh File List",
        Callback = function()
            RefreshFiles()
            Rayfield:Notify("Refreshed", "File list updated.")
        end,
    })

    -- Section: Tools & Merge
    local ToolsSection = Tab:CreateSection("Tools & Merge")

    -- We need a multi-select for merge. Rayfield standard dropdown is single select.
    -- We will use a simple input to load filenames by name or just load multiple manually via logic?
    -- For simplicity in a UI wrapper, let's stick to "Load Last Merged" or implement a basic multi-select logic if possible.
    -- Since Rayfield free version doesn't have MultiSelect dropdown, let's create a custom "Merge Queue" logic or just simple "Load & Add to Queue" buttons.
    
    -- Actually, let's use the "Saved Replays" list logic similar to original but simpler.
    -- Let's just provide a button to "Merge Last Loaded" (accumulator) or simple logic.
    -- To be safe and functional: Let's provide a "Merge Mode" toggle. If on, loading a file ADDS to current data instead of replacing.

    local MergeModeToggle = Tab:CreateToggle({
        Name = "Merge Mode (Append)",
        CurrentValue = false,
        Flag = "MergeMode",
        Callback = function(Value)
            -- This is just a visual indicator for the user, logic handled in LoadFromFile modification below
        end,
    })

    -- Patch LoadFromFile to support Merge Mode
    local OriginalLoadFromFile = LoadFromFile
    LoadFromFile = function(path)
        local isMerge = Rayfield:Get("MergeMode", false)
        
        if not State.HAS_IO then Rayfield:Notify("Error", "IO not supported"); return end
        
        local raw; pcall(function() raw = readfile(path) end)
        if not raw then return end
        
        local ok, data = pcall(HttpService.JSONDecode, HttpService, raw)
        if not ok or type(data) ~= "table" then return end
        
        for _, fd in ipairs(data) do NormalizeFrame(fd) end

        if isMerge and State.repData and #State.repData > 0 then
            -- Perform Merge
            local tOff = State.repData[#State.repData].t
            local t0 = data[1].t
            for _, fd in ipairs(data) do
                local fr = {}
                for k, v in pairs(fd) do fr[k] = v end
                fr.t = tOff + (fd.t - t0)
                table.insert(State.repData, fr)
            end
            Rayfield:Notify("Merged", "Appended " .. #data .. " frames to current replay.")
        else
            -- Normal Load
            State.repData = data
            Rayfield:Notify("Loaded", "Loaded " .. #data .. " frames.")
        end
    end

    Tab:CreateButton({
        Name = "Clear Data",
        Callback = function()
            State.repData = nil
            Rayfield:Notify("Cleared", "Memory wiped.")
        end,
    })

    -- Section: Teleportation
    local TpSection = Tab:CreateSection("Teleportation")
    
    Tab:CreateButton({
        Name = "TP to Start",
        Callback = function()
            if not State.repData or #State.repData == 0 then return Rayfield:Notify("Error", "No data") end
            local fd = State.repData[1]
            if fd and fd.cfd then
                local cf = CfFromData(fd.cfd)
                RootPart.CFrame = cf
            end
        end,
    })

    Tab:CreateButton({
        Name = "TP to End",
        Callback = function()
            if not State.repData or #State.repData == 0 then return Rayfield:Notify("Error", "No data") end
            local fd = State.repData[#State.repData]
            if fd and fd.cfd then
                local cf = CfFromData(fd.cfd)
                RootPart.CFrame = cf
            end
        end,
    })

    -- Section: Loop Target
    local TargetSection = Tab:CreateSection("Loop Stop Target")

    local LsToggle = Tab:CreateToggle({
        Name = "Enable Loop Stop",
        CurrentValue = false,
        Flag = "LsToggle",
        Callback = function(Value)
            State.lsEnabled = Value
        end,
    })

    Tab:CreateInput({
        Name = "Stop at Summit Amount",
        PlaceholderText = "1000",
        RemoveTextAfterFocusLost = false,
        Callback = function(Text)
            local num = tonumber(Text)
            if num then
                State.lsTarget = num
                Rayfield:Notify("Target Set", "Will stop at " .. num .. " Summit.")
            end
        end,
    })

    -- Initialize
    RefreshFiles()
    Rayfield:Notify("Ready", "Hazel Path Player Loaded.")

end

-- Error Handling Wrapper
local success, err = pcall(runPlayer)
if not success then
    warn("Hazel Path Error: " .. tostring(err))
    game:GetService("StarterGui"):SetCore("SendNotification", {
        Title = "Error",
        Text = "Failed to load script: " .. tostring(err),
        Duration = 10
    })
end
