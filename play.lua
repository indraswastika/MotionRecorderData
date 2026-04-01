local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local Window = Rayfield:CreateWindow({
    Name = "HAZEL PATH - Playback Only",
    LoadingTitle = "HAZEL PATH",
    LoadingSubtitle = "Full Animation Fixed",
    ConfigurationSaving = { Enabled = false },
})

local PL = game:GetService("Players")
local RS = game:GetService("RunService")
local HS = game:GetService("HttpService")
local pl = PL.LocalPlayer

local S = {
    char = nil, hum = nil, rp = nil, anim = nil,
    repData = nil, repConn = nil,
    isPlaying = false, isPausedPlay = false,
    isLooping = false, repSpeed = 1.0,
    wallBase = 0, elapsedAtBase = 0, pbElapsed = 0,
    curFrame = 1, loopCount = 0,
    localPlayCopy = nil,
    cfCache = {idxA = -1, idxB = -1, cfA = nil, cfB = nil},
    animPool = {},
    activeRepTracks = {},
    animMapB = {},
    activeAnimSet = {},
    animStatesBuf = {},
}

local function getFreshRefs()
    local c = pl.Character
    if not c then return nil, nil, nil end
    local r = c:FindFirstChild("HumanoidRootPart")
    local h = c:FindFirstChild("Humanoid")
    return r, h, h and h:FindFirstChild("Animator")
end

local char = pl.Character or pl.CharacterAdded:Wait()
S.char = char
S.hum = char:WaitForChild("Humanoid", 10)
S.rp = char:WaitForChild("HumanoidRootPart", 10)
S.anim = S.hum and S.hum:WaitForChild("Animator", 10)

pl.CharacterAdded:Connect(function(nc)
    S.char = nc
    S.hum = nc:WaitForChild("Humanoid", 10)
    S.rp = nc:WaitForChild("HumanoidRootPart", 10)
    S.anim = S.hum and S.hum:WaitForChild("Animator", 10)
end)

local function notify(title, content)
    Rayfield:Notify({Title = title, Content = content, Duration = 6})
end

local function cfFromData(cfd)
    if not cfd then return CFrame.new() end
    local p = Vector3.new(cfd.p[1], cfd.p[2], cfd.p[3])
    local lv = Vector3.new(cfd.lv[1], cfd.lv[2], cfd.lv[3])
    local rv = Vector3.new(cfd.rv[1], cfd.rv[2], cfd.rv[3])
    local uv = Vector3.new(cfd.uv[1], cfd.uv[2], cfd.uv[3])
    return CFrame.fromMatrix(p, rv, uv, -lv)
end

local function cfToQuat(cf)
    local rx,ry,rz = cf.RightVector.X, cf.RightVector.Y, cf.RightVector.Z
    local ux,uy,uz = cf.UpVector.X, cf.UpVector.Y, cf.UpVector.Z
    local bx,by,bz = -cf.LookVector.X, -cf.LookVector.Y, -cf.LookVector.Z
    local tr = rx + uy + bz
    local w,x,y,z
    if tr > 0 then
        local s = 0.5 / math.sqrt(tr + 1)
        w = 0.25 / s; x = (uz-by)*s; y = (bx-rz)*s; z = (ry-ux)*s
    elseif rx > uy and rx > bz then
        local s = 2*math.sqrt(1+rx-uy-bz)
        w = (uz-by)/s; x = 0.25*s; y = (uy+rx)/s; z = (bx+rz)/s
    elseif uy > bz then
        local s = 2*math.sqrt(1+uy-rx-bz)
        w = (bx-rz)/s; x = (ux+ry)/s; y = 0.25*s; z = (uz+by)/s
    else
        local s = 2*math.sqrt(1+bz-rx-uy)
        w = (ry-ux)/s; x = (bx+rz)/s; y = (uz+by)/s; z = 0.25*s
    end
    return {w=w,x=x,y=y,z=z}
end

local function quatSlerp(a,b,t)
    local dot = a.w*b.w + a.x*b.x + a.y*b.y + a.z*b.z
    if dot < 0 then b = {w=-b.w,x=-b.x,y=-b.y,z=-b.z}; dot = -dot end
    dot = math.clamp(dot,-1,1)
    local s0,s1
    if dot > 0.9995 then s0,s1 = 1-t,t
    else
        local th = math.acos(dot)
        local sth = math.sin(th)
        s0 = math.sin((1-t)*th)/sth
        s1 = math.sin(t*th)/sth
    end
    local r = {w=s0*a.w+s1*b.w, x=s0*a.x+s1*b.x, y=s0*a.y+s1*b.y, z=s0*a.z+s1*b.z}
    local l = math.sqrt(r.w*r.w + r.x*r.x + r.y*r.y + r.z*r.z)
    if l < 1e-6 then return a end
    return {w=r.w/l, x=r.x/l, y=r.y/l, z=r.z/l}
end

local function quatToCF(q, pos)
    local w,x,y,z = q.w,q.x,q.y,q.z
    local xx,yy,zz = x*x,y*y,z*z
    local xy,xz,yz = x*y,x*z,y*z
    local wx,wy,wz = w*x,w*y,w*z
    return CFrame.new(pos.X,pos.Y,pos.Z,
        1-2*(yy+zz), 2*(xy-wz), 2*(xz+wy),
        2*(xy+wz), 1-2*(xx+zz), 2*(yz-wx),
        2*(xz-wy), 2*(yz+wx), 1-2*(xx+yy))
end

local function lerpCF(a,b,t)
    return quatToCF(quatSlerp(cfToQuat(a), cfToQuat(b), t), a.Position:Lerp(b.Position, t))
end

local function tpTo(cf)
    pcall(function()
        local r = getFreshRefs()
        if r and r[1] then r[1].CFrame = cf elseif S.rp then S.rp.CFrame = cf end
    end)
end

local function calcElapsed()
    return S.elapsedAtBase + (tick() - S.wallBase) * S.repSpeed
end

local priMap = {
    Action4 = Enum.AnimationPriority.Action4,
    Action3 = Enum.AnimationPriority.Action3,
    Action2 = Enum.AnimationPriority.Action2,
    Action = Enum.AnimationPriority.Action,
    Movement = Enum.AnimationPriority.Movement,
    Idle = Enum.AnimationPriority.Idle,
    Core = Enum.AnimationPriority.Core
}

local function getAnimInst(id)
    if S.animPool[id] then return S.animPool[id] end
    local a = Instance.new("Animation")
    a.AnimationId = id
    S.animPool[id] = a
    return a
end

local function playAnimData(aA, aB, alpha)
    local tp = aA.tp
    if aB and alpha and alpha > 0 then
        tp = aA.tp + (aB.tp - aA.tp) * alpha
    end
    local ex = S.activeRepTracks[aA.id]
    if ex and not ex.IsPlaying then S.activeRepTracks[aA.id] = nil; ex = nil end
    if ex then
        pcall(function() ex:AdjustSpeed(aA.sp * S.repSpeed) end)
        pcall(function() if math.abs(ex.TimePosition - tp) > 0.15 then ex.TimePosition = tp end end)
        return
    end
    local anim = getAnimInst(aA.id)
    local _, _, useAnim = getFreshRefs()
    useAnim = useAnim or S.anim
    if not useAnim then return end
    local ok, track = pcall(function() return useAnim:LoadAnimation(anim) end)
    if not ok or not track then return end
    local pri = Enum.AnimationPriority.Core
    for k,v in pairs(priMap) do
        if aA.pri:find(k) then pri = v; break end
    end
    pcall(function()
        track.Priority = pri
        track:Play(0.05)
        track:AdjustSpeed(aA.sp * S.repSpeed)
        track.TimePosition = tp
    end)
    S.activeRepTracks[aA.id] = track
end

local function stopStaleAnims(curAnims)
    for k in pairs(S.activeAnimSet) do S.activeAnimSet[k] = nil end
    for _,a in ipairs(curAnims) do S.activeAnimSet[a.id] = true end
    for id,tr in pairs(S.activeRepTracks) do
        if not S.activeAnimSet[id] then
            pcall(function() if tr.IsPlaying then tr:Stop(0.1) end end)
            S.activeRepTracks[id] = nil
        end
    end
end

local function clearAllAnims()
    for _,tr in pairs(S.activeRepTracks) do
        pcall(function() if tr.IsPlaying then tr:Stop(0.05) end end)
    end
    S.activeRepTracks = {}
end

local function repDuration(d)
    if not d or #d < 2 then return 0 end
    return d[#d].t - d[1].t
end

local function findFrame(d, targetT)
    if targetT <= d[1].t then return 1 end
    if targetT >= d[#d].t then return math.max(1,#d-1) end
    local lo,hi = 1,#d-1
    while lo < hi do
        local mid = math.floor((lo+hi+1)/2)
        if d[mid].t <= targetT then lo = mid else hi = mid-1 end
    end
    return lo
end

local function makeLocalCopy(d)
    local c = table.create(#d)
    for i=1,#d do
        local s = d[i]
        c[i] = {t = s.t, ws = s.ws or 16, cfd = s.cfd, anims = s.anims}
    end
    return c
end

local function stopReplay()
    if not S.isPlaying then return end
    S.isPlaying = false
    S.isPausedPlay = false
    if S.repConn then S.repConn:Disconnect() S.repConn = nil end
    clearAllAnims()
    S.localPlayCopy = nil
    S.cfCache.idxA = -1
    S.cfCache.idxB = -1
    local _, hum = getFreshRefs()
    if hum then hum.AutoRotate = true; hum.WalkSpeed = 16 end
    notify("Stopped", "Playback dihentikan")
end

local function playReplay(data)
    local rd = data or S.repData
    if not rd or #rd == 0 then notify("Error", "No replay data!"); return end
    if S.isPlaying and not S.isPausedPlay then
        S.isPausedPlay = true
        S.pbElapsed = calcElapsed()
        notify("Paused", "Playback dijeda")
        return
    elseif S.isPlaying and S.isPausedPlay then
        S.isPausedPlay = false
        S.elapsedAtBase = S.pbElapsed
        S.wallBase = tick()
        notify("Resumed", "Playback dilanjutkan")
        return
    end
    S.repData = rd
    S.isPlaying = true
    S.isPausedPlay = false
    S.curFrame = 1
    S.loopCount = 0
    S.wallBase = tick()
    S.elapsedAtBase = 0
    if S.repConn then S.repConn:Disconnect() end
    clearAllAnims()
    local _, hum0 = getFreshRefs()
    if hum0 then
        hum0.AutoRotate = false
        hum0.PlatformStand = false
    end
    local dur = repDuration(rd)
    local rdLen = #rd
    local lc = makeLocalCopy(rd)
    S.localPlayCopy = lc
    local lastSetCF = nil
    local SMOOTH_ALPHA = 0.35
    S.repConn = RS.Heartbeat:Connect(function(dt)
        if not S.isPlaying or S.isPausedPlay then return end
        S.pbElapsed = calcElapsed()
        if S.pbElapsed >= dur then
            if S.isLooping then
                S.loopCount += 1
                S.wallBase = tick()
                S.elapsedAtBase = 0
                lastSetCF = nil
                lc = makeLocalCopy(rd)
                S.localPlayCopy = lc
            else
                stopReplay()
                return
            end
        end
        local targetT = rd[1].t + S.pbElapsed
        local fA = findFrame(rd, targetT)
        local fB = math.min(fA + 1, rdLen)
        local frmA = lc[fA]
        local frmB = lc[fB]
        if not frmA or not frmA.cfd then return end
        local alpha = 0
        if frmB and frmB.cfd and frmB.t > frmA.t then
            alpha = math.clamp((targetT - frmA.t) / (frmB.t - frmA.t), 0, 1)
        end
        local cfA = (S.cfCache.idxA == fA and S.cfCache.cfA) or cfFromData(frmA.cfd)
        S.cfCache.idxA = fA; S.cfCache.cfA = cfA
        local targetCF = cfA
        if frmB and frmB.cfd then
            local cfB2 = (S.cfCache.idxB == fB and S.cfCache.cfB) or cfFromData(frmB.cfd)
            S.cfCache.idxB = fB; S.cfCache.cfB = cfB2
            targetCF = lerpCF(cfA, cfB2, alpha)
        end
        local smoothFactor = math.clamp(1 - math.pow(1 - SMOOTH_ALPHA, dt * 60), 0, 1)
        local finalCF
        if lastSetCF then
            local smoothPos = lastSetCF.Position:Lerp(targetCF.Position, smoothFactor)
            local smoothRot = lerpCF(lastSetCF - lastSetCF.Position, targetCF - targetCF.Position, smoothFactor)
            finalCF = CFrame.new(smoothPos) * (smoothRot - smoothRot.Position)
        else
            finalCF = targetCF
        end
        lastSetCF = finalCF
        local r2, hum2 = getFreshRefs()
        if r2 then r2.CFrame = finalCF end
        if hum2 and frmB then
            local wsA = frmA.ws or 16
            local wsB = frmB.ws or 16
            hum2.WalkSpeed = wsA + (wsB - wsA) * alpha
        end
        if frmA.anims and #frmA.anims > 0 then
            for k in pairs(S.animMapB) do S.animMapB[k] = nil end
            if frmB and frmB.anims then
                for _, ab in ipairs(frmB.anims) do S.animMapB[ab.id] = ab end
            end
            for _, ad in ipairs(frmA.anims) do
                pcall(playAnimData, ad, S.animMapB[ad.id], alpha)
            end
            stopStaleAnims(frmA.anims)
        else
            if next(S.activeRepTracks) then clearAllAnims() end
        end
    end)
end

local function loadVictoriaData()
    local url = "https://raw.githubusercontent.com/indraswastika/MotionRecorderData/refs/heads/main/VICTORIA%20V2.json"
    notify("Loading", "Mengambil VICTORIA V2 Data...")
    task.spawn(function()
        local success, response = pcall(function()
            return request({Url = url, Method = "GET"})
        end)
        if not success or not response or not response.Body then
            notify("Error", "Gagal mengambil VICTORIA DATA")
            return
        end
        local success2, data = pcall(HS.JSONDecode, HS, response.Body)
        if not success2 or type(data) ~= "table" or #data == 0 then
            notify("Error", "JSON VICTORIA tidak valid")
            return
        end
        S.repData = data
        notify("Success", "VICTORIA V2 berhasil dimuat!\nFrames: " .. #data .. "\nTekan PLAY")
    end)
end

local PlayTab = Window:CreateTab("🎮 Playback", 4483362458)

PlayTab:CreateButton({Name = "▶ PLAY / PAUSE", Callback = function() playReplay() end})
PlayTab:CreateButton({Name = "⏹ STOP", Callback = stopReplay})
PlayTab:CreateToggle({Name = "⟳ Loop Mode", CurrentValue = false, Callback = function(v) S.isLooping = v end})
PlayTab:CreateSlider({Name = "Speed", Range = {0.1, 5}, Increment = 0.1, CurrentValue = 1, Callback = function(v) S.repSpeed = v end})

PlayTab:CreateInput({Name = "Load from URL (Manual)", PlaceholderText = "https://pastebin.com/raw/....", Callback = function(url)
    if url == "" then return end
    task.spawn(function()
        local success, response = pcall(function() return request({Url = url, Method = "GET"}) end)
        if not success or not response.Body then notify("Error", "Gagal load URL"); return end
        local ok, data = pcall(HS.JSONDecode, HS, response.Body)
        if not ok or type(data) ~= "table" then notify("Error", "JSON tidak valid"); return end
        S.repData = data
        notify("Loaded", "Replay dari URL dimuat (" .. #data .. " frames)")
    end)
end})

PlayTab:CreateButton({Name = "🎀 Load VICTORIA DATA (V2)", Callback = loadVictoriaData})

PlayTab:CreateButton({Name = "TP ke Start", Callback = function()
    if S.repData and S.repData[1] and S.repData[1].cfd then
        tpTo(cfFromData(S.repData[1].cfd))
    end
end})

Rayfield:Notify({Title = "HAZEL PATH", Content = "Script siap!\nTekan 'Load VICTORIA DATA' untuk memuat replay.", Duration = 8})
