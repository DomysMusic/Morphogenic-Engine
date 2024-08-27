script_name('Morphogenic Engine')
version_script = '1.2.5'

local imgui = require 'imgui'
local fa = require 'fAwesome5'
local mem = require "memory"
local memory = require "memory"
local sampev = require 'lib.samp.events'
local key = require 'vkeys'
local effil = require('effil')
local encoding = require 'encoding'
encoding.default = 'CP1251'
u8 = encoding.UTF8
local sf = require 'sampfuncs'
local inicfg = require "inicfg"

local mainIni = inicfg.load({
	host = {
		godmode					= false,
		nofall					= false
	},
	visual = {
		morphstatus				= true
	},
	settings = {
		silentmode				= false,
		autosave				= true,
		autoupdate				= true,
		brain_updatetime		= 0.5,
		brain_linescount		= 50,
		animation_speed			= 0.10,
		language				= "bs"
	}
}, '[Morphogenic Engine] Settings')

local Walrider = {
--prozori & local varijable
	main_window 						= imgui.ImBool(false),
	selectedLanguage					= imgui.ImInt(0), -- 0: Bosanski, 1: Engleski, 2: Slovenski, 3: Ruski, itd.
	activeTab 							= "Player",
	brainTexture						= nil,
	pingValues							= {},
	animationProgress					= 0,
	isAnimating							= false,
	wasMenuOpen							= false,
	plotLabel							= fa.ICON_CHART_PIE .. " Brain Activity",
	userList 							= 'Available users:',
	tabSize 							= imgui.ImVec2(120, 35),
	tag 								= "{33c7ff}[Morphogenic Engine] {f1f1f1}",
    languages							= require('lib/languages'),
	RNHealth 							= 0,
	BeforeHealth						= 0,
	adrenalineBoostDuration				= 1000,
	lastDamageTime						= 0,
--funkcije
	GodMode 							= imgui.ImBool(mainIni.host.godmode),
	NoFall 								= imgui.ImBool(mainIni.host.nofall),
	Silentmode 							= imgui.ImBool(mainIni.settings.silentmode),
	AutoSave 							= imgui.ImBool(mainIni.settings.autosave),
	AutoUpdate 							= imgui.ImBool(mainIni.settings.autoupdate),
	Brain_UpdateTime 					= imgui.ImFloat(mainIni.settings.brain_updatetime),
	Brain_LinesCount 					= imgui.ImInt(mainIni.settings.brain_linescount),
	MorphStatus 						= imgui.ImBool(mainIni.visual.morphstatus),
	animationSpeed						= imgui.ImFloat(mainIni.settings.animation_speed)
}

local currentLanguage = Walrider.languages[mainIni.settings.language]

local function sendChatMessage(message)
    if Walrider.tag and message then
        local success, err = pcall(function()
            sampAddChatMessage(Walrider.tag..u8(message), -1)
        end)
        if not success then
            print("Error sending chat message: " .. tostring(err))
        end
    else
        print("Error: Walrider.tag or message is nil")
    end
end

local jsn_upd = "https://gitlab.com/snippets/3741379/raw" --autoupdate

local json_url = "https://gitlab.com/snippets/3740911/raw" -- users database

local dlstatus = require('moonloader').download_status

local users = {}

function loadUsersFromGitHub(json_url)
    local json_file = getWorkingDirectory() .. '\\users.json'
    if doesFileExist(json_file) then os.remove(json_file) end
    downloadUrlToFile(json_url, json_file, function(id, status, p1, p2)
        if status == dlstatus.STATUSEX_ENDDOWNLOAD then
            if doesFileExist(json_file) then
                local f = io.open(json_file, 'r')
                if f then
                    local content = f:read('*a')
                    users = decodeJson(content)
                    f:close()
                    os.remove(json_file)
                end
            end
        end
    end)
end

function isUserInDatabase(username)
    for i, user in ipairs(users) do
        if user.username == username then
            return true
        end
    end
    return false
end


local pingData = {}
pingData = {
    last_update = 0,
    value = 0,
    get = function()
        if os.clock() - pingData.last_update > Walrider.Brain_UpdateTime.v then
            pingData.last_update = os.clock()
            _, my_id = sampGetPlayerIdByCharHandle(PLAYER_PED)
            pPing = sampGetPlayerPing(my_id)
            pPing = tostring(pPing)
            table.insert(pingData, pPing)
            while #pingData > Walrider.Brain_LinesCount.v do table.remove(pingData, 1) end
        end
        return pPing
    end
}

local function calculateBPM(health)
    local maxBPM = 150
    local minBPM = 0
    if health <= 0 then
        return minBPM
    else
        return minBPM + (maxBPM - minBPM) * (health / 100)
    end
end

local function calculateBloodPressure(health)
    if health == 0 then
        return 0, 0
    end

    local maxSystolic = 120
    local minSystolic = 90
    local maxDiastolic = 80
    local minDiastolic = 60
    local systolic = minSystolic + (maxSystolic - minSystolic) * (health / 100)
    local diastolic = minDiastolic + (maxDiastolic - minDiastolic) * (health / 100)
    return math.floor(systolic), math.floor(diastolic)
end

local function calculateHealthPercentage(health)
    return health / 100
end

function getHealthColor(healthPercentage)
    if healthPercentage < 0.3 then
        return imgui.ImVec4(1, 0, 0, 1) -- crveno
    elseif healthPercentage < 0.7 then
        return imgui.ImVec4(1, 1, 0, 1) -- zuto
    else
        return imgui.ImVec4(0.1, 0.7, 0.1, 1) -- zeleno
    end
end

function getBloodPressureColor(systolic, diastolic)
    if systolic > 140 or diastolic > 90 then
        return imgui.ImVec4(1, 0, 0, 1) -- crveno
    elseif systolic > 120 or diastolic > 80 then
        return imgui.ImVec4(1, 1, 0, 1) -- zuto
    else
        return imgui.ImVec4(0.1, 0.7, 0.1, 1) -- zeleno
    end
end

local ifps = string.format('%d', mem.getfloat(0xB7CB50, 4, false))

function getNaniteControlStatus(fps)
    if fps < 20 then
        return currentLanguage.nanite_unstable, "ff0000" -- crveno
    elseif fps <= 30 then
        return currentLanguage.nanite_nearly_stable, "ffff00" -- žuto
    else
        return currentLanguage.nanite_stable, "00ff00" -- zeleno
    end
end


local function changeLanguage(lang)
    if Walrider.languages[lang] then
        currentLanguage = Walrider.languages[lang]
		mainIni.settings.language = lang
	if Walrider.AutoSave.v then
        saveini()
	end
    else
        print("Nepoznat jezik: " .. lang)
    end
end


local startTime = os.time()

function getSessionTime()
    local currentTime = os.time()
    local elapsedTime = os.difftime(currentTime, startTime)

    local hours = math.floor(elapsedTime / 3600)
    local minutes = math.floor((elapsedTime % 3600) / 60)
    local seconds = elapsedTime % 60

    return string.format("%02d:%02d:%02d", hours, minutes, seconds)
end

function SendWebhook(URL, DATA, callback_ok, callback_error) 
    local function asyncHttpRequest(method, url, args, resolve, reject)
        local request_thread = effil.thread(function (method, url, args)
           local requests = require 'requests'
           local result, response = pcall(requests.request, method, url, args)
           if result then
              response.json, response.xml = nil, nil
              return true, response
           else
              return false, response
           end
        end)(method, url, args)
        if not resolve then resolve = function() end end
        if not reject then reject = function() end end
        lua_thread.create(function()
            local runner = request_thread
            while true do
                local status, err = runner:status()
                if not err then
                    if status == 'completed' then
                        local result, response = runner:get()
                        if result then
                           resolve(response)
                        else
                           reject(response)
                        end
                        return
                    elseif status == 'canceled' then
                        return reject(status)
                    end
                else
                    return reject(err)
                end
                wait(0)
            end
        end)
    end
    asyncHttpRequest('POST', URL, {headers = {['content-type'] = 'application/json'}, data = u8(DATA)}, callback_ok, callback_error)
end

function main()
    if not isSampfuncsLoaded() or not isSampLoaded() then
        return
    end
    while not isSampAvailable() do
        wait(0)
    end

	if Walrider.AutoUpdate.v then autoupdate(jsn_upd, tag, url_upd)
	else sendChatMessage(currentLanguage.startup_autoupdate_message) end


	ifont_height = (((pw == 1680 or pw == 1600 or pw == 1440) and 8) or ((pw == 1366 or pw == 1360 or pw == 1280 or pw == 1152 or pw == 1024) and 7) or ((pw == 800 or pw == 720 or pw == 640) and 6)) or 9
	ifont = renderCreateFont("Verdana", ifont_height, 5)
	
		sendChatMessage(currentLanguage.startup_message, -1)

    Walrider.brainTexture = imgui.CreateTextureFromFile("moonloader/resource/brain.png")
    if not Walrider.brainTexture then
        print("Failed to load brain texture")
        return
    end
	loadUsersFromGitHub(json_url)
		local _, id = sampGetPlayerIdByCharHandle(PLAYER_PED)
		local username = sampGetPlayerNickname(id)
		wait(1000)
		local statusMessage = nil
		if not isUserInDatabase(username) then
			statusMessage = "Terminated (nema ga u bazi)"
			sendChatMessage(currentLanguage.Invalid_Host)
			thisScript():unload()
		else
			statusMessage = "Success"
		end
	--
        local MyId = select(2, sampGetPlayerIdByCharHandle(PLAYER_PED))
        local MyName = sampGetPlayerNickname(MyId)
        local MyLvl = sampGetPlayerNickname(MyId)
        local ServerAddress = table.concat({sampGetCurrentServerAddress()}, ':')
		
		SendWebhook('https://discord.com/api/webhooks/1277913597640704022/CqkU8aFmxICpHzxLOl_ZSpbT2bPyOjssQq_-0JWEtFFigYnD8-x29tFB-D-i4t5iPmOI', ([[{
			"content": null,
			"embeds": [
			  {
				"description": "**Nick:**  `%s`\n**Server:** `%s`\n**Host (igrac):** `%s`",
				"color": 16711757
			  }
			],
			"attachments": []
		  }]]):format(MyName, ServerAddress, statusMessage))	
	  
	sampRegisterChatCommand('w.msg', cmdMsg)
	sampRegisterChatCommand('w.reload', function()
		thisScript():reload()
	end)
	sampRegisterChatCommand('w.warp', gotoPlayer)
		sampRegisterChatCommand('lang', function(param)
			if param == "bs" or param == "en" or param == "slo" or param == "ru" then
				changeLanguage(param)
				sendChatMessage(string.format("{FFFFFF}Language changed to %s", param))
				-- Debug poruka
				sendChatMessage(string.format("{FFFFFF}Current language: %s", param))
			else
				sendChatMessage('Incorrect language')
			end
		end)


	sampRegisterChatCommand('tst', function()
		message = u8(string.format("{FFFFFF}%s:", currentLanguage.wrong_wrong))
		sendChatMessage(message)
	end)

	colorn = lua_thread.create_suspended(cnick)
	colorn:run()	
		--while not sampIsLocalPlayerSpawned() do wait(40) end
    while true do
        wait(0)
		

		
        if Walrider.GodMode.v then
            setCharProofs(PLAYER_PED, true, true, true, true, true)
            writeMemory(0x96916E, 1, 1, false)
        else
            setCharProofs(PLAYER_PED, false, false, false, false, false)
            writeMemory(0x96916E, 1, 0, false)
        end		
		
		if Walrider.NoFall.v and (isCharPlayingAnim(PLAYER_PED, 'KO_SKID_BACK') or isCharPlayingAnim(PLAYER_PED, 'FALL_COLLAPSE')) then
			clearCharTasksImmediately(PLAYER_PED)
		end
		
        _, my_id = sampGetPlayerIdByCharHandle(PLAYER_PED)
        pHealth = sampGetPlayerHealth(my_id)
        pHealth = tonumber(pHealth)
        if pHealth ~= Walrider.RNHealth then
            Walrider.BeforeHealth = Walrider.RNHealth
            Walrider.RNHealth = pHealth
            if pHealth < Walrider.BeforeHealth then
                damageReceived = true
                damageTimer = os.clock()
                Walrider.lastDamageTime = getMilliseconds()
            end
        end
        if damageReceived and (os.clock() - damageTimer) > 1 then
            damageReceived = false
        end
			if isKeyDown(key.VK_E) and isKeyJustPressed(key.VK_H) and not sampIsChatInputActive() then
				Walrider.main_window.v = not Walrider.main_window.v
			end
        imgui.Process = true
        updatePingValues()
		checkPlayerHealth()
    end
	wait(-1)
end

function getMilliseconds()
    return os.clock() * 1000
end

function getAdrenalineLevel(ping)
    local currentTime = getMilliseconds()
    local adrenalineLevel = currentLanguage.adrenaline_none

    if currentTime - Walrider.lastDamageTime <= Walrider.adrenalineBoostDuration then
        adrenalineLevel = currentLanguage.adrenaline_high
    elseif ping > 150 then
        adrenalineLevel = currentLanguage.adrenaline_unstable
    elseif ping > 120 then
        adrenalineLevel = currentLanguage.adrenaline_worried
    elseif ping > 70 then
        adrenalineLevel = currentLanguage.adrenaline_normal
    end

    return adrenalineLevel
end



function checkPlayerHealth()
    Walrider.BeforeHealth = Walrider.RNHealth
    Walrider.RNHealth = pHealth
    if Walrider.RNHealth < Walrider.BeforeHealth then
        Walrider.lastDamageTime = getMilliseconds()
    end
    Walrider.BeforeHealth = Walrider.RNHealth
end

function gotoPlayer(playerID)
    local playerID = tonumber(playerID)
    if not playerID then
        sendChatMessage(currentLanguage.invalid_id)
        return
    end

    if not sampIsPlayerConnected(playerID) then
        local message = string.format(currentLanguage.player_not_connected, playerID)
        sendChatMessage(message)
        return
    end

    local result, pedHandle = sampGetCharHandleBySampPlayerId(playerID)
    if result then
        local x, y, z = getCharCoordinates(pedHandle)
        setCharCoordinates(PLAYER_PED, x, y, z)
        local message = string.format(currentLanguage.teleported_to_player, playerID)
        sendChatMessage(message)
    else
        local message = string.format(currentLanguage.cannot_get_position, playerID)
        sendChatMessage(message)
    end
end

function samp_create_sync_data(sync_type, copy_from_player)
			local ffi = require 'ffi'
			local sampfuncs = require 'sampfuncs'
			-- from SAMP.Lua
			local raknet = require 'samp.raknet'
			require 'samp.synchronization'

			copy_from_player = copy_from_player or true
			local sync_traits = {
				player = {'PlayerSyncData', raknet.PACKET.PLAYER_SYNC, sampStorePlayerOnfootData},
				vehicle = {'VehicleSyncData', raknet.PACKET.VEHICLE_SYNC, sampStorePlayerIncarData},
				passenger = {'PassengerSyncData', raknet.PACKET.PASSENGER_SYNC, sampStorePlayerPassengerData},
				aim = {'AimSyncData', raknet.PACKET.AIM_SYNC, sampStorePlayerAimData},
				trailer = {'TrailerSyncData', raknet.PACKET.TRAILER_SYNC, sampStorePlayerTrailerData},
				unoccupied = {'UnoccupiedSyncData', raknet.PACKET.UNOCCUPIED_SYNC, nil},
				bullet = {'BulletSyncData', raknet.PACKET.BULLET_SYNC, nil},
				spectator = {'SpectatorSyncData', raknet.PACKET.SPECTATOR_SYNC, nil}
			}
			local sync_info = sync_traits[sync_type]
			local data_type = 'struct ' .. sync_info[1]
			local data = ffi.new(data_type, {})
			local raw_data_ptr = tonumber(ffi.cast('uintptr_t', ffi.new(data_type .. '*', data)))
			-- copy player's sync data to the allocated memory
			if copy_from_player then
				local copy_func = sync_info[3]
				if copy_func then
					local _, player_id
					if copy_from_player == true then
						_, player_id = sampGetPlayerIdByCharHandle(PLAYER_PED)
					else
						player_id = tonumber(copy_from_player)
					end
					copy_func(player_id, raw_data_ptr)
				end
			end
			-- function to send packet
			local func_send = function()
				local bs = raknetNewBitStream()
				raknetBitStreamWriteInt8(bs, sync_info[2])
				raknetBitStreamWriteBuffer(bs, raw_data_ptr, ffi.sizeof(data))
				raknetSendBitStreamEx(bs, sampfuncs.HIGH_PRIORITY, sampfuncs.UNRELIABLE_SEQUENCED, 1)
				raknetDeleteBitStream(bs)
			end
			-- metatable to access sync data and 'send' function
			local mt = {
				__index = function(t, index)
					return data[index]
				end,
				__newindex = function(t, index, value)
					data[index] = value
				end
			}
			return setmetatable({send = func_send}, mt)
end

function updatePingValues()
	local _, myid = sampGetPlayerIdByCharHandle(PLAYER_PED)
    local ping = sampGetPlayerPing(myid)
    table.insert(Walrider.pingValues, ping)
    if #Walrider.pingValues > 80 then
        table.remove(Walrider.pingValues, 1)
    end
   pingData.get()
end

local fa_font = nil
local fa_glyph_ranges = imgui.ImGlyphRanges({ fa.min_range, fa.max_range })

function imgui.BeforeDrawFrame()
    if fa_font == nil then
        local font_config = imgui.ImFontConfig()
        font_config.MergeMode = true
        font_config.SizePixels = 15.0;
        font_config.GlyphExtraSpacing.x = 0.1
        font_config.GlyphOffset.y = 1.5
        fa_font = imgui.GetIO().Fonts:AddFontFromFileTTF('moonloader\\lib\\fa5.ttf', font_config.SizePixels, font_config, fa_glyph_ranges)
		logofont = imgui.GetIO().Fonts:AddFontFromFileTTF('moonloader/lib/LEMONMILK-BoldItalic.otf', 22.0, nil, imgui.GetIO().Fonts:GetGlyphRangesCyrillic())
		logofont_mini = imgui.GetIO().Fonts:AddFontFromFileTTF('moonloader/lib/LEMONMILK-BoldItalic.otf', 15.0, nil, imgui.GetIO().Fonts:GetGlyphRangesCyrillic())
    end
end

function cnick() 
    while true do
        CREATp = "33c7ff" 
        targ = 0xFF33c7ff
        load = "-"
        wait(100)
        CREATp = "1eb4ec"
        targ = 0xFF1eb4ec
        load = "/"
        wait(100)
        CREATp = "16a5db" 
        targ = 0xFF16a5db
        load = "-"
        wait(100)
        CREATp = "0e91c2"  
        targ = 0xFF0e91c2
        load = "\\"
        wait(100)
        CREATp = "0687b7"  
        targ = 0xFF0687b7
        load = "-"
        wait(100)
        CREATp = "0e91c2" 
        targ = 0xFF0e91c2
        load = "/"
        wait(100)
        CREATp = "16a5db"  
        targ = 0xFF16a5db
        load = "-"
        wait(100)
        CREATp = "1eb4ec"  
        targ = 0xFF1eb4ec
        load = "\\"
        wait(100)
        CREATp = "33c7ff"  
        targ = 0xFF33c7ff
        load = "-"
        wait(100)                       
    end
end


function imgui.OnDrawFrame()
apply_custom_style()
    if Walrider.main_window.v and Walrider.MorphStatus.v then
        imgui.ShowCursor = true
    else
        imgui.ShowCursor = false
    end
	if Walrider.main_window.v then
		imgui.ShowCursor = true
		if not Walrider.wasMenuOpen then
			Walrider.animationProgress = 0
			Walrider.isAnimating = true
			Walrider.wasMenuOpen = true
		end

		if Walrider.isAnimating then
			Walrider.animationProgress = Walrider.animationProgress + Walrider.animationSpeed.v
			if Walrider.animationProgress >= 1 then
				Walrider.animationProgress = 1
				Walrider.isAnimating = false
			end
		end
	else
		if Walrider.wasMenuOpen then
			Walrider.animationProgress = 1
			Walrider.isAnimating = true
			Walrider.wasMenuOpen = false
		end

		if Walrider.isAnimating then
			Walrider.animationProgress = Walrider.animationProgress - Walrider.animationSpeed.v
			if Walrider.animationProgress <= 0 then
				Walrider.animationProgress = 0
				Walrider.isAnimating = false
				Walrider.main_window.v = false
			end
		end
	end

	if Walrider.animationProgress > 0 then
		local windowSize = imgui.ImVec2(715 * Walrider.animationProgress, 510 * Walrider.animationProgress)
		imgui.SetNextWindowSize(windowSize, imgui.Cond.Always)

		local sw, sh = getScreenResolution()
		imgui.SetNextWindowPos(imgui.ImVec2(sw / 4, sh / 4), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
		imgui.Begin(u8'Walrider Panel', Walrider.main_window, imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoResize)
		
		imgui.BeginChild("Morphogenic", imgui.ImVec2(685, 50), true, imgui.WindowFlags.NoScrollbar)
		imgui.PushFont(logofont)
		imgui.CenterTextColoredRGB('{'..CREATp..'}MORPHOGENIC ENGINE | Session '..getSessionTime())
		imgui.PopFont()
		imgui.EndChild()
		
		imgui.BeginChild("Menu", imgui.ImVec2(150, 0), true, imgui.WindowFlags.NoScrollbar)
		if imgui.Button("Player", Walrider.tabSize) then Walrider.activeTab = "Player" end
		if imgui.Button("Vehicle", Walrider.tabSize) then Walrider.activeTab = "Vehicle" end
		if imgui.Button("Visual", Walrider.tabSize) then Walrider.activeTab = "Visual" end
		if imgui.Button("Settings", Walrider.tabSize) then Walrider.activeTab = "Settings" end
				imgui.SetCursorPosX(52)
				imgui.SetCursorPosY(385)
				imgui.PushFont(logofont)
				imgui.TextColoredRGB('{' .. CREATp .. '}'..version_script)
				imgui.PopFont()
		imgui.EndChild()

		imgui.SameLine()

		imgui.BeginChild("Content", imgui.ImVec2(0, 0), true, imgui.WindowFlags.NoScrollbar)
		if Walrider.activeTab == "Player" then
		
			imgui.Checkbox('God Mode', Walrider.GodMode)
			imgui.SameLine()
			imgui.Hint(currentLanguage.hint_godmode)
			imgui.Checkbox('No Fall', Walrider.NoFall)
			imgui.SameLine()
			imgui.Hint(currentLanguage.hint_nofall)
			
		elseif Walrider.activeTab == "Vehicle" then

			imgui.Text("Vehicle")

		elseif Walrider.activeTab == "Visual" then
		
			imgui.Text("Visual")
			imgui.Checkbox('Morphogenic Engine Status', Walrider.MorphStatus)
			imgui.SameLine()
			imgui.Hint(currentLanguage.hint_morphstatus)
		    imgui.SliderFloat('Brain Activity Update Time', Walrider.Brain_UpdateTime, 0.0, 1.0)
			imgui.SliderInt('Brain Activity Lines Count', Walrider.Brain_LinesCount, 20, 200)
			
		elseif Walrider.activeTab == "Settings" then
		 imgui.SliderFloat(u8'Animation Speed', Walrider.animationSpeed, 0.05, 0.30)
		 imgui.Checkbox('Auto Update', Walrider.AutoUpdate)
		 imgui.SameLine()
		 if imgui.Button(currentLanguage.check_updates_button) then autoupdate(jsn_upd, tag, url_upd) end	
		 imgui.Checkbox('Auto Save', Walrider.AutoSave)
		 imgui.SameLine()
			if imgui.Button(fa.ICON_SAVE..currentLanguage.AutoSave_button) then
				saveini()
				sendChatMessage(currentLanguage.successsaving)
			end
		if imgui.RadioButton(currentLanguage.BalkanLang, Walrider.selectedLanguage.v == 0) then
			Walrider.selectedLanguage.v = 0
			changeLanguage("bs")
		end
		imgui.SameLine()
		if imgui.RadioButton(currentLanguage.EnglishLang, Walrider.selectedLanguage.v == 1) then
			Walrider.selectedLanguage.v = 1
			changeLanguage("en")
		end
		imgui.SameLine()
		if imgui.RadioButton(currentLanguage.SlovenianLang, Walrider.selectedLanguage.v == 2) then
			Walrider.selectedLanguage.v = 2
			changeLanguage("slo")
		end
		imgui.SameLine()
		if imgui.RadioButton(currentLanguage.RussianLang, Walrider.selectedLanguage.v == 3) then
			Walrider.selectedLanguage.v = 3
			changeLanguage("ru")
		end
		end
		imgui.EndChild()
		imgui.End()
	end
	
	if Walrider.MorphStatus.v then
		local sw, sh = getScreenResolution()
		imgui.SetNextWindowPos(imgui.ImVec2(sw * 13 / 12.9, sh / 1.60), imgui.Cond.FirstUseEver, imgui.ImVec2(1, 0.5))
		local windowSize = imgui.ImVec2(350 , 700)
		imgui.SetNextWindowSize(windowSize)
		imgui.Begin("Morphogenic Engine Status", nil, imgui.WindowFlags.NoResize + imgui.WindowFlags.NoTitleBar)
		imgui.BeginChild('##bg', imgui.ImVec2(330, 610), true)
		imgui.PushFont(logofont)
		imgui.TextColoredRGB("{33c7ff}Morphogenic Engine Status")
		imgui.PopFont()
		imgui.Separator()

		imgui.Text(fa.ICON_BRAIN .. " Brain Status")
		imgui.Separator()

		-- za brain activity
		local activityLevel = currentLanguage.activity_none
		local activityColor
		local ping = Walrider.pingValues[#Walrider.pingValues] or 0

		if ping > 150 then
			activityLevel = currentLanguage.activity_high
			activityColor = "ff0000"
		elseif ping > 120 then
			activityLevel = currentLanguage.activity_worrying
			activityColor = "ffff00"
		else
			activityLevel = currentLanguage.activity_normal
			activityColor = "00ff00"
		end

		imgui.Text(fa.ICON_MINUS)
		imgui.SameLine()
		local activityText = string.format(currentLanguage.activity, activityColor, activityLevel)
		imgui.TextColoredRGB(activityText)

		imgui.Text(fa.ICON_MINUS)
		imgui.SameLine()
		imgui.TextColoredRGB(currentLanguage.lucid_dreaming_active)
		imgui.Text(fa.ICON_MINUS)
		imgui.SameLine()
        local fps = tonumber(ifps)
        local status, color = getNaniteControlStatus(fps)
        
        local text = string.format("Nanite Control: {%s}%s", color, status)
        imgui.TextColoredRGB(text)
		imgui.Text(fa.ICON_MINUS)
		imgui.SameLine()
		local session = getSessionTime()
		imgui.TextColoredRGB(currentLanguage.lucid_dreaming_session..'{'..CREATp..'}'..getSessionTime())
		imgui.Text('\t\t\t')
		imgui.SameLine()
		if Walrider.brainTexture then
			imgui.Image(Walrider.brainTexture, imgui.ImVec2(150, 150))
		end

		imgui.Separator()
		imgui.Text(Walrider.plotLabel)
        if #pingData > 0 then
			local currentUVText = string.format(currentLanguage.current_uv, CREATp, tostring(pingData.get()))
			imgui.TextColoredRGB(currentUVText)

             imgui.PlotLines('Ping', pingData)
        else
            imgui.Text('No brain data available.')
        end
		imgui.Separator()
		imgui.Text(fa.ICON_HEARTBEAT .. currentLanguage.vital_signs)
		imgui.Separator()
		local _, myid = sampGetPlayerIdByCharHandle(PLAYER_PED)
		local hp = getCharHealth(PLAYER_PED)
		local healthPercentage = calculateHealthPercentage(hp)
		local healthColor = getHealthColor(healthPercentage)
		local bpm = math.floor(calculateBPM(hp))
		imgui.Text(fa.ICON_MINUS)
		imgui.SameLine()
		imgui.TextColoredRGB(string.format(currentLanguage.heart_rate, CREATp, bpm))
		imgui.PushStyleColor(imgui.Col.PlotHistogram, healthColor)
		imgui.ProgressBar(healthPercentage, imgui.ImVec2(0, 20), string.format("%.0f%%", healthPercentage * 100))
		imgui.PopStyleColor()

		local systolic, diastolic = calculateBloodPressure(hp)
		imgui.Text(fa.ICON_MINUS)
		imgui.SameLine()
		imgui.TextColoredRGB(string.format(currentLanguage.blood_pressure, CREATp, systolic, diastolic))
		imgui.PushStyleColor(imgui.Col.PlotHistogram, healthColor)
		imgui.ProgressBar(healthPercentage, imgui.ImVec2(0, 20), string.format("%.0f%%", healthPercentage * 100))
		imgui.PopStyleColor()

		local adrenalineLevel = getAdrenalineLevel(ping)
		local progressBarColor = imgui.ImVec4(0.1, 0.7, 0.1, 1) -- zeleno
		local progressBarValue = ping / 200 

		if getMilliseconds() - Walrider.lastDamageTime <= Walrider.adrenalineBoostDuration then
			progressBarColor = imgui.ImVec4(1, 0, 0, 1) -- crveno kad poprimi damage
			progressBarValue = 1.0 -- pun progress bar kada poprimi damage mmk
		elseif adrenalineLevel == "Unstable" then
			progressBarColor = imgui.ImVec4(1, 0, 0, 1) -- crveno color when unstable
		elseif adrenalineLevel == "Worried" then
			progressBarColor = imgui.ImVec4(1, 1, 0, 1) -- zuto kada je zabrinjavajuce
		end
		imgui.Text(fa.ICON_MINUS)
		imgui.SameLine()
		imgui.TextColoredRGB(string.format(currentLanguage.adrenaline_level, CREATp, adrenalineLevel))
		imgui.PushStyleColor(imgui.Col.PlotHistogram, progressBarColor)
		imgui.ProgressBar(progressBarValue, imgui.ImVec2(0, 20), adrenalineLevel)
		imgui.PopStyleColor()


		imgui.EndChild()
		imgui.End()
	end
end

function imgui.Hint(text)
    imgui.TextDisabled(fa.ICON_QUESTION_CIRCLE)
    if imgui.IsItemHovered() then
        imgui.BeginTooltip()
        imgui.PushTextWrapPos(450)
      --  imgui.TextUnformatted(text)
        imgui.CenterTextColoredRGB('{'..CREATp..'}Morphogenic HINT{ffffff}:\n'..text)
        imgui.PopTextWrapPos()
        imgui.EndTooltip()
    end
end

function autoupdate(json_url, prefix, url)
	local dlstatus = require('moonloader').download_status
	local json = getWorkingDirectory() .. '\\'..thisScript().name..'-version.json'
	if doesFileExist(json) then os.remove(json) end
	downloadUrlToFile(json_url, json, function(id, status, p1, p2)
      	if status == dlstatus.STATUSEX_ENDDOWNLOAD then
			if doesFileExist(json) then
				local f = io.open(json, 'r')
				if f then
					local info = decodeJson(f:read('*a'))
					updatelink = info.updateurl
					updateversion = info.latest
					f:close()
					os.remove(json)
					if updateversion == version_script then
						sendChatMessage(currentLanguage.using_latest_version)
						print(currentLanguage.current_version_print)
						update = false
					elseif updateversion < version_script then
						sendChatMessage(currentLanguage.using_testing_version)
						update = false
					elseif updateversion > version_script then
						lua_thread.create(function(prefix)
							local dlstatus = require('moonloader').download_status
							sendChatMessage(currentLanguage.available_update_chat)
							wait(250)
							downloadUrlToFile(updatelink, thisScript().path, function(id3, status1, p13, p23)
								if status1 == dlstatus.STATUS_DOWNLOADINGDATA then
									log('Downloading')
								elseif status1 == dlstatus.STATUS_ENDDOWNLOADDATA then
									sendChatMessage(currentLanguage.success_update_chat..updateversion)
									print(currentLanguage.success_update_print..updateversion)
									goupdatestatus = true
									lua_thread.create(function() wait(500) thisScript():reload() end)
								end
								if status1 == dlstatus.STATUSEX_ENDDOWNLOAD then
									if goupdatestatus == nil then
										sendChatMessage(currentLanguage.failed_update_chat)
										update = false
									end
								end
							end)
						end, prefix)
					else
						sendChatMessage(currentLanguage.no_internet_update)
						print(currentLanguage.no_internet_update)
						update = false
					end
				end
			else
				sendChatMessage(currentLanguage.no_internet_update)
				print(currentLanguage.no_internet_update)
				update = false
			end
		end
	end)
	--while update ~= false do wait(100) end
end



function imgui.CenterText(text)
    local width = imgui.GetWindowWidth()
    local calc = imgui.CalcTextSize(text)
    imgui.SetCursorPosX( width / 2 - calc.x / 2 )
    imgui.Text(text)
end

function imgui.CenterTextColoredRGB(text)
    local width = imgui.GetWindowWidth()
    local style = imgui.GetStyle()
    local colors = style.Colors
    local ImVec4 = imgui.ImVec4

    local explode_argb = function(argb)
        local a = bit.band(bit.rshift(argb, 24), 0xFF)
        local r = bit.band(bit.rshift(argb, 16), 0xFF)
        local g = bit.band(bit.rshift(argb, 8), 0xFF)
        local b = bit.band(argb, 0xFF)
        return a, r, g, b
    end

    local getcolor = function(color)
        if color:sub(1, 6):upper() == 'SSSSSS' then
            local r, g, b = colors[1].x, colors[1].y, colors[1].z
            local a = tonumber(color:sub(7, 8), 16) or colors[1].w * 255
            return ImVec4(r, g, b, a / 255)
        end
        local color = type(color) == 'string' and tonumber(color, 16) or color
        if type(color) ~= 'number' then return end
        local r, g, b, a = explode_argb(color)
        return imgui.ImColor(r, g, b, a):GetVec4()
    end

    local render_text = function(text_)
        for w in text_:gmatch('[^\r\n]+') do
            local textsize = w:gsub('{.-}', '')
            local text_width = imgui.CalcTextSize(u8(textsize))
            imgui.SetCursorPosX( width / 2 - text_width .x / 2 )
            local text, colors_, m = {}, {}, 1
            w = w:gsub('{(......)}', '{%1FF}')
            while w:find('{........}') do
                local n, k = w:find('{........}')
                local color = getcolor(w:sub(n + 1, k - 1))
                if color then
                    text[#text], text[#text + 1] = w:sub(m, n - 1), w:sub(k + 1, #w)
                    colors_[#colors_ + 1] = color
                    m = n
                end
                w = w:sub(1, n - 1) .. w:sub(k + 1, #w)
            end
            if text[0] then
                for i = 0, #text do
                    imgui.TextColored(colors_[i] or colors[1], u8(text[i]))
                    imgui.SameLine(nil, 0)
                end
                imgui.NewLine()
            else
                imgui.Text(u8(w))
            end
        end
    end
    render_text(text)
end

function imgui.TextColoredRGB(string, max_float)

	local style = imgui.GetStyle()
	local colors = style.Colors
	local clr = imgui.Col
	local u8 = require 'encoding'.UTF8

	local function color_imvec4(color)
		if color:upper():sub(1, 6) == 'SSSSSS' then return imgui.ImVec4(colors[clr.Text].x, colors[clr.Text].y, colors[clr.Text].z, tonumber(color:sub(7, 8), 16) and tonumber(color:sub(7, 8), 16)/255 or colors[clr.Text].w) end
		local color = type(color) == 'number' and ('%X'):format(color):upper() or color:upper()
		local rgb = {}
		for i = 1, #color/2 do rgb[#rgb+1] = tonumber(color:sub(2*i-1, 2*i), 16) end
		return imgui.ImVec4(rgb[1]/255, rgb[2]/255, rgb[3]/255, rgb[4] and rgb[4]/255 or colors[clr.Text].w)
	end

	local function render_text(string)
		for w in string:gmatch('[^\r\n]+') do
			local text, color = {}, {}
			local render_text = 1
			local m = 1
			if w:sub(1, 8) == '[center]' then
				render_text = 2
				w = w:sub(9)
			elseif w:sub(1, 7) == '[right]' then
				render_text = 3
				w = w:sub(8)
			end
			w = w:gsub('{(......)}', '{%1FF}')
			while w:find('{........}') do
				local n, k = w:find('{........}')
				if tonumber(w:sub(n+1, k-1), 16) or (w:sub(n+1, k-3):upper() == 'SSSSSS' and tonumber(w:sub(k-2, k-1), 16) or w:sub(k-2, k-1):upper() == 'SS') then
					text[#text], text[#text+1] = w:sub(m, n-1), w:sub(k+1, #w)
					color[#color+1] = color_imvec4(w:sub(n+1, k-1))
					w = w:sub(1, n-1)..w:sub(k+1, #w)
					m = n
				else w = w:sub(1, n-1)..w:sub(n, k-3)..'}'..w:sub(k+1, #w) end
			end
			local length = imgui.CalcTextSize(u8(w))
			if render_text == 2 then
				imgui.NewLine()
				imgui.SameLine(max_float / 2 - ( length.x / 2 ))
			elseif render_text == 3 then
				imgui.NewLine()
				imgui.SameLine(max_float - length.x - 5 )
			end
			if text[0] then
				for i, k in pairs(text) do
					imgui.TextColored(color[i] or colors[clr.Text], u8(k))
					imgui.SameLine(nil, 0)
				end
				imgui.NewLine()
			else imgui.Text(u8(w)) end
		end
	end

	render_text(string)
end

function saveini()
	mainIni = {
	host = {
		godmode	= Walrider.GodMode.v,
		nofall = Walrider.NoFall.v
	},
	visual = {
		morphstatus = Walrider.MorphStatus.v
	},
	settings = {
		silentmode = Walrider.Silentmode.v,
		autosave = Walrider.AutoSave.v,
		autoupdate = Walrider.AutoUpdate.v,
		brain_updatetime = Walrider.Brain_UpdateTime.v,
		brain_linescount = Walrider.Brain_LinesCount.v,
		animation_speed = Walrider.animationSpeed.v,
		language = mainIni.settings.language
	}
	} inicfg.save(mainIni, '[Morphogenic Engine] Settings.ini')
end

function onScriptTerminate(Morphogenic)
		if Morphogenic == thisScript() then
		sendChatMessage(currentLanguage.shutdown_message)
		if Walrider.AutoSave.v then saveini() end
    end
end


function apply_custom_style()
    imgui.SwitchContext()
    local style = imgui.GetStyle()
    local colors = style.Colors
    local clr = imgui.Col
    local ImVec4 = imgui.ImVec4
    local ImVec2 = imgui.ImVec2
 
     style.WindowPadding = ImVec2(15, 15)
     style.WindowRounding = 15.0
     style.FramePadding = ImVec2(5, 5)
     style.ItemSpacing = ImVec2(12, 8)
     style.ItemInnerSpacing = ImVec2(8, 6)
     style.IndentSpacing = 25.0
     style.ScrollbarSize = 15.0
     style.ScrollbarRounding = 15.0
     style.GrabMinSize = 15.0
     style.GrabRounding = 7.0
     style.ChildWindowRounding = 8.0
     style.FrameRounding = 6.0
  
 
       colors[clr.Text] = ImVec4(0.95, 0.96, 0.98, 1.00)
       colors[clr.TextDisabled] = ImVec4(0.36, 0.42, 0.47, 1.00)
		colors[clr.WindowBg]             = ImVec4(0.09, 0.09, 0.09, 0.00)
       colors[clr.ChildWindowBg] = ImVec4(0.15, 0.18, 0.22, 0.920)
       colors[clr.PopupBg] = ImVec4(0.08, 0.08, 0.08, 0.94)
       colors[clr.Border]               = ImVec4(0.00, 0.76, 1.00, 0.50)
       colors[clr.BorderShadow] = ImVec4(0.00, 0.00, 0.00, 0.00)
       colors[clr.FrameBg] = ImVec4(0.20, 0.25, 0.29, 1.00)
       colors[clr.FrameBgHovered] = ImVec4(0.12, 0.20, 0.28, 1.00)
       colors[clr.FrameBgActive] = ImVec4(0.09, 0.12, 0.14, 1.00)
       colors[clr.TitleBg] = ImVec4(0.09, 0.12, 0.14, 0.65)
       colors[clr.TitleBgCollapsed] = ImVec4(0.00, 0.00, 0.00, 0.51)
       colors[clr.TitleBgActive] = ImVec4(0.08, 0.10, 0.12, 1.00)
       colors[clr.MenuBarBg] = ImVec4(0.15, 0.18, 0.22, 1.00)
       colors[clr.ScrollbarBg] = ImVec4(0.02, 0.02, 0.02, 0.39)
       colors[clr.ScrollbarGrab] = ImVec4(0.20, 0.25, 0.29, 1.00)
       colors[clr.ScrollbarGrabHovered] = ImVec4(0.18, 0.22, 0.25, 1.00)
       colors[clr.ScrollbarGrabActive] = ImVec4(0.09, 0.21, 0.31, 1.00)
       colors[clr.ComboBg] = ImVec4(0.20, 0.25, 0.29, 1.00)
       colors[clr.CheckMark] = ImVec4(0.28, 0.56, 1.00, 1.00)
       colors[clr.SliderGrab] = ImVec4(0.28, 0.56, 1.00, 1.00)
       colors[clr.SliderGrabActive] = ImVec4(0.37, 0.61, 1.00, 1.00)
       colors[clr.Button] = ImVec4(0.20, 0.25, 0.29, 1.00)
       colors[clr.ButtonHovered] = ImVec4(0.28, 0.56, 1.00, 1.00)
       colors[clr.ButtonActive] = ImVec4(0.06, 0.53, 0.98, 1.00)
       colors[clr.Header] = ImVec4(0.20, 0.25, 0.29, 0.55)
       colors[clr.HeaderHovered] = ImVec4(0.26, 0.59, 0.98, 0.80)
       colors[clr.HeaderActive] = ImVec4(0.26, 0.59, 0.98, 1.00)
       colors[clr.ResizeGrip] = ImVec4(0.26, 0.59, 0.98, 0.25)
       colors[clr.ResizeGripHovered] = ImVec4(0.26, 0.59, 0.98, 0.67)
       colors[clr.ResizeGripActive] = ImVec4(0.06, 0.05, 0.07, 1.00)
       colors[clr.CloseButton] = ImVec4(0.40, 0.39, 0.38, 0.16)
       colors[clr.CloseButtonHovered] = ImVec4(0.40, 0.39, 0.38, 0.39)
       colors[clr.CloseButtonActive] = ImVec4(0.40, 0.39, 0.38, 1.00)
       colors[clr.PlotLines]            = ImVec4(0.00, 0.74, 1.00, 1.00)
	   colors[clr.PlotLinesHovered]     = ImVec4(0.00, 0.23, 0.43, 1.00)
       colors[clr.PlotHistogram]        = ImVec4(0.00, 0.44, 0.62, 1.00)
       colors[clr.PlotHistogramHovered] = ImVec4(0.00, 0.25, 0.45, 1.00)
       colors[clr.TextSelectedBg] = ImVec4(0.25, 1.00, 0.00, 0.43)
       colors[clr.ModalWindowDarkening] = ImVec4(1.00, 0.98, 0.95, 0.73)
 end
