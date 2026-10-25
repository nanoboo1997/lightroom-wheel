local Tasks = import 'LrTasks'
local Application = import 'LrApplication'
local View = import 'LrApplicationView'
local Develop = import 'LrDevelopController'
local File = import 'LrFileUtils'
local Path = import 'LrPathUtils'
local Date = import 'LrDate'
local root = Path.child(_PLUGIN.path, 'bridge')
File.createAllDirectories(root)

local function read(name)
    local f = io.open(Path.child(root,name),'rb')
    if not f then return nil end
    local s=f:read('*a');f:close();return s
end
local function write(name,s)
    local f=io.open(Path.child(root,name),'wb')
    if f then f:write(s);f:close() end
end
local function split(s)
    local a={};for x in (s..'|'):gmatch('(.-)|') do a[#a+1]=x end;return a
end
local params={Temp='Temperature',Tint='Tint',Exposure='Exposure',Contrast='Contrast',Highlights='Highlights',Shadows='Shadows',Whites='Whites',Blacks='Blacks',Texture='Texture',Clarity='Clarity',Dehaze='Dehaze',Vibrance='Vibrance',Saturation='Saturation'}
local bounds={Temp={-100,100},Tint={-100,100},Exposure={-5,5},Contrast={-100,100},Highlights={-100,100},Shadows={-100,100},Whites={-100,100},Blacks={-100,100},Texture={-100,100},Clarity={-100,100},Dehaze={-100,100},Vibrance={-100,100},Saturation={-100,100}}
local epoch=tostring(Date.currentTime())
_G.LRW_EPOCH=epoch
local previous=read('command.txt')
local lastSeq=previous and split(previous)[1] or '' -- Never replay the previous session's command.
local lastWrite=0
local lastAdjustment=0
local tracking=false

Tasks.startAsyncTask(function()
    while _G.LRW_EPOCH==epoch do
        local ok,err=Tasks.pcall(function()
            local catalog=Application.activeCatalog()
            local photo=catalog:getTargetPhoto()
            local id=photo and tostring(photo.localIdentifier) or 'none'
            local module=View.getCurrentModuleName()
            local selected=#catalog:getTargetPhotos()
            local now=Date.currentTime()
            if now-lastWrite>0.25 then
                local values={id,module,tostring(selected)}
                if module=='develop' and photo then
                    for display,param in pairs(params) do
                        local success,value=Tasks.pcall(function() return Develop.getValue(param) end)
                        if success and type(value)=='number' then values[#values+1]=display..'='..string.format('%.6f',value) end
                    end
                end
                write('state.txt',table.concat(values,'|'));lastWrite=now
            end
            local raw=read('command.txt')
            if raw and #raw<300 then
                local c=split(raw)
                if #c==5 and c[1]~=lastSeq then
                    lastSeq=c[1]
                    local delta=tonumber(c[4])
                    if module~='develop' or not photo then
                        write('reply.txt',c[1]..'|error|Open Develop and select a photo')
                    elseif selected~=1 then
                        write('reply.txt',c[1]..'|error|Select exactly one photo')
                    elseif c[5]~=id then
                        write('reply.txt',c[1]..'|error|Photo changed; command cancelled')
                    elseif not params[c[3]] or not delta or delta~=delta or math.abs(delta)>200 then
                        write('reply.txt',c[1]..'|error|Invalid slider command')
                    elseif c[2]~='adjust' and c[2]~='set' then
                        write('reply.txt',c[1]..'|error|Invalid operation')
                    else
                        local param=params[c[3]]
                        local before=Develop.getValue(param)
                        local range=bounds[c[3]]
                        if type(before)~='number' or before<range[1] or before>range[2] then
                            write('reply.txt',c[1]..'|error|Unsupported slider range')
                        else
                            local nextValue=c[2]=='set' and delta or before+delta
                            nextValue=math.max(range[1],math.min(range[2],nextValue))
                            Develop.startTracking(param)
                            Develop.setValue(param,nextValue)
                            tracking=true;lastAdjustment=now
                            Tasks.yield()
                            local after=Develop.getValue(param)
                            write('reply.txt',table.concat({c[1],'ok',c[3],string.format('%.6f',before),string.format('%.6f',after),id},'|'))
                            lastWrite=0
                        end
                    end
                end
            end
            if tracking and now-lastAdjustment>0.3 and module=='develop' then Develop.stopTracking();tracking=false end
        end)
        if not ok then write('error.txt',tostring(err)) end
        Tasks.sleep(0.04)
    end
end)
