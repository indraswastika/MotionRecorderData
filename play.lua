-- Replay Player + Summit Tracker
-- UI: Fluent Renewed (ActualMasterOogway)

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local pl = Players.LocalPlayer
assert(pl, "LocalPlayer nil")

-- ============================================================
-- CORE STATE
-- ============================================================

local S = {
    char = nil, hum = nil, rp = nil, anim = nil,
    repData = nil, repConn = nil,
    isPlaying = false, isPausedPlay = false,
    isLooping = false, repSpeed = 1.0,
    wallBase = 0, elapsedAtBase = 0, pbElapsed = 0,
    realWallBase = 0, realElapsedBase = 0, realElapsed = 0,
    curFrame = 1, lastPlayFrame = 1,
    loopCount = 0, lastWipeFrame = 0,
    localPlayCopy = nil,
    activeRepTracks = {}, animMapB = {}, activeAnimSet = {},
    cfCache = {idxA=-1, idxB=-1, cfA=nil, cfB=nil},
    animPool = {}, animStatesBuf = {},
    ANIM_CACHE_MAX = 20,
    RAM_WIPE = 30,
    SAVE_FOLDER = "MTP_Replays",

    -- Summit tracker
    summitTarget  = 1000,
    initSummit    = 0,
    curSummit     = 0,
    summitInc     = 0,
    summitPPM     = 0,
    sessionStart  = tick(),
    lastSummitUpd = 0,

    -- Auto stop
    autoStop        = false,
    autoStopReached = false,
}

local HAS_IO = typeof(readfile) == "function" and typeof(writefile) == "function"

-- ============================================================
-- CHARACTER REFS
-- ============================================================

local function getFreshRefs()
    local c = pl.Character
    if not c then return nil, nil, nil end
    local r = c:FindFirstChild("HumanoidRootPart")
    local h = c:FindFirstChild("Humanoid")
    return r, h, h and h:FindFirstChild("Animator")
end

local function initChar(char)
    S.char = char
    S.hum  = char:WaitForChild("Humanoid", 10)
    S.rp   = char:WaitForChild("HumanoidRootPart", 10)
    S.anim = S.hum and S.hum:WaitForChild("Animator", 10)
end

initChar(pl.Character or pl.CharacterAdded:Wait())
pl.CharacterAdded:Connect(function(nc) initChar(nc) end)

-- ============================================================
-- UTILITY
-- ============================================================

local function forceGC()
    pcall(collectgarbage, "collect")
    pcall(collectgarbage, "collect")
end
local function deferGC() task.defer(forceGC) end

local notify = function(title, content, duration)
    -- dipatch setelah Library init
end

local function fmtTime(s)
    s = math.max(0, s or 0)
    local h = math.floor(s/3600)
    local m = math.floor((s%3600)/60)
    local sc = math.floor(s%60)
    return h > 0 and ("%02d:%02d:%02d"):format(h,m,sc) or ("%02d:%02d"):format(m,sc)
end

local function fmtTimeDec(s)
    s = math.max(0, s or 0)
    return ("%02d:%04.1f"):format(math.floor(s/60), s%60)
end

local function fmtDT(ts)
    local d = os.date("*t", ts)
    return ("%02d/%02d %02d:%02d"):format(d.day, d.month, d.hour, d.min)
end

-- ============================================================
-- CFRAME MATH
-- ============================================================

local function cfFromData(cfd)
    if not cfd then return CFrame.new() end
    local p,lv,rv,uv = cfd.p,cfd.lv,cfd.rv,cfd.uv
    if not (p and lv and rv and uv) then return CFrame.new() end
    return CFrame.fromMatrix(
        Vector3.new(p[1],p[2],p[3]),
        Vector3.new(rv[1],rv[2],rv[3]),
        Vector3.new(uv[1],uv[2],uv[3]),
        -Vector3.new(lv[1],lv[2],lv[3])
    )
end

local function cfToQuat(cf)
    local rx,ry,rz = cf.RightVector.X, cf.RightVector.Y, cf.RightVector.Z
    local ux,uy,uz = cf.UpVector.X,    cf.UpVector.Y,    cf.UpVector.Z
    local bx,by,bz = -cf.LookVector.X,-cf.LookVector.Y,-cf.LookVector.Z
    local tr = rx+uy+bz
    local w,x,y,z
    if tr > 0 then
        local s=0.5/math.sqrt(tr+1); w=0.25/s; x=(uz-by)*s; y=(bx-rz)*s; z=(ry-ux)*s
    elseif rx > uy and rx > bz then
        local s=2*math.sqrt(1+rx-uy-bz); w=(uz-by)/s; x=0.25*s; y=(uy+rx)/s; z=(bx+rz)/s
    elseif uy > bz then
        local s=2*math.sqrt(1+uy-rx-bz); w=(bx-rz)/s; x=(ux+ry)/s; y=0.25*s; z=(uz+by)/s
    else
        local s=2*math.sqrt(1+bz-rx-uy); w=(ry-ux)/s; x=(bx+rz)/s; y=(uz+by)/s; z=0.25*s
    end
    return {w=w,x=x,y=y,z=z}
end

local function quatSlerp(a,b,t)
    local dot=a.w*b.w+a.x*b.x+a.y*b.y+a.z*b.z
    if dot<0 then b={w=-b.w,x=-b.x,y=-b.y,z=-b.z}; dot=-dot end
    dot=math.clamp(dot,-1,1)
    local s0,s1
    if dot>0.9995 then s0=1-t; s1=t
    else local th=math.acos(dot); local sth=math.sin(th); s0=math.sin((1-t)*th)/sth; s1=math.sin(t*th)/sth end
    local r={w=s0*a.w+s1*b.w,x=s0*a.x+s1*b.x,y=s0*a.y+s1*b.y,z=s0*a.z+s1*b.z}
    local l=math.sqrt(r.w*r.w+r.x*r.x+r.y*r.y+r.z*r.z)
    if l<1e-6 then return a end
    return {w=r.w/l,x=r.x/l,y=r.y/l,z=r.z/l}
end

local function quatToCF(q,pos)
    local w,x,y,z=q.w,q.x,q.y,q.z
    local xx,yy,zz=x*x,y*y,z*z
    local xy,xz,yz=x*y,x*z,y*z
    local wx,wy,wz=w*x,w*y,w*z
    return CFrame.new(pos.X,pos.Y,pos.Z,
        1-2*(yy+zz),2*(xy-wz),2*(xz+wy),
        2*(xy+wz),1-2*(xx+zz),2*(yz-wx),
        2*(xz-wy),2*(yz+wx),1-2*(xx+yy))
end

local function lerpCF(a,b,t)
    return quatToCF(quatSlerp(cfToQuat(a),cfToQuat(b),t),a.Position:Lerp(b.Position,t))
end

-- ============================================================
-- REPLAY HELPERS
-- ============================================================

local function repDuration(d)
    if not d or #d<2 then return 0 end
    return d[#d].t - d[1].t
end

local function findFrame(d,targetT)
    if targetT<=d[1].t then return 1 end
    if targetT>=d[#d].t then return math.max(1,#d-1) end
    local lo,hi=1,#d-1
    while lo<hi do
        local mid=math.floor((lo+hi+1)/2)
        if d[mid].t<=targetT then lo=mid else hi=mid-1 end
    end
    return lo
end

local function makeLocalCopy(d)
    local c=table.create(#d)
    for i=1,#d do
        local s=d[i]
        c[i]={t=s.t,dt=s.dt,ws=s.ws,hs=s.hs,cfd=s.cfd,anims=s.anims,vel=s.vel}
    end
    return c
end

local function restoreLocalCopy(c,orig)
    for i=1,#orig do
        if c[i] then
            c[i].cfd=orig[i].cfd; c[i].anims=orig[i].anims
            c[i].vel=orig[i].vel; c[i].hs=orig[i].hs
        end
    end
end

-- ============================================================
-- ANIMATION
-- ============================================================

local priMap={
    Action4=Enum.AnimationPriority.Action4,Action3=Enum.AnimationPriority.Action3,
    Action2=Enum.AnimationPriority.Action2,Action=Enum.AnimationPriority.Action,
    Movement=Enum.AnimationPriority.Movement,Idle=Enum.AnimationPriority.Idle,
    Core=Enum.AnimationPriority.Core
}

local function getAnimInst(id)
    if S.animPool[id] then return S.animPool[id] end
    local a=Instance.new("Animation"); a.AnimationId=id; S.animPool[id]=a; return a
end

local function trimAnimCache()
    local n=0; for _ in pairs(S.activeRepTracks) do n=n+1 end
    if n>S.ANIM_CACHE_MAX then
        for id,tr in pairs(S.activeRepTracks) do
            if not tr.IsPlaying then S.activeRepTracks[id]=nil; return end
        end
    end
end

local function playAnimData(aA,aB,alpha)
    local tp=aA.tp
    if aB and alpha and alpha>0 then tp=aA.tp+(aB.tp-aA.tp)*alpha end
    local ex=S.activeRepTracks[aA.id]
    if ex and not ex.IsPlaying then S.activeRepTracks[aA.id]=nil; ex=nil end
    if ex then
        pcall(function() ex:AdjustSpeed(aA.sp*S.repSpeed) end)
        pcall(function() if math.abs(ex.TimePosition-tp)>0.15 then ex.TimePosition=tp end end)
        return
    end
    local anim=getAnimInst(aA.id)
    local _,_,useAnim=getFreshRefs(); useAnim=useAnim or S.anim
    if not useAnim then return end
    local ok,track=pcall(function() return useAnim:LoadAnimation(anim) end)
    if not ok or not track then return end
    local pri=Enum.AnimationPriority.Core
    for k,v in pairs(priMap) do if aA.pri:find(k) then pri=v; break end end
    pcall(function() track.Priority=pri; track:Play(0.05); track:AdjustSpeed(aA.sp*S.repSpeed); track.TimePosition=tp end)
    S.activeRepTracks[aA.id]=track; trimAnimCache()
end

local function stopStaleAnims(curAnims)
    for k in pairs(S.activeAnimSet) do S.activeAnimSet[k]=nil end
    for _,a in ipairs(curAnims) do S.activeAnimSet[a.id]=true end
    for id,tr in pairs(S.activeRepTracks) do
        if not S.activeAnimSet[id] then
            pcall(function() if tr.IsPlaying then tr:Stop(0.1) end end)
            S.activeRepTracks[id]=nil
        end
    end
end

local function clearAllAnims()
    for _,tr in pairs(S.activeRepTracks) do
        pcall(function() if tr and tr.IsPlaying then tr:Stop(0.05) end end)
    end
    S.activeRepTracks={}; task.defer(deferGC)
end

-- ============================================================
-- FILE IO
-- ============================================================

local function normalizeFrame(fd)
    if fd.cframe and not fd.cfd then
        fd.cfd={p=fd.cframe.position,lv=fd.cframe.lookVector,rv=fd.cframe.rightVector,uv=fd.cframe.upVector}
    end
    if fd.animations and not fd.anims then
        fd.anims={}
        for _,a in ipairs(fd.animations) do
            table.insert(fd.anims,{id=a.id,tp=a.timePosition or 0,sp=a.speed or 1,pri=a.priority or "Core"})
        end
    end
    if not fd.t  then fd.t  = fd.time or 0      end
    if not fd.ws then fd.ws = fd.walkSpeed or 16 end
    if not fd.dt then fd.dt = 1/60               end
end

local function loadFromFile(path)
    if not HAS_IO then notify("Error","File IO tidak tersedia"); return nil end
    local raw; local ok=pcall(function() raw=readfile(path) end)
    if not ok or not raw then notify("Error","Gagal baca: "..tostring(path)); return nil end
    local dok,data=pcall(HttpService.JSONDecode,HttpService,raw)
    if not dok or type(data)~="table" or #data==0 then notify("Error","Format tidak valid"); return nil end
    for _,fd in ipairs(data) do normalizeFrame(fd) end
    if #data>1 and data[2].t-data[1].t>10 then
        local t0=data[1].t; for _,fd in ipairs(data) do fd.t=fd.t-t0 end
    end
    return data
end

local function loadFromURL(url)
    local raw; local ok=pcall(function() local res=request({Url=url,Method="GET"}); raw=res.Body end)
    if not ok or not raw or raw=="" then notify("Error","Gagal ambil URL"); return nil end
    local dok,data=pcall(HttpService.JSONDecode,HttpService,raw)
    if not dok or type(data)~="table" or #data==0 then notify("Error","JSON tidak valid"); return nil end
    for _,fd in ipairs(data) do normalizeFrame(fd) end
    if #data>1 and data[2].t-data[1].t>10 then
        local t0=data[1].t; for _,fd in ipairs(data) do fd.t=fd.t-t0 end
    end
    return data
end

local function listFiles()
    if not HAS_IO then return {} end
    local files={}
    pcall(function()
        if not isfolder(S.SAVE_FOLDER) then makefolder(S.SAVE_FOLDER) end
        for _,path in ipairs(listfiles(S.SAVE_FOLDER)) do
            if path:sub(-5)==".json" then
                local n=path:match("([^/\\]+)%.json$") or path
                table.insert(files,{name=n,path=path})
            end
        end
    end)
    return files
end

-- ============================================================
-- SUMMIT TRACKER
-- ============================================================

local function getSummit()
    local ls=pl:FindFirstChild("leaderstats")
    if ls then
        for _,v in ipairs(ls:GetChildren()) do
            if v.Name:lower():find("summit") then return v.Value or 0 end
        end
    end
    for _,v in ipairs(pl:GetDescendants()) do
        if v.Name:lower():find("summit") and (v:IsA("IntValue") or v:IsA("NumberValue")) then
            return v.Value or 0
        end
    end
    return 0
end

S.initSummit = getSummit()
S.curSummit  = S.initSummit

-- Paragraph refs untuk update dashboard
local pSummitCur, pSummitInc, pSummitRate, pSummitLeft,
      pSummitPct, pSummitETA, pSummitDone, pLoopCount,
      pPlayStatus, pAutoStopStatus

local function updateDashboard()
    local now       = tick()
    local elapsed   = now - S.sessionStart
    S.curSummit     = getSummit()
    S.summitInc     = S.curSummit - S.initSummit
    S.summitPPM     = elapsed > 0 and (S.summitInc / elapsed) * 60 or 0

    local left   = math.max(0, S.summitTarget - S.curSummit)
    local pct    = math.min(100, math.floor(S.curSummit / math.max(1, S.summitTarget) * 100))
    local rate   = S.summitPPM
    if S.isPlaying and S.isLooping and S.repSpeed > 0 then
        rate = rate -- rate sudah real dari leaderstat
    end
    local etaStr, doneStr
    if rate > 0 and left > 0 then
        local etaSec = (left / rate) * 60
        etaStr  = fmtTime(etaSec)
        doneStr = fmtDT(now + etaSec)
    else
        etaStr  = S.curSummit >= S.summitTarget and "Tercapai!" or "---"
        doneStr = S.curSummit >= S.summitTarget and "Selesai" or "---"
    end

    pcall(function()
        if pSummitCur  then pSummitCur:SetValue(tostring(S.curSummit)) end
        if pSummitInc  then pSummitInc:SetValue("+"..S.summitInc) end
        if pSummitRate then pSummitRate:SetValue(("%.1f / menit"):format(S.summitPPM)) end
        if pSummitLeft then pSummitLeft:SetValue(tostring(left)) end
        if pSummitPct  then pSummitPct:SetValue(pct.."%") end
        if pSummitETA  then pSummitETA:SetValue(etaStr) end
        if pSummitDone then pSummitDone:SetValue(doneStr) end
        if pLoopCount  then pLoopCount:SetValue(tostring(S.loopCount)) end
        if pPlayStatus then
            local st = S.isPlaying and (S.isPausedPlay and "Dijeda" or "Berjalan") or "Berhenti"
            pPlayStatus:SetValue(st)
        end
        if pAutoStopStatus then
            if S.autoStop then
                pAutoStopStatus:SetValue("ON  (target: "..S.summitTarget..")")
            else
                pAutoStopStatus:SetValue("OFF")
            end
        end
    end)

    -- Auto stop check
    if S.autoStop and not S.autoStopReached and S.isPlaying and S.isLooping then
        if S.curSummit >= S.summitTarget then
            S.autoStopReached = true
            -- stopReplay dipanggil dari luar fungsi ini lewat flag
        end
    end
end

-- ============================================================
-- CALC
-- ============================================================

local function calcElapsed()     return S.elapsedAtBase + (tick()-S.wallBase)*S.repSpeed end
local function calcRealElapsed() return S.realElapsedBase + (tick()-S.realWallBase) end

local function setSpeed(val)
    if S.isPlaying and not S.isPausedPlay then
        S.pbElapsed   = calcElapsed()
        S.realElapsed = calcRealElapsed()
    end
    S.repSpeed = math.clamp(val, 0.1, 5.0)
    if S.isPlaying and not S.isPausedPlay then
        S.elapsedAtBase = S.pbElapsed
        S.wallBase      = tick()
    end
end

-- ============================================================
-- STOP REPLAY
-- ============================================================

local function stopReplay()
    if not S.isPlaying then return end
    S.isPlaying=false; S.isPausedPlay=false
    if S.repConn then S.repConn:Disconnect(); S.repConn=nil end
    clearAllAnims()
    if S.localPlayCopy then
        for i=1,#S.localPlayCopy do
            if S.localPlayCopy[i] then
                S.localPlayCopy[i].cfd=nil
                S.localPlayCopy[i].anims=nil
                S.localPlayCopy[i]=nil
            end
        end
        S.localPlayCopy=nil
    end
    S.cfCache={idxA=-1,idxB=-1,cfA=nil,cfB=nil}
    local _,hum=getFreshRefs(); hum=hum or S.hum
    pcall(function() if hum then hum.AutoRotate=true; hum.WalkSpeed=16 end end)
    forceGC(); deferGC()
    pcall(updateDashboard)
end

-- ============================================================
-- PLAY REPLAY
-- ============================================================

local function playReplay(data)
    local rd=data or S.repData
    if not rd or #rd==0 then notify("Error","Tidak ada data replay!"); return end

    if S.isPlaying and not S.isPausedPlay then
        S.isPausedPlay=true
        S.pbElapsed=calcElapsed(); S.realElapsed=calcRealElapsed()
        notify("Paused","Replay dijeda")
        pcall(updateDashboard)
        return
    elseif S.isPlaying and S.isPausedPlay then
        S.isPausedPlay=false
        S.elapsedAtBase=S.pbElapsed; S.wallBase=tick()
        S.realElapsedBase=S.realElapsed; S.realWallBase=tick()
        notify("Resumed","Replay dilanjutkan")
        pcall(updateDashboard)
        return
    end

    S.repData=rd; S.isPlaying=true; S.isPausedPlay=false
    S.curFrame=1; S.lastPlayFrame=1; S.loopCount=0
    S.pbElapsed=0; S.elapsedAtBase=0; S.wallBase=tick()
    S.realElapsed=0; S.realElapsedBase=0; S.realWallBase=tick()
    S.lastWipeFrame=0; S.autoStopReached=false
    S.cfCache={idxA=-1,idxB=-1,cfA=nil,cfB=nil}

    if S.localPlayCopy then
        for i=1,#S.localPlayCopy do S.localPlayCopy[i]=nil end
    end
    S.localPlayCopy=makeLocalCopy(rd)
    if S.repConn then S.repConn:Disconnect() end
    clearAllAnims()

    local _,hum0=getFreshRefs(); hum0=hum0 or S.hum
    pcall(function() if hum0 then hum0.AutoRotate=false; hum0.PlatformStand=false end end)

    local dur=repDuration(rd)
    local rdLen=#rd
    local lc=S.localPlayCopy
    local lastSetCF=nil
    local SMOOTH_ALPHA=0.35
    local playUICounter=0
    local dashCounter=0

    notify("Playing","Replay dimulai — "..rdLen.." frames")
    pcall(updateDashboard)

    S.repConn=RunService.Heartbeat:Connect(function(dt)
        if not S.isPlaying or S.isPausedPlay then return end

        -- Auto stop check
        if S.autoStopReached then
            local rt=fmtTimeDec(S.realElapsed)
            stopReplay()
            notify("Target Tercapai!","Summit "..S.summitTarget.." dicapai! Loop: "..S.loopCount.." | "..rt, 8)
            return
        end

        S.pbElapsed=calcElapsed()
        S.realElapsed=calcRealElapsed()

        -- Dashboard update setiap ~60 frame
        dashCounter=dashCounter+1
        if dashCounter>=60 then dashCounter=0; task.spawn(updateDashboard) end

        if S.pbElapsed>=dur then
            if S.isLooping then
                S.loopCount=S.loopCount+1
                S.pbElapsed=0; S.elapsedAtBase=0; S.wallBase=tick()
                S.curFrame=1; S.lastWipeFrame=0
                S.cfCache={idxA=-1,idxB=-1,cfA=nil,cfB=nil}
                lastSetCF=nil
                restoreLocalCopy(lc,rd)
                task.defer(function() pcall(collectgarbage,"collect") end)
                task.spawn(updateDashboard)
            else
                local rt=fmtTimeDec(S.realElapsed)
                stopReplay()
                notify("Selesai","Replay selesai | Loop: "..S.loopCount.." | Waktu: "..rt)
                return
            end
        end

        local targetT=rd[1].t+S.pbElapsed
        local fA=findFrame(rd,targetT)
        local fB=math.min(fA+1,rdLen)
        S.curFrame=fA; S.lastPlayFrame=fA

        if not S.isLooping and fA>S.lastWipeFrame+S.RAM_WIPE then
            local wt=fA-S.RAM_WIPE
            for i=S.lastWipeFrame+1,wt do
                if lc[i] then lc[i].cfd=nil; lc[i].anims=nil; lc[i].vel=nil; lc[i].hs=nil; lc[i]=nil end
            end
            S.lastWipeFrame=wt
        end

        local frmA=lc[fA]; local frmB=lc[fB]
        if not frmA or not frmA.cfd then return end

        local alpha=0
        if frmB and frmB.cfd then
            local span=frmB.t-frmA.t
            if span>0.0001 then alpha=math.clamp((targetT-frmA.t)/span,0,1) end
        end

        local cfA,cfB2
        if S.cfCache.idxA==fA then cfA=S.cfCache.cfA
        else cfA=cfFromData(frmA.cfd); S.cfCache.idxA=fA; S.cfCache.cfA=cfA end

        local targetCF
        if frmB and frmB.cfd then
            if S.cfCache.idxB==fB then cfB2=S.cfCache.cfB
            else cfB2=cfFromData(frmB.cfd); S.cfCache.idxB=fB; S.cfCache.cfB=cfB2 end
            targetCF=lerpCF(cfA,cfB2,alpha)
        else targetCF=cfA end

        local smoothFactor=math.clamp(1-math.pow(1-SMOOTH_ALPHA,dt*60),0,1)
        local finalCF
        if lastSetCF then
            local smoothPos=lastSetCF.Position:Lerp(targetCF.Position,smoothFactor)
            local smoothRot=lerpCF(lastSetCF-lastSetCF.Position,targetCF-targetCF.Position,smoothFactor)
            finalCF=CFrame.new(smoothPos)*(smoothRot-smoothRot.Position)
        else finalCF=targetCF end
        lastSetCF=finalCF

        local r2,hum2=getFreshRefs(); r2=r2 or S.rp; hum2=hum2 or S.hum
        pcall(function()
            if r2 then r2.CFrame=finalCF end
            if hum2 and frmB and frmB.cfd then
                local wsA=frmA.ws or 16; local wsB=frmB.ws or 16
                hum2.WalkSpeed=wsA+(wsB-wsA)*alpha
            end
        end)

        if frmA.anims and #frmA.anims>0 then
            for k in pairs(S.animMapB) do S.animMapB[k]=nil end
            if frmB and frmB.anims then
                for _,ab in ipairs(frmB.anims) do S.animMapB[ab.id]=ab end
            end
            for _,ad in ipairs(frmA.anims) do pcall(playAnimData,ad,S.animMapB[ad.id],alpha) end
            playUICounter=playUICounter+1
            if playUICounter%3==0 then pcall(stopStaleAnims,frmA.anims) end
        else
            if next(S.activeRepTracks)~=nil then clearAllAnims() end
        end
    end)
end

-- ============================================================
-- FLUENT RENEWED UI
-- ============================================================

local Library        = loadstring(game:HttpGetAsync("https://github.com/ActualMasterOogway/Fluent-Renewed/releases/latest/download/Fluent.luau"))()
local SaveManager    = loadstring(game:HttpGetAsync("https://raw.githubusercontent.com/ActualMasterOogway/Fluent-Renewed/master/Addons/SaveManager.luau"))()
local InterfaceManager = loadstring(game:HttpGetAsync("https://raw.githubusercontent.com/ActualMasterOogway/Fluent-Renewed/master/Addons/InterfaceManager.luau"))()

notify = function(title, content, duration)
    Library:Notify{
        Title    = title,
        Content  = content,
        Duration = duration or 4
    }
end

local Window = Library:CreateWindow{
    Title       = "Replay Player",
    SubTitle    = "MTP System",
    TabWidth    = 160,
    Size        = UDim2.fromOffset(830, 525),
    Resize      = true,
    MinSize     = Vector2.new(470, 380),
    Acrylic     = true,
    Theme       = "Dark",
    MinimizeKey = Enum.KeyCode.RightControl
}

local Tabs = {
    Dashboard = Window:CreateTab{ Title = "Dashboard", Icon = "activity"          },
    Playback  = Window:CreateTab{ Title = "Playback",  Icon = "play-circle"       },
    Files     = Window:CreateTab{ Title = "Files",     Icon = "folder-open"       },
    Settings  = Window:CreateTab{ Title = "Settings",  Icon = "settings"          },
}

local Options = Library.Options

-- ============================================================
-- TAB: DASHBOARD
-- ============================================================

Tabs.Dashboard:CreateParagraph("DashTitle",{
    Title   = "Info Sesi",
    Content = "Data diperbarui otomatis setiap loop dan setiap detik."
})

pPlayStatus = Tabs.Dashboard:CreateParagraph("DashPlayStatus",{
    Title   = "Status Replay",
    Content = "Berhenti"
})

pLoopCount = Tabs.Dashboard:CreateParagraph("DashLoop",{
    Title   = "Jumlah Loop",
    Content = "0"
})

Tabs.Dashboard:CreateParagraph("DashSummitHeader",{
    Title   = "Summit",
    Content = "---"
})

pSummitCur = Tabs.Dashboard:CreateParagraph("DashSummitCur",{
    Title   = "Summit Sekarang",
    Content = tostring(S.initSummit)
})

pSummitInc = Tabs.Dashboard:CreateParagraph("DashSummitInc",{
    Title   = "Kenaikan (sesi ini)",
    Content = "+0"
})

pSummitRate = Tabs.Dashboard:CreateParagraph("DashSummitRate",{
    Title   = "Laju",
    Content = "0.0 / menit"
})

pSummitLeft = Tabs.Dashboard:CreateParagraph("DashSummitLeft",{
    Title   = "Sisa Menuju Target",
    Content = tostring(S.summitTarget)
})

pSummitPct = Tabs.Dashboard:CreateParagraph("DashSummitPct",{
    Title   = "Persentase",
    Content = "0%"
})

pSummitETA = Tabs.Dashboard:CreateParagraph("DashSummitETA",{
    Title   = "Estimasi Waktu (ETA)",
    Content = "---"
})

pSummitDone = Tabs.Dashboard:CreateParagraph("DashSummitDone",{
    Title   = "Perkiraan Selesai",
    Content = "---"
})

pAutoStopStatus = Tabs.Dashboard:CreateParagraph("DashAutoStop",{
    Title   = "Auto Stop",
    Content = "OFF"
})

Tabs.Dashboard:CreateButton{
    Title       = "Refresh Dashboard",
    Description = "Perbarui semua data sekarang",
    Callback    = function()
        pcall(updateDashboard)
        notify("Dashboard","Data diperbarui")
    end
}

Tabs.Dashboard:CreateButton{
    Title       = "Reset Sesi",
    Description = "Reset data kenaikan summit sesi ini",
    Callback    = function()
        S.initSummit  = getSummit()
        S.curSummit   = S.initSummit
        S.summitInc   = 0
        S.loopCount   = 0
        S.summitPPM   = 0
        S.sessionStart = tick()
        S.autoStopReached = false
        pcall(updateDashboard)
        notify("Reset","Sesi summit direset")
    end
}

-- ============================================================
-- TAB: PLAYBACK
-- ============================================================

Tabs.Playback:CreateParagraph("PlayInfo",{
    Title   = "Kontrol Replay",
    Content = "Gunakan tombol di bawah untuk mengontrol replay."
})

-- Play / Pause
Tabs.Playback:CreateButton{
    Title       = "Play / Pause",
    Description = "Mulai atau jeda replay yang aktif",
    Callback    = function()
        if S.repData then playReplay()
        else notify("Error","Load replay terlebih dahulu!") end
    end
}

-- Stop
Tabs.Playback:CreateButton{
    Title       = "Stop",
    Description = "Hentikan replay dan kembalikan kontrol karakter",
    Callback    = function()
        stopReplay()
        notify("Stopped","Replay dihentikan")
    end
}

-- Loop
local LoopToggle = Tabs.Playback:CreateToggle("LoopToggle",{
    Title       = "Loop",
    Description = "Ulangi replay secara otomatis saat selesai",
    Default     = false
})
LoopToggle:OnChanged(function()
    S.isLooping = Options.LoopToggle.Value
    notify("Loop", S.isLooping and "Loop ON" or "Loop OFF")
    pcall(updateDashboard)
end)

-- Auto Stop
local AutoStopToggle = Tabs.Playback:CreateToggle("AutoStopToggle",{
    Title       = "Auto Stop saat Target Tercapai",
    Description = "Hentikan loop otomatis saat summit mencapai target",
    Default     = false
})
AutoStopToggle:OnChanged(function()
    S.autoStop        = Options.AutoStopToggle.Value
    S.autoStopReached = false
    notify("Auto Stop", S.autoStop and "ON" or "OFF")
    pcall(updateDashboard)
end)

-- Target summit input
local TargetInput = Tabs.Playback:CreateInput("TargetInput",{
    Title       = "Target Summit",
    Description = "Angka summit yang ingin dicapai",
    Default     = "1000",
    Placeholder = "contoh: 5000",
    Numeric     = true,
    Finished    = true,
    Callback    = function(value)
        local n = tonumber(value)
        if n and n > 0 then
            S.summitTarget    = n
            S.autoStopReached = false
            notify("Target","Target summit diset ke "..n)
            pcall(updateDashboard)
        else
            notify("Error","Masukkan angka yang valid!")
        end
    end
})

-- Speed slider
local SpeedSlider = Tabs.Playback:CreateSlider("SpeedSlider",{
    Title       = "Kecepatan Replay",
    Description = "0.1x hingga 5.0x",
    Default     = 1.0,
    Min         = 0.1,
    Max         = 5.0,
    Rounding    = 2,
    Callback    = function(value)
        setSpeed(value)
    end
})

-- TP frame pertama
Tabs.Playback:CreateButton{
    Title       = "Teleport ke Frame Pertama",
    Description = "Pindahkan karakter ke posisi awal replay",
    Callback    = function()
        if not S.repData or #S.repData==0 then notify("Error","Tidak ada data"); return end
        local fd=S.repData[1]
        if fd and fd.cfd then
            local ok,cf=pcall(cfFromData,fd.cfd)
            if ok then
                local rp=getFreshRefs(); rp=rp or S.rp
                pcall(function() if rp then rp.CFrame=cf end end)
                notify("Teleport","Frame pertama")
            end
        end
    end
}

-- TP frame terakhir
Tabs.Playback:CreateButton{
    Title       = "Teleport ke Frame Terakhir",
    Description = "Pindahkan karakter ke posisi akhir replay",
    Callback    = function()
        if not S.repData or #S.repData==0 then notify("Error","Tidak ada data"); return end
        local fd=S.repData[#S.repData]
        if fd and fd.cfd then
            local ok,cf=pcall(cfFromData,fd.cfd)
            if ok then
                local rp=getFreshRefs(); rp=rp or S.rp
                pcall(function() if rp then rp.CFrame=cf end end)
                notify("Teleport","Frame terakhir")
            end
        end
    end
}

-- Keybind play/pause
local PlayKeybind = Tabs.Playback:CreateKeybind("PlayKeybind",{
    Title   = "Keybind Play / Pause",
    Mode    = "Always",
    Default = "F5",
    Callback = function()
        if S.repData then playReplay() end
    end
})

-- Keybind stop
local StopKeybind = Tabs.Playback:CreateKeybind("StopKeybind",{
    Title   = "Keybind Stop",
    Mode    = "Always",
    Default = "F6",
    Callback = function()
        stopReplay()
    end
})

-- ============================================================
-- TAB: FILES
-- ============================================================

Tabs.Files:CreateParagraph("FilesInfo",{
    Title   = "Load Replay",
    Content = "Load file dari folder lokal ("..S.SAVE_FOLDER..") atau dari URL."
})

-- Input nama file
local FileInput = Tabs.Files:CreateInput("FileInput",{
    Title       = "Nama File Lokal",
    Description = "Tanpa ekstensi .json",
    Default     = "",
    Placeholder = "contoh: Replay_1",
    Numeric     = false,
    Finished    = false,
    Callback    = function(value) end
})

-- Load file
Tabs.Files:CreateButton{
    Title       = "Load File Lokal",
    Description = "Muat dari folder "..S.SAVE_FOLDER,
    Callback    = function()
        local name=Options.FileInput.Value
        if not name or name=="" then notify("Error","Masukkan nama file!"); return end
        local d=loadFromFile(S.SAVE_FOLDER.."/"..name..".json")
        if d then
            S.repData=d
            notify("Loaded",name.." — "..#d.." frames")
        end
    end
}

-- Tampilkan daftar
Tabs.Files:CreateButton{
    Title       = "Tampilkan Daftar File",
    Description = "Lihat semua file replay tersimpan",
    Callback    = function()
        local files=listFiles()
        if #files==0 then notify("Files","Tidak ada file di "..S.SAVE_FOLDER,5); return end
        local names={}
        for i,f in ipairs(files) do table.insert(names,i..". "..f.name) end
        notify("Files ("..#files..")", table.concat(names,"\n"), 10)
    end
}

-- URL input
local URLInput = Tabs.Files:CreateInput("URLInput",{
    Title       = "URL Replay",
    Description = "URL raw JSON (pastebin, dsb)",
    Default     = "",
    Placeholder = "https://pastebin.com/raw/...",
    Numeric     = false,
    Finished    = false,
    Callback    = function(value) end
})

-- Load URL
Tabs.Files:CreateButton{
    Title       = "Load dari URL",
    Description = "Ambil dan muat replay dari internet",
    Callback    = function()
        local url=Options.URLInput.Value
        if not url or url=="" then notify("Error","Masukkan URL!"); return end
        notify("Loading","Mengambil data dari URL...")
        task.spawn(function()
            local d=loadFromURL(url)
            if d then
                S.repData=d
                notify("Loaded","URL berhasil — "..#d.." frames")
                pcall(updateDashboard)
            end
        end)
    end
}

-- ============================================================
-- TAB: SETTINGS
-- ============================================================

SaveManager:SetLibrary(Library)
InterfaceManager:SetLibrary(Library)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes{}
InterfaceManager:SetFolder("ReplayPlayer")
SaveManager:SetFolder("ReplayPlayer/config")
InterfaceManager:BuildInterfaceSection(Tabs.Settings)
SaveManager:BuildConfigSection(Tabs.Settings)

-- ============================================================
-- BACKGROUND UPDATE LOOP
-- ============================================================

task.spawn(function()
    while true do
        task.wait(3)
        if not Library.Unloaded then
            pcall(updateDashboard)
        else
            breakz
        end
    end
end)

-- ============================================================
-- SELESAI
-- ============================================================

Window:SelectTab(1)

Library:Notify{
    Title    = "Replay Player",
    Content  = "Script berhasil dimuat. Buka tab Files untuk load replay.",
    Duration = 6
}

SaveManager:LoadAutoloadConfig()
