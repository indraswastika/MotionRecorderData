;(function()
local PL  = game:GetService("Players")
local RS  = game:GetService("RunService")
local HS  = game:GetService("HttpService")
local SG  = game:GetService("StarterGui")
local UIS = game:GetService("UserInputService")
local TS  = game:GetService("TweenService")
local pl  = PL.LocalPlayer
assert(pl,"LocalPlayer nil")

local C={
    bg1=Color3.fromRGB(8,8,10),
    bg2=Color3.fromRGB(12,12,16),
    bg3=Color3.fromRGB(17,17,22),
    bg4=Color3.fromRGB(22,22,28),
    bg5=Color3.fromRGB(28,28,36),
    border=Color3.fromRGB(38,38,50),
    borderHi=Color3.fromRGB(60,60,80),
    a1=Color3.fromRGB(220,220,255),
    a2=Color3.fromRGB(140,140,200),
    a3=Color3.fromRGB(255,80,80),
    a4=Color3.fromRGB(80,200,120),
    a5=Color3.fromRGB(200,160,60),
    a6=Color3.fromRGB(100,120,255),
    t1=Color3.fromRGB(240,240,255),
    t2=Color3.fromRGB(160,160,190),
    t3=Color3.fromRGB(80,80,110),
    tb=Color3.fromRGB(6,6,8),
    dR=Color3.fromRGB(140,30,30),
    dG=Color3.fromRGB(25,90,50),
    dB=Color3.fromRGB(30,55,140),
    dP=Color3.fromRGB(65,35,130),
    dA=Color3.fromRGB(130,85,0),
}

local S={
    char=nil, hum=nil, rp=nil, anim=nil,
    isRec=false, isPausedRec=false,
    recData={}, recConn=nil,
    lastRecCF=nil, recStart=0,
    recThrottle=0, lastRecTime=0, recUICounter=0, recAccumT=0,
    smartRec=false,
    lastSmartState="", lastSmartPos=Vector3.new(0,0,0),
    smartDebounce=0,
    repData=nil, repConn=nil,
    isPlaying=false, isPausedPlay=false,
    isLooping=false, repSpeed=1.0,
    wallBase=0, elapsedAtBase=0, pbElapsed=0,
    realWallBase=0, realElapsedBase=0, realElapsed=0,
    curFrame=1, lastPlayFrame=1,
    loopCount=0, lastWipeFrame=0,
    localPlayCopy=nil,
    savedReplays={}, repCounter=1,
    selectedMerge={}, selectedDelete={},
    checkpoints={}, cpCounter=1,
    initSummit=0, curSummit=0,
    summitInc=0, summitPPM=0,
    lastSummitUpdate=0, summitTarget=1000,
    sessionStart=tick(),
    lsTarget=0, lsEnabled=false, lsReached=false,
    fps=60, frameCount=0, fpsUpdateTime=tick(), memMB=0,
    isMinimized=false, isDragging=false,
    dragStart=nil, startPos=nil, draggingSpeed=false,
    activeRepTracks={}, animMapB={}, activeAnimSet={},
    cfCache={idxA=-1,idxB=-1,cfA=nil,cfB=nil},
    animPool={}, animStatesBuf={},
    uiC={recStatus="",recFrames="",recPos="",recSaved="",
         frames="",time="",loops="",
         realTime="",repTime="",totalDur="",
         fps="",mem="",ft=""},
    playUICounter=0,
    MAX_FRAMES=108000, REC_INTERVAL=1, ANIM_CACHE_MAX=20,
    SAVE_FOLDER="MTP_Replays", WIN_W=360, WIN_H=820,
    RAM_WIPE=30, GC_INT=15, GC_LIGHT=5, GC_HEAVY_KB=65536,
    lastGC=0, lastLightGC=0, lastHeavyGC=0,
    REC_UI_INT=6, PLAY_UI_INT=4,
    trimStart=0, trimEnd=0,
}

local U={
    sg=nil, win=nil, content=nil,
    startBtn=nil, stopRecBtn=nil, saveBtn=nil,
    statusLbl=nil, frameLbl=nil, posLbl=nil, savedLbl=nil,
    smartRecBtn=nil, smartStatusLbl=nil,
    trimStartBox=nil, trimEndBox=nil, trimInfoLbl=nil,
    urlBox=nil, urlLoadBtn=nil, urlStatusLbl=nil,
    fileStatusLbl=nil, fileListScroll=nil,
    listScroll=nil, listToggleBtn=nil,
    selAllBtn=nil, selNoneBtn=nil, delSelBtn=nil,
    multiRepLbl=nil,
    mergePBtn=nil, mergeLBtn=nil, mergeSBtn=nil,
    playPauseBtn=nil, stopPlayBtn=nil, loopBtn=nil,
    repStatusLbl=nil, framesLbl=nil, pbInfoLbl=nil, progressBar=nil,
    speedValLbl=nil, sliderFill=nil, sliderBg=nil,
    presetBtns={},
    summitInfoLbl=nil, summitRateLbl=nil, summitLeftLbl=nil,
    pctLbl=nil, etaLbl=nil, doneLbl=nil, summitBar=nil,
    fpsLbl=nil, memLbl=nil,
    lsToggleBtn=nil, lsTargetBox=nil, lsStatusLbl=nil,
    lsEtaLbl=nil,
    refreshCPList=nil,
    refreshRepList=nil,
}

local function initCore()

local function getFreshRefs()
    local c=pl.Character; if not c then return nil,nil,nil end
    local r=c:FindFirstChild("HumanoidRootPart")
    local h=c:FindFirstChild("Humanoid")
    return r,h,h and h:FindFirstChild("Animator")
end

local char=pl.Character or pl.CharacterAdded:Wait()
S.char=char
S.hum=char:WaitForChild("Humanoid",10)
S.rp=char:WaitForChild("HumanoidRootPart",10)
S.anim=S.hum and S.hum:WaitForChild("Animator",10)
assert(S.hum and S.rp,"Hum/RP not found")
pl.CharacterAdded:Connect(function(nc)
    S.char=nc
    S.hum=nc:WaitForChild("Humanoid",10)
    S.rp=nc:WaitForChild("HumanoidRootPart",10)
    S.anim=S.hum and S.hum:WaitForChild("Animator",10)
end)

local function forceGC() pcall(collectgarbage,"collect") pcall(collectgarbage,"collect") end
local function deferGC() task.defer(forceGC) end
local function smartGC()
    local now=tick(); local kb=gcinfo()
    if now-S.lastLightGC>=S.GC_LIGHT then S.lastLightGC=now; pcall(collectgarbage,"collect") end
    if kb>S.GC_HEAVY_KB and now-S.lastHeavyGC>=2 then S.lastHeavyGC=now; forceGC() end
end

local function notify(t,m,d) pcall(SG.SetCore,SG,"SendNotification",{Title=t,Text=m,Duration=d or 3}) end
local function tw(o,p,d,st,dr)
    pcall(function() TS:Create(o,TweenInfo.new(d or 0.18,st or Enum.EasingStyle.Quad,dr or Enum.EasingDirection.Out),p):Play() end)
end

local function fmtTime(s)
    s=math.max(0,s or 0)
    local h=math.floor(s/3600); local m=math.floor((s%3600)/60); local sc=math.floor(s%60)
    return h>0 and ("%02d:%02d:%02d"):format(h,m,sc) or ("%02d:%02d"):format(m,sc)
end
local function fmtTimeDec(s)
    s=math.max(0,s or 0); return ("%02d:%04.1f"):format(math.floor(s/60),s%60)
end
local function fmtDT(ts)
    local d=os.date("*t",ts); return ("%02d/%02d %02d:%02d"):format(d.day,d.month,d.hour,d.min)
end

local function cfFromData(cfd)
    if not cfd then return CFrame.new() end
    local p,lv,rv,uv=cfd.p,cfd.lv,cfd.rv,cfd.uv
    if not(p and lv and rv and uv) then return CFrame.new() end
    return CFrame.fromMatrix(Vector3.new(p[1],p[2],p[3]),Vector3.new(rv[1],rv[2],rv[3]),
        Vector3.new(uv[1],uv[2],uv[3]),-Vector3.new(lv[1],lv[2],lv[3]))
end
local function cfToData(cf)
    return{p={cf.X,cf.Y,cf.Z},lv={cf.LookVector.X,cf.LookVector.Y,cf.LookVector.Z},
        rv={cf.RightVector.X,cf.RightVector.Y,cf.RightVector.Z},
        uv={cf.UpVector.X,cf.UpVector.Y,cf.UpVector.Z}}
end

local function cfToQuat(cf)
    local rx,ry,rz=cf.RightVector.X,cf.RightVector.Y,cf.RightVector.Z
    local ux,uy,uz=cf.UpVector.X,cf.UpVector.Y,cf.UpVector.Z
    local bx,by,bz=-cf.LookVector.X,-cf.LookVector.Y,-cf.LookVector.Z
    local tr=rx+uy+bz; local w,x,y,z
    if tr>0 then local s=0.5/math.sqrt(tr+1); w=0.25/s;x=(uz-by)*s;y=(bx-rz)*s;z=(ry-ux)*s
    elseif rx>uy and rx>bz then local s=2*math.sqrt(1+rx-uy-bz);w=(uz-by)/s;x=0.25*s;y=(uy+rx)/s;z=(bx+rz)/s
    elseif uy>bz then local s=2*math.sqrt(1+uy-rx-bz);w=(bx-rz)/s;x=(ux+ry)/s;y=0.25*s;z=(uz+by)/s
    else local s=2*math.sqrt(1+bz-rx-uy);w=(ry-ux)/s;x=(bx+rz)/s;y=(uz+by)/s;z=0.25*s end
    return{w=w,x=x,y=y,z=z}
end
local function quatSlerp(a,b,t)
    local dot=a.w*b.w+a.x*b.x+a.y*b.y+a.z*b.z
    if dot<0 then b={w=-b.w,x=-b.x,y=-b.y,z=-b.z};dot=-dot end
    dot=math.clamp(dot,-1,1)
    local s0,s1
    if dot>0.9995 then s0=1-t;s1=t
    else local th=math.acos(dot);local sth=math.sin(th);s0=math.sin((1-t)*th)/sth;s1=math.sin(t*th)/sth end
    local r={w=s0*a.w+s1*b.w,x=s0*a.x+s1*b.x,y=s0*a.y+s1*b.y,z=s0*a.z+s1*b.z}
    local l=math.sqrt(r.w*r.w+r.x*r.x+r.y*r.y+r.z*r.z); if l<1e-6 then return a end
    return{w=r.w/l,x=r.x/l,y=r.y/l,z=r.z/l}
end
local function quatToCF(q,pos)
    local w,x,y,z=q.w,q.x,q.y,q.z
    local xx,yy,zz=x*x,y*y,z*z; local xy,xz,yz=x*y,x*z,y*z; local wx,wy,wz=w*x,w*y,w*z
    return CFrame.new(pos.X,pos.Y,pos.Z,1-2*(yy+zz),2*(xy-wz),2*(xz+wy),2*(xy+wz),1-2*(xx+zz),2*(yz-wx),2*(xz-wy),2*(yz+wx),1-2*(xx+yy))
end
local function lerpCF(a,b,t)
    return quatToCF(quatSlerp(cfToQuat(a),cfToQuat(b),t),a.Position:Lerp(b.Position,t))
end

local function tpTo(cf) pcall(function() local r=getFreshRefs(); if r then r.CFrame=cf elseif S.rp then S.rp.CFrame=cf end end) end

local function calcElapsed() return S.elapsedAtBase+(tick()-S.wallBase)*S.repSpeed end
local function calcRealElapsed() return S.realElapsedBase+(tick()-S.realWallBase) end

local HAS_IO=typeof(readfile)=="function" and typeof(writefile)=="function"
local function ensureFolder()
    if not HAS_IO then return end
    pcall(function() if not isfolder(S.SAVE_FOLDER) then makefolder(S.SAVE_FOLDER) end end)
end
local function normalizeFrame(fd)
    if fd.cframe and not fd.cfd then fd.cfd={p=fd.cframe.position,lv=fd.cframe.lookVector,rv=fd.cframe.rightVector,uv=fd.cframe.upVector} end
    if fd.animations and not fd.anims then fd.anims={} for _,a in ipairs(fd.animations) do table.insert(fd.anims,{id=a.id,tp=a.timePosition or 0,sp=a.speed or 1,pri=a.priority or "Core"}) end end
    if not fd.t then fd.t=fd.time or 0 end; if not fd.ws then fd.ws=fd.walkSpeed or 16 end; if not fd.dt then fd.dt=1/60 end
end
local function saveToFile(name,data)
    if not HAS_IO then notify("Error","File IO N/A"); return false end
    ensureFolder()
    local ok,enc=pcall(HS.JSONEncode,HS,data); if not ok then notify("Error","Encode fail"); return false end
    local wok=pcall(writefile,S.SAVE_FOLDER.."/"..name..".json",enc)
    if wok then notify("Saved",name..".json ("..math.floor(#enc/1024).."KB)"); return true end
    notify("Error","Write fail"); return false
end
local function loadFromFile(path)
    if not HAS_IO then notify("Error","File IO N/A"); return nil end
    local raw; local ok=pcall(function() raw=readfile(path) end)
    if not ok or not raw then notify("Error","Read fail: "..tostring(path)); return nil end
    local dok,data=pcall(HS.JSONDecode,HS,raw)
    if not dok or type(data)~="table" or #data==0 then notify("Error","Invalid format"); return nil end
    for _,fd in ipairs(data) do normalizeFrame(fd) end
    if #data>1 and data[2].t-data[1].t>10 then local t0=data[1].t; for _,fd in ipairs(data) do fd.t=fd.t-t0 end end
    return data
end
local function loadFromURL(url)
    local raw
    local ok = pcall(function()
        local res = request({ Url = url, Method = "GET" })
        raw = res.Body
    end)
    if not ok or not raw or raw == "" then notify("Error","URL fetch fail"); return nil end
    local dok,data = pcall(HS.JSONDecode, HS, raw)
    if not dok or type(data)~="table" or #data==0 then notify("Error","Invalid JSON from URL"); return nil end
    for _,fd in ipairs(data) do normalizeFrame(fd) end
    if #data>1 and data[2].t-data[1].t>10 then local t0=data[1].t; for _,fd in ipairs(data) do fd.t=fd.t-t0 end end
    return data
end
local function listFiles()
    if not HAS_IO then return {} end
    local files={}
    pcall(function() ensureFolder(); for _,path in ipairs(listfiles(S.SAVE_FOLDER)) do
        if path:sub(-5)==".json" then local n=path:match("([^/\\]+)%.json$") or path; table.insert(files,{name=n,path=path}) end
    end end)
    return files
end

local function applyTrim(data)
    if not data or #data==0 then return data end
    local s=math.max(1,1+S.trimStart)
    local e=math.max(s,#data-S.trimEnd)
    if s==1 and e==#data then return data end
    local out={}
    local t0=data[s].t
    for i=s,e do
        local fd=data[i]; local fr={}
        for k,v in pairs(fd) do fr[k]=v end
        fr.t=fd.t-t0
        table.insert(out,fr)
    end
    return out
end

local function getSummit()
    local ls=pl:FindFirstChild("leaderstats")
    if ls then for _,v in ipairs(ls:GetChildren()) do if v.Name:lower():find("summit") then return v.Value or 0 end end end
    for _,v in ipairs(pl:GetDescendants()) do if v.Name:lower():find("summit") and(v:IsA("IntValue") or v:IsA("NumberValue")) then return v.Value or 0 end end
    local lb=workspace:FindFirstChild("Leaderboard"); if lb then local pe=lb:FindFirstChild(pl.Name); if pe then for _,v in ipairs(pe:GetChildren()) do if v.Name:lower():find("summit") then return v.Value or 0 end end end end
    return 0
end
S.initSummit=getSummit(); S.curSummit=S.initSummit

local priMap={Action4=Enum.AnimationPriority.Action4,Action3=Enum.AnimationPriority.Action3,Action2=Enum.AnimationPriority.Action2,Action=Enum.AnimationPriority.Action,Movement=Enum.AnimationPriority.Movement,Idle=Enum.AnimationPriority.Idle,Core=Enum.AnimationPriority.Core}
local function getAnimInst(id)
    if S.animPool[id] then return S.animPool[id] end
    local a=Instance.new("Animation"); a.AnimationId=id; S.animPool[id]=a; return a
end
local function trimAnimCache()
    local n=0; for _ in pairs(S.activeRepTracks) do n=n+1 end
    if n>S.ANIM_CACHE_MAX then for id,tr in pairs(S.activeRepTracks) do if not tr.IsPlaying then S.activeRepTracks[id]=nil; return end end end
end
local function getAnimStates()
    local buf=S.animStatesBuf; local n=#buf; for i=1,n do buf[i]=nil end
    local _,hum=getFreshRefs(); hum=hum or S.hum
    local ok,tracks=pcall(function() return hum:GetPlayingAnimationTracks() end)
    if ok and tracks then local idx=0
        for _,t in pairs(tracks) do if t and t.IsPlaying then idx=idx+1
            local e=buf[idx]
            if e then e.id=t.Animation.AnimationId;e.tp=t.TimePosition;e.sp=t.Speed;e.pri=tostring(t.Priority)
            else buf[idx]={id=t.Animation.AnimationId,tp=t.TimePosition,sp=t.Speed,pri=tostring(t.Priority)} end
        end end
    end
    local snap=table.create(#buf); for i,v in ipairs(buf) do snap[i]={id=v.id,tp=v.tp,sp=v.sp,pri=v.pri} end
    return snap
end
local function playAnimData(aA,aB,alpha)
    local tp=aA.tp; if aB and alpha and alpha>0 then tp=aA.tp+(aB.tp-aA.tp)*alpha end
    local ex=S.activeRepTracks[aA.id]
    if ex and not ex.IsPlaying then S.activeRepTracks[aA.id]=nil; ex=nil end
    if ex then pcall(function() ex:AdjustSpeed(aA.sp*S.repSpeed) end); pcall(function() if math.abs(ex.TimePosition-tp)>0.15 then ex.TimePosition=tp end end); return end
    local anim=getAnimInst(aA.id); local _,_,useAnim=getFreshRefs(); useAnim=useAnim or S.anim; if not useAnim then return end
    local ok,track=pcall(function() return useAnim:LoadAnimation(anim) end); if not ok or not track then return end
    local pri=Enum.AnimationPriority.Core; for k,v in pairs(priMap) do if aA.pri:find(k) then pri=v; break end end
    pcall(function() track.Priority=pri; track:Play(0.05); track:AdjustSpeed(aA.sp*S.repSpeed); track.TimePosition=tp end)
    S.activeRepTracks[aA.id]=track; trimAnimCache()
end
local function stopStaleAnims(curAnims)
    for k in pairs(S.activeAnimSet) do S.activeAnimSet[k]=nil end
    for _,a in ipairs(curAnims) do S.activeAnimSet[a.id]=true end
    for id,tr in pairs(S.activeRepTracks) do if not S.activeAnimSet[id] then pcall(function() if tr.IsPlaying then tr:Stop(0.1) end end); S.activeRepTracks[id]=nil end end
end
local function clearAllAnims()
    for _,tr in pairs(S.activeRepTracks) do pcall(function() if tr and tr.IsPlaying then tr:Stop(0.05) end end) end
    S.activeRepTracks={}; task.defer(deferGC)
end

local function repDuration(d) if not d or #d<2 then return 0 end; return d[#d].t-d[1].t end
local function findFrame(d,targetT)
    if targetT<=d[1].t then return 1 end; if targetT>=d[#d].t then return math.max(1,#d-1) end
    local lo,hi=1,#d-1
    while lo<hi do local mid=math.floor((lo+hi+1)/2); if d[mid].t<=targetT then lo=mid else hi=mid-1 end end
    return lo
end
local function makeLocalCopy(d)
    local c=table.create(#d)
    for i=1,#d do local s=d[i]; c[i]={t=s.t,dt=s.dt,ws=s.ws,hs=s.hs,cfd=s.cfd,anims=s.anims,vel=s.vel} end
    return c
end
local function restoreLocalCopy(c,orig)
    for i=1,#orig do if c[i] then c[i].cfd=orig[i].cfd;c[i].anims=orig[i].anims;c[i].vel=orig[i].vel;c[i].hs=orig[i].hs end end
end

local updatePlayUI=function() end
local updateRecUI=function() end
local updateSummitUI=function() end
local updateLoopSummitUI=function() end

local function stopReplay()
    if not S.isPlaying then return end
    S.isPlaying=false; S.isPausedPlay=false
    if S.repConn then S.repConn:Disconnect(); S.repConn=nil end
    clearAllAnims()
    if S.localPlayCopy then
        for i=1,#S.localPlayCopy do if S.localPlayCopy[i] then S.localPlayCopy[i].cfd=nil;S.localPlayCopy[i].anims=nil;S.localPlayCopy[i]=nil end end
        S.localPlayCopy=nil
    end
    S.cfCache.idxA=-1;S.cfCache.idxB=-1;S.cfCache.cfA=nil;S.cfCache.cfB=nil
    local _,hum=getFreshRefs(); hum=hum or S.hum
    pcall(function() if hum then hum.AutoRotate=true; hum.WalkSpeed=16 end end)
    pcall(function()
        if U.playPauseBtn then U.playPauseBtn.Text="▶  PLAY"; U.playPauseBtn.BackgroundColor3=C.dG end
        if U.repStatusLbl then U.repStatusLbl.Text="Stopped" end
    end)
    forceGC(); deferGC()
end

local function playReplay(data)
    local rd=data or S.repData
    if not rd or #rd==0 then notify("Error","No replay data!"); return end

    if S.isPlaying and not S.isPausedPlay then
        S.isPausedPlay=true
        S.pbElapsed=calcElapsed()
        S.realElapsed=calcRealElapsed()
        pcall(function()
            if U.playPauseBtn then U.playPauseBtn.Text="▶  RESUME"; U.playPauseBtn.BackgroundColor3=C.dA end
            if U.repStatusLbl then U.repStatusLbl.Text="Paused" end
        end)
        return
    elseif S.isPlaying and S.isPausedPlay then
        S.isPausedPlay=false
        S.elapsedAtBase=S.pbElapsed
        S.wallBase=tick()
        S.realElapsedBase=S.realElapsed
        S.realWallBase=tick()
        pcall(function()
            if U.playPauseBtn then U.playPauseBtn.Text="⏸  PAUSE"; U.playPauseBtn.BackgroundColor3=C.dA end
            if U.repStatusLbl then U.repStatusLbl.Text="Playing" end
        end)
        return
    end

    S.repData=rd
    S.isPlaying=true
    S.isPausedPlay=false
    S.curFrame=1; S.lastPlayFrame=1; S.loopCount=0
    S.pbElapsed=0; S.elapsedAtBase=0; S.wallBase=tick()
    S.realElapsed=0; S.realElapsedBase=0; S.realWallBase=tick()
    S.lastWipeFrame=0; S.playUICounter=0; S.lsReached=false
    S.cfCache.idxA=-1; S.cfCache.idxB=-1; S.cfCache.cfA=nil; S.cfCache.cfB=nil

    if S.localPlayCopy then for i=1,#S.localPlayCopy do S.localPlayCopy[i]=nil end end
    S.localPlayCopy=makeLocalCopy(rd)

    pcall(function()
        if U.playPauseBtn then U.playPauseBtn.Text="⏸  PAUSE"; U.playPauseBtn.BackgroundColor3=C.dA end
        if U.repStatusLbl then U.repStatusLbl.Text="Playing" end
    end)

    if S.repConn then S.repConn:Disconnect() end
    clearAllAnims()

    local _,hum0=getFreshRefs(); hum0=hum0 or S.hum
    pcall(function() if hum0 then hum0.AutoRotate=false; hum0.PlatformStand=false end end)

    local dur=repDuration(rd)
    local rdLen=#rd
    local lc=S.localPlayCopy
    local lastSetCF=nil
    local SMOOTH_ALPHA=0.35

    S.repConn=RS.Heartbeat:Connect(function(dt)
        if not S.isPlaying or S.isPausedPlay then return end

        S.pbElapsed=calcElapsed()
        S.realElapsed=calcRealElapsed()

        if S.pbElapsed>=dur then
            if S.isLooping then
                if S.lsEnabled and not S.lsReached then
                    S.curSummit=getSummit()
                    if S.curSummit>=S.lsTarget then
                        S.lsReached=true
                        local rt=fmtTimeDec(S.realElapsed)
                        stopReplay()
                        notify("Target!","Summit "..S.lsTarget.." reached! "..S.loopCount.." loops | "..rt,8)
                        pcall(updateLoopSummitUI)
                        return
                    end
                end
                S.loopCount=S.loopCount+1
                S.pbElapsed=0; S.elapsedAtBase=0; S.wallBase=tick()
                S.curFrame=1; S.lastWipeFrame=0
                S.cfCache.idxA=-1; S.cfCache.idxB=-1; S.cfCache.cfA=nil; S.cfCache.cfB=nil
                lastSetCF=nil
                restoreLocalCopy(lc,rd)
                task.defer(smartGC)
                S.curSummit=getSummit()
                S.summitInc=S.curSummit-S.initSummit
                pcall(function() if U.repStatusLbl then U.repStatusLbl.Text="Loop #"..S.loopCount end end)
                pcall(updateLoopSummitUI)
            else
                local rt=fmtTimeDec(S.realElapsed)
                stopReplay()
                notify("Done","Replay done! "..S.loopCount.." loops | "..rt)
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
                if lc[i] then lc[i].cfd=nil;lc[i].anims=nil;lc[i].vel=nil;lc[i].hs=nil;lc[i]=nil end
            end
            S.lastWipeFrame=wt
        end

        local frmA=lc[fA]
        local frmB=lc[fB]
        if not frmA or not frmA.cfd then updatePlayUI(); return end

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

        local smoothFactor=1-math.pow(1-SMOOTH_ALPHA,dt*60)
        smoothFactor=math.clamp(smoothFactor,0,1)

        local finalCF
        if lastSetCF then
            local smoothPos=lastSetCF.Position:Lerp(targetCF.Position,smoothFactor)
            local smoothRot=lerpCF(lastSetCF-lastSetCF.Position,targetCF-targetCF.Position,smoothFactor)
            finalCF=CFrame.new(smoothPos)*(smoothRot-smoothRot.Position)
        else finalCF=targetCF end
        lastSetCF=finalCF

        local r2,hum2=getFreshRefs()
        r2=r2 or S.rp; hum2=hum2 or S.hum
        pcall(function()
            if r2 then r2.CFrame=finalCF end
            if hum2 and frmB and frmB.cfd then
                local wsA=frmA.ws or 16; local wsB=frmB.ws or 16
                hum2.WalkSpeed=wsA+(wsB-wsA)*alpha
            end
        end)

        if frmA.anims and #frmA.anims>0 then
            for k in pairs(S.animMapB) do S.animMapB[k]=nil end
            if frmB and frmB.anims then for _,ab in ipairs(frmB.anims) do S.animMapB[ab.id]=ab end end
            for _,ad in ipairs(frmA.anims) do pcall(playAnimData,ad,S.animMapB[ad.id],alpha) end
            if S.playUICounter%3==0 then pcall(stopStaleAnims,frmA.anims) end
        else
            if next(S.activeRepTracks)~=nil then clearAllAnims() end
        end

        updatePlayUI()
    end)
end

local function captureFrame()
    local rp,hum=getFreshRefs(); rp=rp or S.rp; hum=hum or S.hum
    if not rp or not hum then return nil end
    local char=rp.Parent; if not char or not char.Parent then return nil end
    local vel=rp.AssemblyLinearVelocity; local now=tick()
    local dt=S.lastRecTime>0 and math.clamp(now-S.lastRecTime,0.001,0.05) or (1/60)
    S.lastRecTime=now; S.recAccumT=S.recAccumT+dt
    return{t=S.recAccumT,dt=dt,cfd=cfToData(rp.CFrame),vel={vel.X,vel.Y,vel.Z},ws=hum.WalkSpeed,hs=tostring(hum:GetState()),anims=getAnimStates()}
end

local function startRecording()
    if S.isRec and not S.isPausedRec then return end
    if S.isPlaying then notify("Error","Stop replay first!"); return end
    if S.isPausedRec then S.isPausedRec=false
    else S.isRec=true;S.recData=table.create(math.min(S.MAX_FRAMES,3600));S.isPausedRec=false;S.recStart=tick();S.recThrottle=0;S.lastRecTime=0;S.recUICounter=0;S.recAccumT=0;deferGC() end
    pcall(function() if U.startBtn then U.startBtn.Text="⏸  PAUSE";U.startBtn.BackgroundColor3=C.dA end end)
    if S.recConn then S.recConn:Disconnect() end
    S.recConn=RS.RenderStepped:Connect(function()
        if not S.isRec or S.isPausedRec then return end
        S.recThrottle=S.recThrottle+1; if S.recThrottle<S.REC_INTERVAL then return end; S.recThrottle=0
        if #S.recData>=S.MAX_FRAMES then notify("Warning","Max frames! Auto-pause."); S.isPausedRec=true; return end
        local fd=captureFrame()
        if fd then table.insert(S.recData,fd); local ok,cf=pcall(cfFromData,fd.cfd); if ok then S.lastRecCF=cf end end
        updateRecUI()
        local now=tick(); if now-S.lastGC>S.GC_INT then S.lastGC=now; task.defer(smartGC) end
    end)
end

local function pauseRecording()
    if not S.isRec or S.isPausedRec then return end
    S.isPausedRec=true; if S.recConn then S.recConn:Disconnect(); S.recConn=nil end
    pcall(function() if U.startBtn then U.startBtn.Text="▶  CONTINUE";U.startBtn.BackgroundColor3=C.dG end end)
    if #S.recData>0 then local lf=S.recData[#S.recData]; if lf and lf.cfd then local ok,cf=pcall(cfFromData,lf.cfd); if ok then S.lastRecCF=cf end end end
    updateRecUI()
end

local function stopRecording()
    if not S.isRec then return end
    S.isRec=false;S.isPausedRec=false
    if S.recConn then S.recConn:Disconnect(); S.recConn=nil end
    pcall(function() if U.startBtn then U.startBtn.Text="⏺  RECORD";U.startBtn.BackgroundColor3=C.dR end end)
    if #S.recData>0 then local lf=S.recData[#S.recData]; if lf and lf.cfd then local ok,cf=pcall(cfFromData,lf.cfd); if ok then S.lastRecCF=cf end end
    elseif S.rp then S.lastRecCF=S.rp.CFrame end
    updateRecUI(); deferGC()
end

local function saveRecording()
    if #S.recData==0 then notify("Error","No data!"); return end
    local trimmed=applyTrim(S.recData)
    if not trimmed or #trimmed==0 then notify("Error","Trim removed all frames!"); return end
    local name="Replay_"..S.repCounter; S.repCounter=S.repCounter+1
    table.insert(S.savedReplays,{name=name,data=trimmed,frames=#trimmed,time=os.time()})
    notify("Saved",name.." ("..#trimmed.." frames)"); updateRecUI(); deferGC()
end

local SMART_STATES={
    ["Jumping"]=true,["Freefall"]=true,["Running"]=true,
    ["Swimming"]=true,["Climbing"]=true,["GettingUp"]=true,
}
local SMART_MOVE_THRESHOLD=0.5
local SMART_IDLE_TIMEOUT=1.5
local smartIdleTimer=0

local function updateSmartRec(dt)
    if not S.smartRec then return end
    local _,hum=getFreshRefs(); hum=hum or S.hum
    local rp=S.rp
    if not hum or not rp then return end

    local curState=tostring(hum:GetState())
    local curPos=rp.Position
    local moved=(curPos-S.lastSmartPos).Magnitude
    local isActive=SMART_STATES[curState] or moved>SMART_MOVE_THRESHOLD or (hum.MoveDirection.Magnitude>0.1)
    S.lastSmartPos=curPos

    if isActive then
        smartIdleTimer=0
        if not S.isRec or S.isPausedRec then
            startRecording()
            pcall(function()
                if U.smartStatusLbl then
                    U.smartStatusLbl.Text="● Active — "..curState
                    U.smartStatusLbl.TextColor3=C.a3
                end
            end)
        else
            if S.recUICounter%12==0 then
                pcall(function()
                    if U.smartStatusLbl then
                        U.smartStatusLbl.Text="● "..curState.."  "..#S.recData.."f"
                        U.smartStatusLbl.TextColor3=C.a3
                    end
                end)
            end
        end
    else
        if S.isRec and not S.isPausedRec then
            smartIdleTimer=smartIdleTimer+dt
            if smartIdleTimer>=SMART_IDLE_TIMEOUT then
                smartIdleTimer=0
                pauseRecording()
                pcall(function()
                    if U.smartStatusLbl then
                        U.smartStatusLbl.Text="○ Waiting..."
                        U.smartStatusLbl.TextColor3=C.t3
                    end
                end)
            else
                local left=math.ceil(SMART_IDLE_TIMEOUT-smartIdleTimer)
                pcall(function()
                    if U.smartStatusLbl then
                        U.smartStatusLbl.Text="○ Idle pause in "..left.."s"
                        U.smartStatusLbl.TextColor3=C.a5
                    end
                end)
            end
        else
            pcall(function()
                if U.smartStatusLbl then
                    U.smartStatusLbl.Text="○ Waiting..."
                    U.smartStatusLbl.TextColor3=C.t3
                end
            end)
        end
    end
    S.lastSmartState=curState
end

local function toggleSmartRec()
    S.smartRec=not S.smartRec
    if S.smartRec then
        S.lastSmartState=""
        local rp=S.rp; S.lastSmartPos=rp and rp.Position or Vector3.new(0,0,0)
        smartIdleTimer=0
        S.isRec=false; S.isPausedRec=false
        if S.recConn then S.recConn:Disconnect(); S.recConn=nil end
        S.recData=table.create(math.min(S.MAX_FRAMES,3600))
        S.recStart=tick();S.recThrottle=0;S.lastRecTime=0;S.recUICounter=0;S.recAccumT=0
        notify("Smart Rec","Auto-detect ON")
        pcall(function()
            if U.smartRecBtn then U.smartRecBtn.Text="SMART  ON"; U.smartRecBtn.BackgroundColor3=Color3.fromRGB(0,100,55) end
            if U.smartStatusLbl then U.smartStatusLbl.Text="○ Waiting..."; U.smartStatusLbl.TextColor3=C.t3 end
        end)
    else
        if S.isRec then stopRecording() end
        smartIdleTimer=0
        notify("Smart Rec","Auto-detect OFF")
        pcall(function()
            if U.smartRecBtn then U.smartRecBtn.Text="SMART REC"; U.smartRecBtn.BackgroundColor3=C.bg4 end
            if U.smartStatusLbl then U.smartStatusLbl.Text="Off"; U.smartStatusLbl.TextColor3=C.t3 end
        end)
    end
end

local function saveCP()
    local rp=getFreshRefs(); rp=rp or S.rp; if not rp then notify("Error","No RootPart"); return end
    local name="CP_"..S.cpCounter; S.cpCounter=S.cpCounter+1; local cf=rp.CFrame
    table.insert(S.checkpoints,{name=name,cf=cf,time=os.time()})
    notify("Checkpoint",name.." saved"); pcall(function() if U.refreshCPList then U.refreshCPList() end end)
end
local function tpToCP(idx) local cp=S.checkpoints[idx]; if cp then tpTo(cp.cf); notify("TP","To "..cp.name) end end
local function deleteCP(idx) local cp=S.checkpoints[idx]; if not cp then return end; local n=cp.name; table.remove(S.checkpoints,idx); notify("Deleted",n); pcall(function() if U.refreshCPList then U.refreshCPList() end end) end

local function updateSummit(force)
    local now=tick(); if not force and now-S.lastSummitUpdate<5 then return end; S.lastSummitUpdate=now
    S.curSummit=getSummit(); S.summitInc=S.curSummit-S.initSummit
    local elapsed=now-S.sessionStart; S.summitPPM=elapsed>0 and (S.summitInc/elapsed)*60 or 0
    pcall(function()
        if U.summitInfoLbl then U.summitInfoLbl.Text=("%d  (+%d)"):format(S.curSummit,S.summitInc) end
        if U.summitRateLbl then U.summitRateLbl.Text=("%.1f / min   Loops: %d"):format(S.summitPPM,S.loopCount) end
        local left=math.max(0,S.summitTarget-S.curSummit); local pct=math.min(1,S.curSummit/math.max(1,S.summitTarget))
        if U.summitLeftLbl then U.summitLeftLbl.Text="Remaining: "..left end
        if U.pctLbl then U.pctLbl.Text=math.floor(pct*100).."%" end
        if U.summitBar then tw(U.summitBar,{Size=UDim2.new(pct,0,1,0)},0.4) end
        local er=S.summitPPM; if S.isPlaying and S.isLooping and S.repSpeed>0 then er=S.summitPPM*S.repSpeed end
        if er>0 and left>0 then local eta=(left/er)*60
            if U.etaLbl then U.etaLbl.Text="ETA  "..fmtTime(eta) end
            if U.doneLbl then U.doneLbl.Text="Done  "..fmtDT(now+eta) end
        else
            if U.etaLbl then U.etaLbl.Text="ETA  —" end
            if U.doneLbl then U.doneLbl.Text=S.curSummit>=S.summitTarget and "✓ Achieved" or "Done  —" end
        end
    end)
    if S.curSummit>=S.summitTarget then notify("Target!","🎯 "..S.summitTarget.." Summit!",6) end
    pcall(updateLoopSummitUI)
end
local function resetSummit()
    S.initSummit=getSummit();S.curSummit=S.initSummit;S.summitInc=0
    S.loopCount=0;S.summitPPM=0;S.sessionStart=tick()
    updateSummit(true); notify("Reset","Summit reset")
end

local function mergeSelected()
    local sel={}; for idx,v in pairs(S.selectedMerge) do if v and S.savedReplays[idx] then table.insert(sel,{idx=idx,rep=S.savedReplays[idx]}) end end
    table.sort(sel,function(a,b) return a.idx<b.idx end)
    if #sel<1 then notify("Error","Select at least 1!"); return nil end
    local merged,tOff={},0
    for _,e in ipairs(sel) do local d=e.rep.data; if #d>0 then
        local t0=d[1].t; local tEnd=d[#d].t-t0
        for _,fd in ipairs(d) do local fr={}; for k,v in pairs(fd) do fr[k]=v end; fr.t=tOff+(fd.t-t0); table.insert(merged,fr) end
        tOff=tOff+tEnd+0.05
    end end
    if #merged==0 then notify("Error","Merge empty"); return nil end
    notify("Merged",#sel.." replays → "..#merged.." frames"); return merged
end

local function updatePerf()
    S.frameCount=S.frameCount+1; local now=tick()
    if now-S.fpsUpdateTime>=1 then
        S.fps=math.floor(S.frameCount/math.max(0.001,now-S.fpsUpdateTime)); S.frameCount=0; S.fpsUpdateTime=now
        local fs=tostring(S.fps); pcall(function() if U.fpsLbl and S.uiC.fps~=fs then U.fpsLbl.Text=fs;S.uiC.fps=fs end end)
        task.defer(smartGC)
    end
    if S.frameCount%30==0 then local kb=gcinfo(); S.memMB=math.floor(kb/102.4)/10
        local ms=S.memMB.."MB"; pcall(function() if U.memLbl and S.uiC.mem~=ms then U.memLbl.Text=ms;S.uiC.mem=ms end end)
    end
end

updatePlayUI=function()
    S.playUICounter=S.playUICounter+1; local doFull=(S.playUICounter%S.PLAY_UI_INT==0)
    pcall(function()
        if not S.repData or #S.repData==0 then return end
        local pct=math.clamp(S.curFrame/#S.repData,0,1)
        if U.progressBar then tw(U.progressBar,{Size=UDim2.new(pct,0,1,0)},0.08) end
        if not doFull then return end
        local dur=repDuration(S.repData)
        local fs=S.curFrame.." / "..#S.repData; if U.framesLbl and S.uiC.frames~=fs then U.framesLbl.Text=fs;S.uiC.frames=fs end
        if S.isPlaying and not S.isPausedPlay then S.realElapsed=calcRealElapsed() end
        local info=("%s / %s  ×%.2f   Loop %d"):format(fmtTime(S.pbElapsed),fmtTime(dur),S.repSpeed,S.loopCount)
        if U.pbInfoLbl and S.uiC.repTime~=info then U.pbInfoLbl.Text=info;S.uiC.repTime=info end
    end)
end
updateRecUI=function()
    S.recUICounter=S.recUICounter+1; if S.recUICounter<S.REC_UI_INT then return end; S.recUICounter=0
    pcall(function()
        local st="Status: "..(S.isPausedRec and "Paused" or(S.isRec and "Recording" or "Ready"))
        if U.statusLbl and S.uiC.recStatus~=st then U.statusLbl.Text=st;S.uiC.recStatus=st end
        local fr="Frames: "..#S.recData; if U.frameLbl and S.uiC.recFrames~=fr then U.frameLbl.Text=fr;S.uiC.recFrames=fr end
        if U.posLbl and S.lastRecCF then local p=S.lastRecCF.Position; local ps=("%.0f, %.0f, %.0f"):format(p.X,p.Y,p.Z); if S.uiC.recPos~=ps then U.posLbl.Text=ps;S.uiC.recPos=ps end end
        local sv="Saved: "..#S.savedReplays; if U.savedLbl and S.uiC.recSaved~=sv then U.savedLbl.Text=sv;S.uiC.recSaved=sv end
        if U.trimInfoLbl then
            local total=#S.recData
            local trimmed=math.max(0,total-S.trimStart-S.trimEnd)
            U.trimInfoLbl.Text=("Trim: -%d / -%d   Result: %d frames"):format(S.trimStart,S.trimEnd,trimmed)
        end
    end)
end
updateLoopSummitUI=function()
    pcall(function()
        if U.lsStatusLbl then
            if S.lsEnabled then
                local cur=S.curSummit; local left=math.max(0,S.lsTarget-cur); local pct=math.min(100,math.floor(cur/math.max(1,S.lsTarget)*100))
                U.lsStatusLbl.Text=("Target %d  —  %d remaining  (%d%%)"):format(S.lsTarget,left,pct)
                U.lsStatusLbl.TextColor3=left==0 and C.a4 or C.a5
            else U.lsStatusLbl.Text="Off"; U.lsStatusLbl.TextColor3=C.t3 end
        end
        if U.lsToggleBtn then
            if S.lsEnabled then U.lsToggleBtn.Text="ON";U.lsToggleBtn.BackgroundColor3=C.dG
            else U.lsToggleBtn.Text="OFF";U.lsToggleBtn.BackgroundColor3=C.bg4 end
        end
    end)
end

local function setSpeed(pct)
    if S.isPlaying and not S.isPausedPlay then S.pbElapsed=calcElapsed();S.realElapsed=calcRealElapsed() end
    S.repSpeed=0.1+pct*4.9
    if S.isPlaying and not S.isPausedPlay then S.elapsedAtBase=S.pbElapsed;S.wallBase=tick() end
    pcall(function() U.sliderFill.Size=UDim2.new(math.clamp(pct,0,1),0,1,0) end)
    pcall(function() if U.speedValLbl then U.speedValLbl.Text=("%.2fx"):format(S.repSpeed) end end)
    for _,ps in ipairs(U.presetBtns) do
        local m=math.abs(ps.speed-S.repSpeed)<0.05
        tw(ps.btn,{BackgroundColor3=m and C.dG or C.bg4},0.1)
    end
    pcall(updateSummit,true)
end

S._stopReplay=stopReplay; S._playReplay=playReplay; S._startRec=startRecording
S._pauseRec=pauseRecording; S._stopRec=stopRecording; S._saveRec=saveRecording
S._saveCP=saveCP; S._tpToCP=tpToCP; S._deleteCP=deleteCP
S._updateSummit=updateSummit; S._resetSummit=resetSummit
S._mergeSelected=mergeSelected; S._updatePerf=updatePerf
S._setSpeed=setSpeed; S._saveToFile=saveToFile; S._loadFromFile=loadFromFile
S._loadFromURL=loadFromURL; S._listFiles=listFiles; S._normalizeFrame=normalizeFrame
S._fmtTime=fmtTime; S._fmtTimeDec=fmtTimeDec; S._fmtDT=fmtDT
S._cfFromData=cfFromData; S._tpTo=tpTo; S._notify=notify; S._tw=tw
S._deferGC=deferGC; S._forceGC=forceGC
S._repDuration=repDuration
S._updatePlayUI=function() updatePlayUI() end
S._updateRecUI=function() updateRecUI() end
S._updateLoopSummitUI=function() updateLoopSummitUI() end
S._toggleSmartRec=toggleSmartRec
S._updateSmartRec=updateSmartRec
S._applyTrim=applyTrim

end
initCore()

local function makeCard(lo)
    local c=Instance.new("Frame",U.content)
    c.Size=UDim2.new(1,0,0,10); c.AutomaticSize=Enum.AutomaticSize.Y
    c.BackgroundColor3=C.bg2; c.BorderSizePixel=0; c.LayoutOrder=lo
    Instance.new("UICorner",c).CornerRadius=UDim.new(0,8)
    local s=Instance.new("UIStroke",c); s.Color=C.border; s.Thickness=1; s.Transparency=0.2
    local pad=Instance.new("UIPadding",c)
    pad.PaddingLeft=UDim.new(0,12); pad.PaddingRight=UDim.new(0,12)
    pad.PaddingTop=UDim.new(0,10); pad.PaddingBottom=UDim.new(0,10)
    local ll=Instance.new("UIListLayout",c); ll.SortOrder=Enum.SortOrder.LayoutOrder; ll.Padding=UDim.new(0,6)
    return c
end
local function makeHeader(parent,txt,lo)
    local row=Instance.new("Frame",parent); row.Size=UDim2.new(1,0,0,18); row.BackgroundTransparency=1; row.LayoutOrder=lo or 0
    local tx=Instance.new("TextLabel",row); tx.Size=UDim2.new(1,0,1,0)
    tx.BackgroundTransparency=1; tx.Text=txt:upper(); tx.TextColor3=C.t3
    tx.Font=Enum.Font.GothamBold; tx.TextSize=9; tx.TextXAlignment=Enum.TextXAlignment.Left
    local div=Instance.new("Frame",parent); div.Size=UDim2.new(1,0,0,1); div.BackgroundColor3=C.border
    div.BorderSizePixel=0; div.LayoutOrder=(lo or 0)+0.5; div.BackgroundTransparency=0
end
local function makeBtn(parent,txt,clr,lo,scX)
    local btn=Instance.new("TextButton",parent)
    btn.Size=UDim2.new(scX or 1,scX and -3 or 0,0,30)
    btn.BackgroundColor3=clr; btn.Text=txt; btn.TextColor3=C.t1
    btn.Font=Enum.Font.GothamBold; btn.TextSize=11; btn.BorderSizePixel=0; btn.AutoButtonColor=false; btn.LayoutOrder=lo or 1
    Instance.new("UICorner",btn).CornerRadius=UDim.new(0,6)
    btn.MouseEnter:Connect(function() S._tw(btn,{BackgroundColor3=Color3.new(math.min(1,clr.R*1.3),math.min(1,clr.G*1.3),math.min(1,clr.B*1.3))},0.1) end)
    btn.MouseLeave:Connect(function() S._tw(btn,{BackgroundColor3=clr},0.12) end)
    return btn
end
local function makeLbl(parent,txt,clr,h,lo)
    local l=Instance.new("TextLabel",parent); l.Size=UDim2.new(1,0,0,h or 15); l.BackgroundTransparency=1
    l.Text=txt; l.TextColor3=clr or C.t2; l.Font=Enum.Font.Gotham; l.TextSize=11
    l.TextXAlignment=Enum.TextXAlignment.Left; l.LayoutOrder=lo or 2; return l
end
local function makeRow(parent,lo,h)
    local row=Instance.new("Frame",parent); row.Size=UDim2.new(1,0,0,h or 30); row.BackgroundTransparency=1; row.LayoutOrder=lo or 1
    local rl=Instance.new("UIListLayout",row); rl.FillDirection=Enum.FillDirection.Horizontal; rl.VerticalAlignment=Enum.VerticalAlignment.Center; rl.Padding=UDim.new(0,4)
    return row
end
local function makeStatBox(parent,label,initVal)
    local box=Instance.new("Frame",parent); box.Size=UDim2.new(0.5,-3,1,0); box.BackgroundColor3=C.bg3; box.BorderSizePixel=0
    Instance.new("UICorner",box).CornerRadius=UDim.new(0,6)
    local s=Instance.new("UIStroke",box); s.Color=C.border; s.Thickness=1; s.Transparency=0.3
    local lb=Instance.new("TextLabel",box); lb.Size=UDim2.new(1,-6,0,14); lb.Position=UDim2.new(0,6,0,4)
    lb.BackgroundTransparency=1; lb.Text=label; lb.TextColor3=C.t3; lb.Font=Enum.Font.GothamBold; lb.TextSize=9; lb.TextXAlignment=Enum.TextXAlignment.Left
    local val=Instance.new("TextLabel",box); val.Size=UDim2.new(1,-6,0,16); val.Position=UDim2.new(0,6,0,17)
    val.BackgroundTransparency=1; val.Text=initVal; val.TextColor3=C.t1; val.Font=Enum.Font.GothamBold; val.TextSize=15; val.TextXAlignment=Enum.TextXAlignment.Left
    return val
end
local function makeProgressBg(parent,lo,clr)
    local bg=Instance.new("Frame",parent); bg.Size=UDim2.new(1,0,0,3); bg.BackgroundColor3=C.bg4; bg.BorderSizePixel=0; bg.LayoutOrder=lo or 5
    Instance.new("UICorner",bg).CornerRadius=UDim.new(1,0)
    local bar=Instance.new("Frame",bg); bar.Size=UDim2.new(0,0,1,0); bar.BackgroundColor3=clr or C.a1; bar.BorderSizePixel=0
    Instance.new("UICorner",bar).CornerRadius=UDim.new(1,0); return bg,bar
end
local function makeScrollList(parent,lo,maxH)
    local sf=Instance.new("ScrollingFrame",parent); sf.Size=UDim2.new(1,0,0,0); sf.BackgroundTransparency=1
    sf.BorderSizePixel=0; sf.ScrollBarThickness=2; sf.ScrollBarImageColor3=C.border
    sf.CanvasSize=UDim2.new(0,0,0,0); sf.AutomaticCanvasSize=Enum.AutomaticSize.Y; sf.LayoutOrder=lo
    local il=Instance.new("UIListLayout",sf); il.SortOrder=Enum.SortOrder.LayoutOrder; il.Padding=UDim.new(0,3)
    il:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        pcall(function() local h2=math.min(maxH or 200,il.AbsoluteContentSize.Y+4); sf.Size=UDim2.new(1,0,0,h2); sf.CanvasSize=UDim2.new(0,0,0,il.AbsoluteContentSize.Y+4) end)
    end)
    return sf
end
local function makeTBox(parent,ph,lo,w)
    local tb=Instance.new("TextBox",parent); tb.Size=UDim2.new(w or 1,w and -3 or 0,0,30)
    tb.BackgroundColor3=C.bg3; tb.Text=""; tb.TextColor3=C.t1; tb.Font=Enum.Font.Gotham; tb.TextSize=11
    tb.PlaceholderText=ph or ""; tb.PlaceholderColor3=C.t3; tb.BorderSizePixel=0; tb.ClearTextOnFocus=false; tb.LayoutOrder=lo or 1
    Instance.new("UICorner",tb).CornerRadius=UDim.new(0,6)
    local p=Instance.new("UIPadding",tb); p.PaddingLeft=UDim.new(0,8)
    local st=Instance.new("UIStroke",tb); st.Color=C.border; st.Thickness=1; st.Transparency=0.2
    tb.Focused:Connect(function() S._tw(st,{Color=C.a2,Transparency=0},0.15) end)
    tb.FocusLost:Connect(function() S._tw(st,{Color=C.border,Transparency=0.2},0.15) end)
    return tb
end

local function setupGUI()
    local gp = pl:WaitForChild("PlayerGui")
    pcall(function() local old=gp:FindFirstChild("MTP5"); if old then old:Destroy() end end)

    U.sg=Instance.new("ScreenGui"); U.sg.Name="MTP5"; U.sg.ResetOnSpawn=false
    U.sg.ZIndexBehavior=Enum.ZIndexBehavior.Sibling; U.sg.Parent=gp

    U.win=Instance.new("Frame"); U.win.Name="Win"; U.win.Size=UDim2.new(0,S.WIN_W,0,36)
    U.win.Position=UDim2.new(0,10,0,45); U.win.BackgroundColor3=C.bg1
    U.win.BorderSizePixel=0; U.win.Active=true; U.win.ClipsDescendants=true; U.win.Parent=U.sg
    Instance.new("UICorner",U.win).CornerRadius=UDim.new(0,10)
    local ws=Instance.new("UIStroke",U.win); ws.Color=C.border; ws.Thickness=1; ws.Transparency=0

    local tb=Instance.new("Frame",U.win); tb.Name="TitleBar"; tb.Size=UDim2.new(1,0,0,36)
    tb.BackgroundColor3=C.tb; tb.BorderSizePixel=0; tb.ZIndex=5
    Instance.new("UICorner",tb).CornerRadius=UDim.new(0,10)
    local cov=Instance.new("Frame",tb); cov.Size=UDim2.new(1,0,0,10); cov.Position=UDim2.new(0,0,1,-10)
    cov.BackgroundColor3=C.tb; cov.BorderSizePixel=0; cov.ZIndex=4

local tl=Instance.new("TextLabel",tb)
tl.Size=UDim2.new(1,-80,1,0)
tl.Position=UDim2.new(0,14,0,0)
tl.BackgroundTransparency=1
tl.Text="HAZEL PATH"
tl.TextColor3=C.t1
tl.Font=Enum.Font.GothamBold
tl.TextSize=12
tl.TextXAlignment=Enum.TextXAlignment.Left
tl.ZIndex=6

local vl=Instance.new("TextLabel",tb)
vl.Size=UDim2.new(0,40,1,0)
vl.Position=UDim2.new(0,128,0,0)
vl.BackgroundTransparency=1
vl.Text="v1.5"
vl.TextColor3=C.t3
vl.Font=Enum.Font.Gotham
vl.TextSize=10
vl.TextXAlignment=Enum.TextXAlignment.Left
vl.ZIndex=6

    local function mkWB(t,x,bg)
        local b=Instance.new("TextButton",tb); b.Size=UDim2.new(0,24,0,20); b.Position=UDim2.new(1,x,0.5,-10)
        b.BackgroundColor3=bg; b.Text=t; b.TextColor3=C.t2; b.Font=Enum.Font.GothamBold; b.TextSize=12; b.BorderSizePixel=0; b.ZIndex=7
        Instance.new("UICorner",b).CornerRadius=UDim.new(0,5); return b
    end
    local minBtn=mkWB("—",-58,C.bg4); local closeBtn=mkWB("×",-30,C.bg4)

    tb.InputBegan:Connect(function(inp)
        if inp.UserInputType~=Enum.UserInputType.MouseButton1 then return end
        S.isDragging=true; S.dragStart=inp.Position; S.startPos=U.win.Position
        inp.Changed:Connect(function() if inp.UserInputState==Enum.UserInputState.End then S.isDragging=false end end)
    end)
    minBtn.MouseButton1Click:Connect(function()
        S.isMinimized=not S.isMinimized
        if S.isMinimized then S._tw(U.win,{Size=UDim2.new(0,S.WIN_W,0,36)},0.25,Enum.EasingStyle.Quart); U.content.Visible=false; minBtn.Text="+"
        else S._tw(U.win,{Size=UDim2.new(0,S.WIN_W,0,S.WIN_H)},0.25,Enum.EasingStyle.Quart); U.content.Visible=true; minBtn.Text="—" end
    end)
    closeBtn.MouseButton1Click:Connect(function()
        if S.isPlaying then S._stopReplay() end; if S.isRec then S._stopRec() end
        pcall(function() if S.hum then S.hum.WalkSpeed=16 end end)
        S._tw(U.win,{Size=UDim2.new(0,0,0,0)},0.18)
        task.delay(0.22,function() pcall(function() U.sg:Destroy() end) end); S._forceGC()
    end)

    local RS2=game:GetService("RunService")
    RS2.RenderStepped:Connect(function()
        if not S.isDragging then return end
        pcall(function() local mp=UIS:GetMouseLocation(); local d=mp-Vector2.new(S.dragStart.X,S.dragStart.Y)
            U.win.Position=UDim2.new(S.startPos.X.Scale,S.startPos.X.Offset+d.X,S.startPos.Y.Scale,S.startPos.Y.Offset+d.Y) end)
    end)

    U.content=Instance.new("ScrollingFrame",U.win); U.content.Name="Content"; U.content.Size=UDim2.new(1,-4,1,-42)
    U.content.Position=UDim2.new(0,2,0,40); U.content.BackgroundTransparency=1; U.content.BorderSizePixel=0
    U.content.ScrollBarThickness=2; U.content.ScrollBarImageColor3=C.border
    U.content.CanvasSize=UDim2.new(0,0,0,2000); U.content.AutomaticCanvasSize=Enum.AutomaticSize.Y
    local cl=Instance.new("UIListLayout",U.content); cl.SortOrder=Enum.SortOrder.LayoutOrder; cl.Padding=UDim.new(0,4)
    cl:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function() pcall(function() U.content.CanvasSize=UDim2.new(0,0,0,cl.AbsoluteContentSize.Y+20) end) end)
    local cp=Instance.new("UIPadding",U.content); cp.PaddingTop=UDim.new(0,4); cp.PaddingBottom=UDim.new(0,14); cp.PaddingLeft=UDim.new(0,4); cp.PaddingRight=UDim.new(0,4)
end
setupGUI()

local function buildCard1()
    local c=makeCard(1); makeHeader(c,"Performance",0)
    local row=makeRow(c,2,44); row.Size=UDim2.new(1,0,0,44)
    U.fpsLbl=makeStatBox(row,"FPS","60")
    U.memLbl=makeStatBox(row,"RAM","0 MB")
end

local function buildCard2()
    local c=makeCard(2); makeHeader(c,"Recording",0)
    local r1=makeRow(c,2)
    U.startBtn=makeBtn(r1,"⏺  RECORD",C.dR,0,0.5)
    U.stopRecBtn=makeBtn(r1,"⏹  STOP",C.bg4,0,0.5)
    local r2=makeRow(c,3)
    U.smartRecBtn=makeBtn(r2,"SMART REC",C.bg4,0,0.5)
    U.saveBtn=makeBtn(r2,"💾  SAVE",C.dG,0,0.5)
    U.smartStatusLbl=makeLbl(c,"Off",C.t3,13,4)
    local sep=Instance.new("Frame",c); sep.Size=UDim2.new(1,0,0,1); sep.BackgroundColor3=C.border; sep.BorderSizePixel=0; sep.LayoutOrder=5
    makeLbl(c,"TRIM",C.t3,12,6).Font=Enum.Font.GothamBold
    local tr=makeRow(c,7)
    local trimSLbl=makeLbl(tr,"Start",C.t3,30,0); trimSLbl.Size=UDim2.new(0,32,1,0)
    U.trimStartBox=makeTBox(tr,"0",0,0.4); U.trimStartBox.Text="0"
    local trimELbl=makeLbl(tr,"End",C.t3,30,0); trimELbl.Size=UDim2.new(0,28,1,0)
    U.trimEndBox=makeTBox(tr,"0",0,0.4); U.trimEndBox.Text="0"
    U.trimInfoLbl=makeLbl(c,"Trim: -0 / -0   Result: 0 frames",C.t3,13,8)
    U.statusLbl=makeLbl(c,"Status: Ready",C.a4,14,9)
    U.frameLbl=makeLbl(c,"Frames: 0",C.t2,13,10)
    U.posLbl=makeLbl(c,"—",C.t3,12,11)
    U.savedLbl=makeLbl(c,"Saved: 0",C.t3,12,12)
end

local function buildCard3()
    local c=makeCard(3); makeHeader(c,"File IO",0)
    local r1=makeRow(c,2)
    local saveFileBtn=makeBtn(r1,"Save File",C.bg4,0,0.5)
    local refreshBtn=makeBtn(r1,"Refresh",C.bg4,0,0.5)
    local r2=makeRow(c,3)
    local loadListBtn=makeBtn(r2,"Load → List",C.bg4,0,1)
    makeLbl(c,"Load from URL",C.t3,12,4)
    local ur=makeRow(c,5)
    U.urlBox=makeTBox(ur,"https://pastebin.com/raw/...",0,0.75)
    U.urlLoadBtn=makeBtn(ur,"Load",C.dB,0,0.25)
    U.urlStatusLbl=makeLbl(c,"",C.t3,12,6)
    U.fileListScroll=makeScrollList(c,7,140)
    U.fileStatusLbl=makeLbl(c,S.SAVE_FOLDER,C.t3,12,8)

    local function doRefresh()
        for _,ch in ipairs(U.fileListScroll:GetChildren()) do if ch:IsA("Frame") then ch:Destroy() end end
        local files=S._listFiles()
        for idx,fi in ipairs(files) do
            local item=Instance.new("Frame",U.fileListScroll); item.Size=UDim2.new(1,0,0,28); item.BackgroundColor3=C.bg3; item.BorderSizePixel=0; item.LayoutOrder=idx
            Instance.new("UICorner",item).CornerRadius=UDim.new(0,6)
            local nL=Instance.new("TextLabel",item); nL.Size=UDim2.new(1,-118,1,0); nL.Position=UDim2.new(0,8,0,0); nL.BackgroundTransparency=1; nL.Text=fi.name; nL.TextColor3=C.t1; nL.Font=Enum.Font.Gotham; nL.TextSize=10; nL.TextXAlignment=Enum.TextXAlignment.Left; nL.TextTruncate=Enum.TextTruncate.AtEnd
            local function mkFB(t,clr,xOff) local b=Instance.new("TextButton",item); b.Size=UDim2.new(0,52,0,20); b.Position=UDim2.new(1,xOff,0.5,-10); b.BackgroundColor3=clr; b.Text=t; b.TextColor3=C.t1; b.Font=Enum.Font.GothamBold; b.TextSize=10; b.BorderSizePixel=0; Instance.new("UICorner",b).CornerRadius=UDim.new(0,5); return b end
            local loadB=mkFB("Load",C.dB,-116); local addB=mkFB("→ List",C.bg4,-60)
            local fp,fn=fi.path,fi.name
            loadB.MouseButton1Click:Connect(function() local d=S._loadFromFile(fp); if d then S.repData=d; S._notify("Loaded",fn.." → "..#d.." frames"); pcall(function() if U.repStatusLbl then U.repStatusLbl.Text="File: "..fn end end); S._updatePlayUI() end end)
            addB.MouseButton1Click:Connect(function() local d=S._loadFromFile(fp); if d then S.repCounter=S.repCounter+1; table.insert(S.savedReplays,{name="[F]"..fn,data=d,frames=#d,time=os.time()}); S._notify("Added",fn); S._updateRecUI() end end)
        end
        pcall(function() if U.fileStatusLbl then U.fileStatusLbl.Text=S.SAVE_FOLDER.."  ("..#files..")" end end)
    end

    U.urlLoadBtn.MouseButton1Click:Connect(function()
        local url=U.urlBox.Text
        if url=="" then S._notify("Error","Enter a URL"); return end
        pcall(function() if U.urlStatusLbl then U.urlStatusLbl.Text="Loading..." end end)
        task.spawn(function()
            local d=S._loadFromURL(url)
            if d then
                S.repData=d
                S._notify("Loaded","URL → "..#d.." frames")
                pcall(function() if U.repStatusLbl then U.repStatusLbl.Text="URL loaded  "..#d.."f" end end)
                pcall(function() if U.urlStatusLbl then U.urlStatusLbl.Text="Loaded  "..#d.." frames" end end)
                S._updatePlayUI()
            else
                pcall(function() if U.urlStatusLbl then U.urlStatusLbl.Text="Failed to load" end end)
            end
        end)
    end)
    saveFileBtn.MouseButton1Click:Connect(function() local d=S.repData or S.recData; if not d or #d==0 then S._notify("Error","No data!"); return end; S._saveToFile("Replay_"..os.time(),d); pcall(doRefresh) end)
    refreshBtn.MouseButton1Click:Connect(function() pcall(doRefresh) end)
    loadListBtn.MouseButton1Click:Connect(function() pcall(doRefresh) end)
    task.delay(0.8,function() pcall(doRefresh) end)
end

local function buildCard4()
    local c=makeCard(4); makeHeader(c,"Checkpoints",0)
    local cpRow=makeRow(c,2)
    local saveCpBtn=makeBtn(cpRow,"+ Save Checkpoint",C.bg4,0,1)
    local cpScroll=makeScrollList(c,3,180)
    local cpEmptyLbl=makeLbl(c,"No checkpoints",C.t3,13,4)
    U.refreshCPList=function()
        for _,ch in ipairs(cpScroll:GetChildren()) do if ch:IsA("Frame") then ch:Destroy() end end
        cpEmptyLbl.Visible=#S.checkpoints==0
        for idx,cp in ipairs(S.checkpoints) do
            local item=Instance.new("Frame",cpScroll); item.Size=UDim2.new(1,0,0,28); item.BackgroundColor3=C.bg3; item.BorderSizePixel=0; item.LayoutOrder=idx
            Instance.new("UICorner",item).CornerRadius=UDim.new(0,6)
            local nL=Instance.new("TextLabel",item); nL.Size=UDim2.new(1,-108,1,0); nL.Position=UDim2.new(0,8,0,0); nL.BackgroundTransparency=1
            nL.Text=("%s  %.0f,%.0f,%.0f"):format(cp.name,cp.cf.X,cp.cf.Y,cp.cf.Z); nL.TextColor3=C.t1; nL.Font=Enum.Font.Gotham; nL.TextSize=10; nL.TextXAlignment=Enum.TextXAlignment.Left; nL.TextTruncate=Enum.TextTruncate.AtEnd
            local tpB=Instance.new("TextButton",item); tpB.Size=UDim2.new(0,38,0,20); tpB.Position=UDim2.new(1,-104,0.5,-10); tpB.BackgroundColor3=C.dB; tpB.Text="TP"; tpB.TextColor3=C.t1; tpB.Font=Enum.Font.GothamBold; tpB.TextSize=10; tpB.BorderSizePixel=0; Instance.new("UICorner",tpB).CornerRadius=UDim.new(0,5)
            local dtL=Instance.new("TextLabel",item); dtL.Size=UDim2.new(0,48,0,20); dtL.Position=UDim2.new(1,-62,0.5,-10); dtL.BackgroundTransparency=1; dtL.Text=S._fmtDT(cp.time); dtL.TextColor3=C.t3; dtL.Font=Enum.Font.Gotham; dtL.TextSize=9; dtL.TextXAlignment=Enum.TextXAlignment.Right
            local delB=Instance.new("TextButton",item); delB.Size=UDim2.new(0,20,0,20); delB.Position=UDim2.new(1,-22,0.5,-10); delB.BackgroundColor3=C.bg4; delB.Text="×"; delB.TextColor3=C.t3; delB.Font=Enum.Font.GothamBold; delB.TextSize=13; delB.BorderSizePixel=0; Instance.new("UICorner",delB).CornerRadius=UDim.new(0,5)
            local ci=idx; tpB.MouseButton1Click:Connect(function() S._tpToCP(ci) end); delB.MouseButton1Click:Connect(function() S._deleteCP(ci) end)
        end
    end
    U.refreshCPList()
    saveCpBtn.MouseButton1Click:Connect(S._saveCP)
end

local function buildCard5()
    local c=makeCard(5); makeHeader(c,"Saved Replays",0)
    local selRow=makeRow(c,2)
    U.selAllBtn=makeBtn(selRow,"All",C.bg4,0,0.25)
    U.selNoneBtn=makeBtn(selRow,"None",C.bg4,0,0.25)
    U.delSelBtn=makeBtn(selRow,"Delete",C.dR,0,0.25)
    U.listToggleBtn=makeBtn(selRow,"▾ Show",C.bg4,0,0.25)
    U.listScroll=makeScrollList(c,3,270); U.listScroll.Visible=false
    U.refreshRepList=function()
        for _,ch in ipairs(U.listScroll:GetChildren()) do if ch:IsA("Frame") then ch:Destroy() end end
        for idx,rep in ipairs(S.savedReplays) do
            local isSel=S.selectedMerge[idx] or false
            local isDel=S.selectedDelete[idx] or false
            local item=Instance.new("Frame",U.listScroll); item.Size=UDim2.new(1,0,0,52)
            item.BackgroundColor3=isSel and Color3.fromRGB(18,22,36) or C.bg3; item.BorderSizePixel=0; item.LayoutOrder=idx
            Instance.new("UICorner",item).CornerRadius=UDim.new(0,7)
            if isSel then local s=Instance.new("UIStroke",item); s.Color=C.a2; s.Thickness=1; s.Transparency=0.4 end

            local chk=Instance.new("TextButton",item)
            chk.Size=UDim2.new(0,20,0,20); chk.Position=UDim2.new(0,4,0.5,-10)
            chk.BackgroundColor3=isSel and C.dB or C.bg4
            chk.Text=isSel and "✓" or ""; chk.TextColor3=C.t1; chk.Font=Enum.Font.GothamBold; chk.TextSize=11; chk.BorderSizePixel=0
            Instance.new("UICorner",chk).CornerRadius=UDim.new(0,4)

            local dchk=Instance.new("TextButton",item)
            dchk.Size=UDim2.new(0,16,0,16); dchk.Position=UDim2.new(1,-20,0,4)
            dchk.BackgroundColor3=isDel and C.dR or C.bg4
            dchk.Text=isDel and "×" or "·"; dchk.TextColor3=isDel and C.t1 or C.t3
            dchk.Font=Enum.Font.GothamBold; dchk.TextSize=isDel and 12 or 14; dchk.BorderSizePixel=0
            Instance.new("UICorner",dchk).CornerRadius=UDim.new(0,3)

            local nL=Instance.new("TextLabel",item); nL.Size=UDim2.new(1,-148,0,20); nL.Position=UDim2.new(0,28,0,4); nL.BackgroundTransparency=1; nL.Text=rep.name; nL.TextColor3=isSel and C.a1 or C.t1; nL.Font=Enum.Font.GothamBold; nL.TextSize=11; nL.TextXAlignment=Enum.TextXAlignment.Left
            local iL=Instance.new("TextLabel",item); iL.Size=UDim2.new(1,-148,0,14); iL.Position=UDim2.new(0,28,0,25); iL.BackgroundTransparency=1; iL.Text=rep.frames.."f  ·  "..S._fmtDT(rep.time); iL.TextColor3=C.t3; iL.Font=Enum.Font.Gotham; iL.TextSize=10; iL.TextXAlignment=Enum.TextXAlignment.Left
            local function mkIB(t,clr,xOff,yOff) local b=Instance.new("TextButton",item); b.Size=UDim2.new(0,52,0,20); b.Position=UDim2.new(1,xOff,0,yOff); b.BackgroundColor3=clr; b.Text=t; b.TextColor3=C.t1; b.Font=Enum.Font.GothamBold; b.TextSize=10; b.BorderSizePixel=0; Instance.new("UICorner",b).CornerRadius=UDim.new(0,5); return b end
            local playB=mkIB("▶ Play",C.dG,-114,5)
            local tpEB=mkIB("TP End",C.bg4,-114,28)
            local savFB=mkIB("Save",C.bg4,-58,5)
            local loopB=mkIB("Loop",C.bg4,-58,28)
            local ci=idx
            chk.MouseButton1Click:Connect(function()
                S.selectedMerge[ci]=not(S.selectedMerge[ci] or false); U.refreshRepList()
                local n=0; for _,v in pairs(S.selectedMerge) do if v then n=n+1 end end
                pcall(function() if U.multiRepLbl then U.multiRepLbl.Text=n>0 and(n.." selected") or "Select to merge" end end)
            end)
            dchk.MouseButton1Click:Connect(function()
                S.selectedDelete[ci]=not(S.selectedDelete[ci] or false); U.refreshRepList()
            end)
            playB.MouseButton1Click:Connect(function()
                S.repData=rep.data; S._notify("Loaded",rep.name)
                pcall(function() if U.repStatusLbl then U.repStatusLbl.Text="Loaded: "..rep.name end end)
                S._playReplay(rep.data)
            end)
            loopB.MouseButton1Click:Connect(function()
                S.repData=rep.data; S.isLooping=true
                U.loopBtn.Text="⟳  LOOP ON"; S._tw(U.loopBtn,{BackgroundColor3=C.dG},0.1)
                S._notify("Loop","Loop ON — "..rep.name); S._playReplay(rep.data)
            end)
            tpEB.MouseButton1Click:Connect(function() local fd=rep.data[#rep.data]; if fd and fd.cfd then local ok,cf=pcall(S._cfFromData,fd.cfd); if ok then S._tpTo(cf); S._notify("TP","End of "..rep.name) end end end)
            savFB.MouseButton1Click:Connect(function() S._saveToFile(rep.name,rep.data) end)
        end
    end
    U.listToggleBtn.MouseButton1Click:Connect(function() local vis=not U.listScroll.Visible; U.listScroll.Visible=vis; if vis then U.refreshRepList() end; U.listToggleBtn.Text=vis and "▴ Hide" or "▾ Show" end)
    U.selAllBtn.MouseButton1Click:Connect(function()
        S.selectedMerge={};S.selectedDelete={}
        for i=1,#S.savedReplays do S.selectedMerge[i]=true;S.selectedDelete[i]=true end
        pcall(U.refreshRepList)
        pcall(function() if U.multiRepLbl then U.multiRepLbl.Text=#S.savedReplays.." selected" end end)
    end)
    U.selNoneBtn.MouseButton1Click:Connect(function()
        S.selectedMerge={};S.selectedDelete={}
        pcall(U.refreshRepList)
        pcall(function() if U.multiRepLbl then U.multiRepLbl.Text="Select to merge" end end)
    end)
    U.delSelBtn.MouseButton1Click:Connect(function()
        local toDel={}
        for idx,v in pairs(S.selectedDelete) do if v and S.savedReplays[idx] then table.insert(toDel,idx) end end
        if #toDel==0 then S._notify("Info","Mark replays with × first"); return end
        table.sort(toDel,function(a,b) return a>b end)
        for _,idx in ipairs(toDel) do table.remove(S.savedReplays,idx) end
        S.selectedDelete={};S.selectedMerge={}
        S._notify("Deleted",#toDel.." replay(s)")
        pcall(U.refreshRepList); S._updateRecUI(); S._deferGC()
    end)
end

local function buildCard6()
    local c=makeCard(6); makeHeader(c,"Merge",0)
    U.multiRepLbl=makeLbl(c,"Select to merge",C.t3,13,1)
    local r1=makeRow(c,2)
    U.mergePBtn=makeBtn(r1,"▶ Play",C.dG,0,0.34)
    U.mergeLBtn=makeBtn(r1,"⟳ Loop",C.bg4,0,0.33)
    U.mergeSBtn=makeBtn(r1,"💾 Save",C.dB,0,0.33)
end

local function buildCard7()
    local c=makeCard(7); makeHeader(c,"Playback",0)
    local r1=makeRow(c,2)
    local clrBtn=makeBtn(r1,"Clear",C.bg4,0,0.5)
    local r1b=makeRow(c,3); r1b.Size=UDim2.new(1,0,0,30)
    local tpSBtn=makeBtn(r1b,"⏮ Start",C.bg4,0,0.5); local tpEBtn=makeBtn(r1b,"⏭ End",C.bg4,0,0.5)
    local r2=makeRow(c,4)
    U.playPauseBtn=makeBtn(r2,"▶  PLAY",C.dG,0,0.38)
    U.stopPlayBtn=makeBtn(r2,"⏹  STOP",C.dR,0,0.3)
    U.loopBtn=makeBtn(r2,"⟳  LOOP",C.bg4,0,0.32)

    local shr=makeRow(c,5,18); shr.Size=UDim2.new(1,0,0,18)
    local spLbl=Instance.new("TextLabel",shr); spLbl.Size=UDim2.new(0.6,0,1,0); spLbl.BackgroundTransparency=1; spLbl.Text="SPEED"; spLbl.TextColor3=C.t3; spLbl.Font=Enum.Font.GothamBold; spLbl.TextSize=9; spLbl.TextXAlignment=Enum.TextXAlignment.Left;
    U.speedValLbl=Instance.new("TextLabel",shr); U.speedValLbl.Size=UDim2.new(0.4,0,1,0); U.speedValLbl.BackgroundTransparency=1; U.speedValLbl.Text="1.00×"; U.speedValLbl.TextColor3=C.a1; U.speedValLbl.Font=Enum.Font.GothamBold; U.speedValLbl.TextSize=12; U.speedValLbl.TextXAlignment=Enum.TextXAlignment.Right

    local sw=Instance.new("Frame",c); sw.Size=UDim2.new(1,0,0,16); sw.BackgroundTransparency=1; sw.LayoutOrder=6
    U.sliderBg=Instance.new("Frame",sw); U.sliderBg.Size=UDim2.new(1,0,0,3); U.sliderBg.Position=UDim2.new(0,0,0.5,-1.5); U.sliderBg.BackgroundColor3=C.bg4; U.sliderBg.BorderSizePixel=0
    Instance.new("UICorner",U.sliderBg).CornerRadius=UDim.new(1,0)
    U.sliderFill=Instance.new("Frame",U.sliderBg); U.sliderFill.Size=UDim2.new(0.184,0,1,0); U.sliderFill.BackgroundColor3=C.a2; U.sliderFill.BorderSizePixel=0
    Instance.new("UICorner",U.sliderFill).CornerRadius=UDim.new(1,0)
    local sh=Instance.new("TextButton",U.sliderFill); sh.Size=UDim2.new(0,12,0,12); sh.Position=UDim2.new(1,-6,0.5,-6); sh.BackgroundColor3=C.a1; sh.Text=""; sh.BorderSizePixel=0; sh.ZIndex=3; Instance.new("UICorner",sh).CornerRadius=UDim.new(1,0)
    sh.MouseButton1Down:Connect(function() S.draggingSpeed=true end)

    local pr=makeRow(c,7)
    for _,ps in ipairs({{0.25,"×0.25"},{0.5,"×0.5"},{1.0,"×1"},{2.0,"×2"},{3.0,"×3"}}) do
        local pb=makeBtn(pr,ps[2],ps[1]==1.0 and C.dG or C.bg4,0,0.19)
        table.insert(U.presetBtns,{btn=pb,speed=ps[1]})
    end

    local _,rpb=makeProgressBg(c,8,C.a2); U.progressBar=rpb
    U.repStatusLbl=makeLbl(c,"No data",C.t3,13,9)
    U.framesLbl=makeLbl(c,"—",C.t3,12,10)
    U.pbInfoLbl=makeLbl(c,"—",C.t2,13,11)

    clrBtn.MouseButton1Click:Connect(function() S.repData=nil;S.curFrame=1;S.lastPlayFrame=0; if S.isPlaying then S._stopReplay() end; pcall(function() if U.repStatusLbl then U.repStatusLbl.Text="Cleared" end end); S._updatePlayUI(); S._notify("Cleared","Data removed"); S._deferGC() end)
    tpSBtn.MouseButton1Click:Connect(function() if not S.repData or #S.repData==0 then S._notify("Error","No data"); return end; local fd=S.repData[1]; if fd and fd.cfd then local ok,cf=pcall(S._cfFromData,fd.cfd); if ok then S._tpTo(cf) end end; S._notify("TP","Start") end)
    tpEBtn.MouseButton1Click:Connect(function() if not S.repData or #S.repData==0 then S._notify("Error","No data"); return end; local fd=S.repData[#S.repData]; if fd and fd.cfd then local ok,cf=pcall(S._cfFromData,fd.cfd); if ok then S._tpTo(cf) end end; S._notify("TP","End") end)
end

local function buildCard8()
    local c=makeCard(8); makeHeader(c,"Summit Tracker",0)
    U.summitInfoLbl=makeLbl(c,"0  (+0)",C.t1,22,2); U.summitInfoLbl.Font=Enum.Font.GothamBold; U.summitInfoLbl.TextSize=20
    U.summitRateLbl=makeLbl(c,"0.0 / min   Loops: 0",C.t3,13,3)
    local sr=makeRow(c,4)
    local refBtn=makeBtn(sr,"Refresh",C.bg4,0,0.5); local rstBtn=makeBtn(sr,"Reset",C.bg4,0,0.5)
    local tr=makeRow(c,5)
    local tgtBox=makeTBox(tr,"Target...",0,0.7); tgtBox.Text="1000"
    local setBtn=makeBtn(tr,"Set",C.dG,0,0.3)
    local si=makeRow(c,6,16); si.Size=UDim2.new(1,0,0,16)
    U.summitLeftLbl=Instance.new("TextLabel",si); U.summitLeftLbl.Size=UDim2.new(0.5,0,1,0); U.summitLeftLbl.BackgroundTransparency=1; U.summitLeftLbl.Text="Remaining: —"; U.summitLeftLbl.TextColor3=C.a5; U.summitLeftLbl.Font=Enum.Font.Gotham; U.summitLeftLbl.TextSize=11; U.summitLeftLbl.TextXAlignment=Enum.TextXAlignment.Left
    U.pctLbl=Instance.new("TextLabel",si); U.pctLbl.Size=UDim2.new(0.5,0,1,0); U.pctLbl.BackgroundTransparency=1; U.pctLbl.Text="0%"; U.pctLbl.TextColor3=C.t3; U.pctLbl.Font=Enum.Font.Gotham; U.pctLbl.TextSize=11; U.pctLbl.TextXAlignment=Enum.TextXAlignment.Right
    local si2=makeRow(c,7,16); si2.Size=UDim2.new(1,0,0,16)
    U.etaLbl=Instance.new("TextLabel",si2); U.etaLbl.Size=UDim2.new(0.5,0,1,0); U.etaLbl.BackgroundTransparency=1; U.etaLbl.Text="ETA  —"; U.etaLbl.TextColor3=C.a2; U.etaLbl.Font=Enum.Font.GothamBold; U.etaLbl.TextSize=11; U.etaLbl.TextXAlignment=Enum.TextXAlignment.Left
    U.doneLbl=Instance.new("TextLabel",si2); U.doneLbl.Size=UDim2.new(0.5,0,1,0); U.doneLbl.BackgroundTransparency=1; U.doneLbl.Text="Done  —"; U.doneLbl.TextColor3=C.t3; U.doneLbl.Font=Enum.Font.Gotham; U.doneLbl.TextSize=11; U.doneLbl.TextXAlignment=Enum.TextXAlignment.Right
    local _,spb=makeProgressBg(c,8,C.a5); U.summitBar=spb

    local sep2=Instance.new("Frame",c); sep2.Size=UDim2.new(1,0,0,1); sep2.BackgroundColor3=C.border; sep2.BorderSizePixel=0; sep2.LayoutOrder=9
    makeLbl(c,"LOOP STOP TARGET",C.t3,12,10).Font=Enum.Font.GothamBold
    U.lsStatusLbl=makeLbl(c,"Off",C.t3,13,11)
    local lr=makeRow(c,12)
    U.lsToggleBtn=makeBtn(lr,"OFF",C.bg4,0,0.28)
    U.lsTargetBox=makeTBox(lr,"Summit target...",0,0.72); U.lsTargetBox.Text="0"
    local lr2=makeRow(c,13)
    local lsSetBtn=makeBtn(lr2,"Set Target",C.dG,0,0.5)
    local lsRstBtn=makeBtn(lr2,"Reset",C.bg4,0,0.5)

    refBtn.MouseButton1Click:Connect(function() S._updateSummit(true) end)
    rstBtn.MouseButton1Click:Connect(S._resetSummit)
    setBtn.MouseButton1Click:Connect(function() local n=tonumber(tgtBox.Text); if n and n>0 then S.summitTarget=n;S._updateSummit(true);S._notify("Target","Target: "..n) else S._notify("Error","Invalid number!") end end)
    lsSetBtn.MouseButton1Click:Connect(function()
        local n=tonumber(U.lsTargetBox.Text)
        if n and n>0 then S.lsTarget=n; S._notify("Loop Target","Stop at summit "..n); S._updateLoopSummitUI()
        else S._notify("Error","Enter a valid number!") end
    end)
    lsRstBtn.MouseButton1Click:Connect(function() S.lsTarget=0;S.lsEnabled=false;S.lsReached=false; U.lsTargetBox.Text="0"; S._updateLoopSummitUI(); S._notify("Reset","Loop target reset") end)
    U.lsToggleBtn.MouseButton1Click:Connect(function()
        if S.lsTarget<=0 then S._notify("Error","Set a target first!"); return end
        S.lsEnabled=not S.lsEnabled; S.lsReached=false; S._updateLoopSummitUI()
        if S.lsEnabled then S._notify("ON","Auto stop at "..S.lsTarget.." summit")
        else S._notify("OFF","Auto stop disabled") end
    end)
    S._updateLoopSummitUI()
end

buildCard1(); buildCard2(); buildCard3(); buildCard4(); buildCard5()
buildCard6(); buildCard7(); buildCard8()

U.startBtn.MouseButton1Click:Connect(function() if S.isRec and not S.isPausedRec then S._pauseRec() else S._startRec() end end)
U.stopRecBtn.MouseButton1Click:Connect(S._stopRec)
U.saveBtn.MouseButton1Click:Connect(function()
    local ts=tonumber(U.trimStartBox.Text) or 0
    local te=tonumber(U.trimEndBox.Text) or 0
    S.trimStart=math.max(0,math.floor(ts))
    S.trimEnd=math.max(0,math.floor(te))
    S._saveRec()
    pcall(function() if U.listScroll.Visible then U.refreshRepList() end end)
end)
U.smartRecBtn.MouseButton1Click:Connect(S._toggleSmartRec)
U.playPauseBtn.MouseButton1Click:Connect(function() S._playReplay() end)
U.stopPlayBtn.MouseButton1Click:Connect(S._stopReplay)
U.loopBtn.MouseButton1Click:Connect(function()
    S.isLooping=not S.isLooping; U.loopBtn.Text=S.isLooping and "⟳  LOOP ON" or "⟳  LOOP"
    S._tw(U.loopBtn,{BackgroundColor3=S.isLooping and C.dG or C.bg4},0.15)
    S._notify("Loop",S.isLooping and "ON" or "OFF")
end)
U.mergePBtn.MouseButton1Click:Connect(function()
    local m=S._mergeSelected(); if not m then return end
    S.isLooping=false; U.loopBtn.Text="⟳  LOOP"; S._tw(U.loopBtn,{BackgroundColor3=C.bg4},0.1)
    S.repData=m; S._updatePlayUI(); S._playReplay(m)
end)
U.mergeLBtn.MouseButton1Click:Connect(function()
    local m=S._mergeSelected(); if not m then return end
    S.isLooping=true; U.loopBtn.Text="⟳  LOOP ON"; S._tw(U.loopBtn,{BackgroundColor3=C.dG},0.1)
    S.repData=m; S._updatePlayUI(); S._playReplay(m)
end)
U.mergeSBtn.MouseButton1Click:Connect(function()
    local m=S._mergeSelected(); if not m then return end
    local name="Merged_"..S.repCounter; S.repCounter=S.repCounter+1
    table.insert(S.savedReplays,{name=name,data=m,frames=#m,time=os.time()})
    S._notify("Saved",name.." ("..#m.." frames)"); S._updateRecUI()
    pcall(function() if U.listScroll.Visible then U.refreshRepList() end end)
end)

UIS.InputEnded:Connect(function(inp) if inp.UserInputType==Enum.UserInputType.MouseButton1 then S.draggingSpeed=false end end)
local _lastFT=tick()
game:GetService("RunService").RenderStepped:Connect(function()
    local now=tick(); _lastFT=now
    if not S.draggingSpeed then return end
    pcall(function() local mp=UIS:GetMouseLocation(); local sp=U.sliderBg.AbsolutePosition; local ss=U.sliderBg.AbsoluteSize; S._setSpeed(math.clamp((mp.X-sp.X)/ss.X,0,1)) end)
end)
for _,ps in ipairs(U.presetBtns) do
    ps.btn.MouseButton1Click:Connect(function() S._setSpeed((ps.speed-0.1)/4.9) end)
end

U.trimStartBox.FocusLost:Connect(function()
    local v=tonumber(U.trimStartBox.Text) or 0; S.trimStart=math.max(0,math.floor(v))
    U.trimStartBox.Text=tostring(S.trimStart); S._updateRecUI()
end)
U.trimEndBox.FocusLost:Connect(function()
    local v=tonumber(U.trimEndBox.Text) or 0; S.trimEnd=math.max(0,math.floor(v))
    U.trimEndBox.Text=tostring(S.trimEnd); S._updateRecUI()
end)

UIS.InputBegan:Connect(function(inp,gp)
    if gp then return end; local k=inp.KeyCode
    if k==Enum.KeyCode.R then if S.isRec and not S.isPausedRec then S._pauseRec() else S._startRec() end
    elseif k==Enum.KeyCode.F2 then S._stopRec()
    elseif k==Enum.KeyCode.F3 then
        S.trimStart=math.max(0,math.floor(tonumber(U.trimStartBox.Text) or 0))
        S.trimEnd=math.max(0,math.floor(tonumber(U.trimEndBox.Text) or 0))
        S._saveRec(); pcall(function() if U.listScroll.Visible then U.refreshRepList() end end)
    elseif k==Enum.KeyCode.F4 then S._toggleSmartRec()
    elseif k==Enum.KeyCode.F5 then S._playReplay()
    elseif k==Enum.KeyCode.F6 then S._stopReplay()
    elseif k==Enum.KeyCode.F8 then S._saveCP()
    elseif k==Enum.KeyCode.F9 then
        S.isLooping=not S.isLooping; U.loopBtn.Text=S.isLooping and "⟳  LOOP ON" or "⟳  LOOP"
        S._tw(U.loopBtn,{BackgroundColor3=S.isLooping and C.dG or C.bg4},0.15)
    elseif k==Enum.KeyCode.F10 then
        S.isMinimized=not S.isMinimized
        if S.isMinimized then S._tw(U.win,{Size=UDim2.new(0,S.WIN_W,0,36)},0.25,Enum.EasingStyle.Quart); U.content.Visible=false
        else S._tw(U.win,{Size=UDim2.new(0,S.WIN_W,0,S.WIN_H)},0.25,Enum.EasingStyle.Quart); U.content.Visible=true end
    elseif k==Enum.KeyCode.F11 then S._updateSummit(true)
    end
end)

game:GetService("RunService").Heartbeat:Connect(function(dt)
    pcall(S._updatePerf)
    pcall(S._updateSummit,false)
    pcall(S._updateSmartRec,dt)
end)

task.delay(0.05,function()
    S._tw(U.win,{Size=UDim2.new(0,S.WIN_W,0,S.WIN_H)},0.4,Enum.EasingStyle.Quart,Enum.EasingDirection.Out)
end)

end)()
