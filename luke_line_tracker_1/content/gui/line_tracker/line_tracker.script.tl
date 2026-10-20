-- Line Tracker: a live route strip of a line, its stations, its vehicles, their load and their
-- direction of travel. Shown in two places:
--   1. a "Line Map" card in the line entity window, below Balance (LineTrackerPlugin)
--   2. a card right below the stop list in the line manager, for the selected line (doReplace)
--   3. a "Line Map" card in the vehicle window: that vehicle in full colour, the others faded
-- Everything is drawn from placed components inside a FloatingLayout. FloatingLayoutChild h/v
-- work like gravity: an item's left edge lands at h * (layout width - item width), so to centre
-- an item on a point its own size has to be taken into account (see place).

local react = ug_require "::/gui/main/react.lua" as React
local builtin = ug_require "::/gui/main/builtin.lua" as Builtin
local engine_react_util = ug_require "::/gui/main/engine_react_util.tl" as EngineReactUtil
local content_card = ug_require "::/gui/main/content_card.tl" as ContentCard
local styleutil = ug_require "::/gui/main/styleutil.tl" as StyleUtil
local gui_react_util = ug_require "::/gui/main/gui_react_util.tl" as GuiReactUtil
local cargo_react_util = ug_require "::/gui/main/cargo_react_util.tl" as CargoReactUtil
local callout_react_util = ug_require "::/gui/main/callout_react_util.tl" as CalloutReactUtil
local line_eow = ug_require "::/gui/entity_window/line/line_eow.script.tl" as LineEow
local vehicle_eow = ug_require "::/gui/entity_window/vehicle/vehicle_eow.script.tl" as VehicleEow
local LineManagerPanel = ug_require "::/gui/line_vehicle_mgmt/line_manager_panel.tl" as Recipe<LineManagerPanelParams>

-- Card width matches the vanilla cards (entity_window_sizes.InnerCardWidth, the Balance chart).
-- In the line manager the card sits in the stop list's scroll area (500 px manager content minus
-- paddings and the always-reserved scrollbar), so it is a little narrower.
local CARD_W <const> = 400
local MANAGER_W <const> = 430
local ROUTE_H <const> = 40
local PAD <const> = 16
local STATION_SIZE <const> = 18
local STATION_DOT <const> = 8 -- the white centre of a station circle
local VEHICLE_SIZE <const> = 12 -- the round part of the vehicle teardrop (fits inside a station)
local VEHICLE_OUTLINE <const> = 1
local POINTER_W <const> = 7 -- the teardrop's tip: how far the triangle reaches beyond its base
local POINTER_H <const> = 10 -- and how tall its base is

-- Where the triangle sits inside the 48x48 combobox arrow masks (measured from the @2x textures):
-- arrow_right spans x 16..35 (flat base at 16, tip at 35), y 7..41; arrow_left is its mirror.
local MASK_W <const> = 19 / 48
local MASK_H <const> = 34 / 48
local MASK_BASE <const> = 16 / 48 -- flat side of arrow_right from its left edge
local TRACK_THICKNESS <const> = 4
local REFRESH_SECONDS <const> = 0.25
local LINE_REFRESH_SECONDS <const> = 1.0

local CIRCLE_IMAGE <const> = "::/gui/line_vehicle_mgmt/icons/line_surface.tga" -- vanilla's line colour dot
local ARROW_RIGHT_IMAGE <const> = "::/gui/builtin/combobox/arrow_right.tga"
local ARROW_LEFT_IMAGE <const> = "::/gui/builtin/combobox/arrow_left.tga"
local COLOR_BACKGROUND : {number} = { 0.08, 0.10, 0.13, 0.85 }
local COLOR_STATION_DOT : {number} = { 0.97, 0.97, 0.97, 1.0 }
local COLOR_VEHICLE_OUTLINE : {number} = { 0.05, 0.05, 0.05, 1.0 }
local LOAD_EMPTY : {number} = { 0.30, 0.75, 0.42 }
local LOAD_HALF : {number} = { 0.96, 0.80, 0.25 }
local LOAD_FULL : {number} = { 0.90, 0.30, 0.25 }
-- other vehicles when one is highlighted (vehicle window): load colour washed towards grey, see-through
local FADE_TO : {number} = { 0.55, 0.57, 0.60 }
local FADE_MIX <const> = 0.6
local FADE_ALPHA <const> = 0.45

local record CargoCount
	cargoType : integer
	count : integer
	cap : integer -- vehicle capacity; 0 for waiting cargo
end

local record StopInfo
	group : Engine.Entity
	name : string
	x : number
	y : number
	waiting : {CargoCount} -- waiting at this stop for this line
end

local record LineInfo
	color : {number}
	stops : {StopInfo}
end

local record VehicleInfo
	id : Engine.Entity
	name : string
	prev : integer
	next : integer
	frac : number
	fill : number -- fullest cargo type, count / capacity
	cargo : {CargoCount}
	atStop : boolean
end

local record Canvas
	w : number
	h : number
	gameCtx : GameContext -- for hover popups; without a callout container: plain tooltips
	highlight : Engine.Entity -- if set, only this vehicle is drawn in full colour
end

-- hover popup content: a header, one row per cargo type (icon + text), an optional footer
local record InfoRow
	cargoType : integer
	text : string
end

local record Info
	header : string
	rows : {InfoRow}
	footer : string
end

---------------------------------------------------------------------------
-- small helpers
---------------------------------------------------------------------------

local function clamp(v : number, lo : number, hi : number) : number
	if v < lo then return lo end
	if v > hi then return hi end
	return v
end

local function lerp(a : number, b : number, t : number) : number
	return a + (b - a) * t
end

local function round(v : number, step : number) : number
	return math.floor(v / step + 0.5) * step
end

local function dist(ax : number, ay : number, bx : number, by : number) : number
	local dx, dy = bx - ax, by - ay
	return math.sqrt(dx * dx + dy * dy)
end

local function loadColor(frac : number) : {number}
	frac = clamp(frac, 0, 1)
	local a, b, t : {number}, {number}, number
	if frac < 0.5 then
		a, b, t = LOAD_EMPTY, LOAD_HALF, frac / 0.5
	else
		a, b, t = LOAD_HALF, LOAD_FULL, (frac - 0.5) / 0.5
	end
	return { lerp(a[1], b[1], t), lerp(a[2], b[2], t), lerp(a[3], b[3], t), 1.0 }
end

local function faded(color : {number}) : {number}
	return {
		lerp(color[1], FADE_TO[1], FADE_MIX),
		lerp(color[2], FADE_TO[2], FADE_MIX),
		lerp(color[3], FADE_TO[3], FADE_MIX),
		(color[4] or 1) * FADE_ALPHA,
	}
end

local function entityPosition(entity : Engine.Entity) : boolean, number, number
	if entity == nil or entity < 0 then return false, 0, 0 end
	local bv = api.engine.getComponent(entity, api.type.ComponentType.BOUNDING_VOLUME) as Engine.Component.BoundingVolume
	if bv == nil then return false, 0, 0 end
	return true, (bv.bbox.max.x + bv.bbox.min.x) * 0.5, (bv.bbox.max.y + bv.bbox.min.y) * 0.5
end

-- engine-bound arrays can throw on out-of-range access, so index them defensively
local function safeIndex<T>(arr : {T}, i : integer) : T
	local ok, v = pcall(function() : T return arr[i] end)
	if ok then return v end
	return nil
end

-- Display name of a cargo type (cargoTypeRep.getName returns the resource path, e.g.
-- "::/cargos/passengers/passengers.cargo"; vanilla's cargo_util uses get(id).name).
local cargoNames : {integer : string} = {}
local function cargoName(cargoType : integer) : string
	local cached = cargoNames[cargoType]
	if cached ~= nil then return cached end
	local name = _("Cargo")
	local ok, desc = pcall(api.res.cargoTypeRep.get, cargoType)
	if ok and desc ~= nil and type(desc.name) == "string" and desc.name ~= "" then
		name = desc.name
	end
	cargoNames[cargoType] = name
	return name
end

---------------------------------------------------------------------------
-- engine reads (return plain tables so the step states can deep-compare them)
---------------------------------------------------------------------------

-- cargo types this line actually carries, from its vehicles' configured capacities
local function lineCargoTypes(lineId : Engine.Entity) : {integer}
	local seen : {integer : boolean} = {}
	local types : {integer} = {}
	for __, vehicle in ipairs(api.engine.system.transportVehicleSystem.getLineVehicles(lineId)) do
		local tv = api.engine.getComponent(vehicle, api.type.ComponentType.TRANSPORT_VEHICLE) as Engine.Component.TransportVehicle
		if tv ~= nil and tv.config ~= nil and tv.config.capacities ~= nil then
			for i, capacity in ipairs(tv.config.capacities) do
				if capacity > 0 and not seen[i - 1] then
					seen[i - 1] = true
					types[#types + 1] = i - 1
				end
			end
		end
	end
	table.sort(types)
	return types
end

local function readLine(lineId : Engine.Entity) : LineInfo
	local line = api.engine.getComponent(lineId, api.type.ComponentType.LINE) as Engine.Component.Line
	if line == nil then return nil end

	local color : {number} = { 0.9, 0.8, 0.3, 1.0 }
	local colorComp = api.engine.getComponent(lineId, api.type.ComponentType.COLOR) as Engine.Component.Color
	if colorComp ~= nil and colorComp.color ~= nil then
		color = { colorComp.color.x, colorComp.color.y, colorComp.color.z, 1.0 }
	end

	local cargoTypes = lineCargoTypes(lineId)
	local stops : {StopInfo} = {}
	for i, stop in ipairs(line.stops) do
		local group = stop.stationGroup
		local found, x, y = false, 0.0, 0.0
		local sg = api.engine.getComponent(group, api.type.ComponentType.STATION_GROUP) as Engine.Component.StationGroup
		if sg ~= nil then
			local station = safeIndex(sg.stations, (stop.station or 0) + 1) or safeIndex(sg.stations, 1)
			if station ~= nil then
				found, x, y = entityPosition(station)
			end
		end
		if not found then
			found, x, y = entityPosition(group)
		end

		-- what is waiting at this stop for this line (stop index is 0-based, as in station_group.tl)
		local waiting : {CargoCount} = {}
		for __, cargoType in ipairs(cargoTypes) do
			local ok, raw = pcall(api.engine.system.simEntityAtTerminalSystem.getLineStopSimEntitiesCount, lineId, i - 1, cargoType)
			local count = (ok and type(raw) == "number") and math.floor(raw) or 0
			if count > 0 then waiting[#waiting + 1] = { cargoType = cargoType, count = count, cap = 0 } end
		end

		stops[#stops + 1] = {
			group = group,
			name = api.engine.util.getEntityName(group) or "?",
			x = round(x, 1),
			y = round(y, 1),
			waiting = waiting,
		}
	end

	return { color = color, stops = stops }
end

-- Per cargo type load, the way vanilla's cargo_util does it: config.capacities is indexed by
-- cargo type id + 1, paired with getVehicleSimEntitiesCountForCargoType(vehicle, id).
-- (Avoid `is integer` anywhere: it compiles to math.type, which the game's Lua 5.2 lacks.)
local function readCargo(vehicle : Engine.Entity, tv : Engine.Component.TransportVehicle) : {CargoCount}, number
	local cargo : {CargoCount} = {}
	local fill = 0.0
	if tv.config == nil or tv.config.capacities == nil then return cargo, fill end
	for i, capacity in ipairs(tv.config.capacities) do
		if capacity > 0 then
			local ok, raw = pcall(api.engine.system.simEntityAtVehicleSystem.getVehicleSimEntitiesCountForCargoType, vehicle, i - 1)
			local count = (ok and type(raw) == "number") and math.floor(raw) or 0
			cargo[#cargo + 1] = { cargoType = i - 1, count = count, cap = capacity }
			fill = math.max(fill, count / capacity)
		end
	end
	return cargo, fill
end

-- Fraction travelled from stop a to stop b: world position projected onto the straight a->b segment.
local function geometricFraction(px : number, py : number, a : StopInfo, b : StopInfo) : number
	local dx, dy = b.x - a.x, b.y - a.y
	local len2 = dx * dx + dy * dy
	if len2 < 1 then return 0.5 end
	return clamp(((px - a.x) * dx + (py - a.y) * dy) / len2, 0, 1)
end

-- How many departure-time units (gameTime, ms) one sectionTimes unit is worth: 1000 if section
-- times are seconds, 1 if they are ms. The API doesn't say, so compare the spread of departure
-- times across stops (roughly one lap) with the summed section times (one lap): the ratio is
-- ~1 for matching units and ~1000 otherwise. nil until the vehicle has a usable history.
local function sectionTimeScale(tv : Engine.Component.TransportVehicle, n : integer) : number
	local minDep, maxDep, sumSec = math.huge, -math.huge, 0.0
	local deps = 0
	for i = 1, n do
		local d = safeIndex(tv.lineStopDepartures, i)
		if d ~= nil and d > 0 then
			deps = deps + 1
			minDep, maxDep = math.min(minDep, d), math.max(maxDep, d)
		end
		local s = safeIndex(tv.sectionTimes, i)
		if s ~= nil and s > 0 then sumSec = sumSec + s end
	end
	if deps < 2 or sumSec <= 0 or maxDep <= minDep then return nil end
	return (maxDep - minDep) / sumSec > 30 and 1000 or 1
end

-- Fraction travelled from the last departure time and that section's recorded travel time.
-- Returns nil whenever the numbers don't look trustworthy (first lap, changed line, ...).
local function timeFraction(tv : Engine.Component.TransportVehicle, prevIdx : integer, n : integer, now : number) : number
	local dep = safeIndex(tv.lineStopDepartures, prevIdx)
	local sec = safeIndex(tv.sectionTimes, prevIdx)
	if dep == nil or sec == nil or dep <= 0 or sec <= 0 then return nil end
	local elapsed = now - dep
	if elapsed < 0 then return nil end
	local scale = sectionTimeScale(tv, n)
	if scale == nil then return nil end
	local f = elapsed / (sec * scale)
	if f > 1.5 then return nil end
	return clamp(f, 0, 0.99)
end

local function readVehicles(lineId : Engine.Entity, stops : {StopInfo}) : {VehicleInfo}
	local n = #stops
	local result : {VehicleInfo} = {}
	if n < 2 then return result end

	local gt = api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_TIME) as Engine.Component.GameTime
	local now : number = gt and gt.gameTime or 0

	for __, vehicle in ipairs(api.engine.system.transportVehicleSystem.getLineVehicles(lineId)) do
		local tv = api.engine.getComponent(vehicle, api.type.ComponentType.TRANSPORT_VEHICLE) as Engine.Component.TransportVehicle
		local enRoute = tv ~= nil and tv.state == api.type["enum"].TransportVehicleState.EN_ROUTE
		local atStop = tv ~= nil and tv.state == api.type["enum"].TransportVehicleState.AT_TERMINAL
		if enRoute or atStop then
			-- stopIndex is the 0-based stop the vehicle is heading to (or standing at)
			local nextIdx = math.floor(clamp((tv.stopIndex or 0) + 1, 1, n))
			local prevIdx = nextIdx - 1
			if prevIdx < 1 then prevIdx = n end

			local frac : number = 1
			if not atStop then
				frac = timeFraction(tv, prevIdx, n, now)
				if frac == nil then
					local ok, pos = pcall(api.engine.util.vehicle.getPosition, vehicle)
					if ok and pos ~= nil then
						frac = geometricFraction(pos.x, pos.y, stops[prevIdx], stops[nextIdx])
					end
				end
				frac = frac or 0.5
			end

			local cargo, fill = readCargo(vehicle, tv)

			result[#result + 1] = {
				id = vehicle,
				name = api.engine.util.getEntityName(vehicle) or "?",
				prev = prevIdx,
				next = nextIdx,
				frac = round(frac, 0.002),
				fill = round(fill, 0.01),
				cargo = cargo,
				atStop = atStop,
			}
		end
	end
	table.sort(result, function(a : VehicleInfo, b : VehicleInfo) : boolean return a.id < b.id end)
	return result
end

---------------------------------------------------------------------------
-- hover info (popup with cargo icons, or plain tooltip text as a fallback)
---------------------------------------------------------------------------

-- "Train 8" / [clay icon] "120/120 (100%)". The direction arrow on the strip shows where it is heading.
local function vehicleInfo(v : VehicleInfo) : Info
	local rows : {InfoRow} = {}
	local function add(c : CargoCount)
		local pct = math.floor(100 * c.count / c.cap + 0.5)
		rows[#rows + 1] = { cargoType = c.cargoType, text = tostring(c.count) .. "/" .. tostring(c.cap) .. " (" .. tostring(pct) .. "%)" }
	end
	for __, c in ipairs(v.cargo) do
		if c.count > 0 then add(c) end
	end
	-- an empty vehicle still shows its capacity, e.g. [passenger icon] "0/95 (0%)"
	if #rows == 0 and #v.cargo > 0 then add(v.cargo[1]) end
	return { header = v.name, rows = rows, footer = nil }
end

-- "Malton Station" / [icon] "34 waiting" ... or "Nothing waiting"
local function stationInfo(name : string, waitingLists : {{CargoCount}}) : Info
	local totals : {integer : integer} = {}
	local order : {integer} = {}
	for __, list in ipairs(waitingLists) do
		for __, c in ipairs(list) do
			if totals[c.cargoType] == nil then
				totals[c.cargoType] = 0
				order[#order + 1] = c.cargoType
			end
			totals[c.cargoType] = totals[c.cargoType] + c.count
		end
	end
	table.sort(order)
	local rows : {InfoRow} = {}
	for __, cargoType in ipairs(order) do
		rows[#rows + 1] = { cargoType = cargoType, text = tostring(totals[cargoType]) .. " " .. _("waiting") }
	end
	return { header = name, rows = rows, footer = #rows == 0 and _("Nothing waiting") or nil }
end

-- plain-text version for when no popup container is available
local function infoText(info : Info) : string
	local lines : {string} = { info.header }
	for __, row in ipairs(info.rows) do
		lines[#lines + 1] = cargoName(row.cargoType) .. ": " .. row.text
	end
	if info.footer ~= nil then lines[#lines + 1] = info.footer end
	return table.concat(lines, "\n")
end

-- popup body, shown inside the game's DefaultCalloutWrapper bubble
local LineInfoContent = react.RegisterRecipe("LukeLineInfo", function(info : Info) : TreeNodeId
	local children : {TreeNodeId} = {
		builtin.TextView{ meta = { class = "font-scale-body" }, text = info.header },
	}
	for __, row in ipairs(info.rows) do
		children[#children + 1] = builtin.BoxLayout{
			meta = { class = "luke-lt-row" },
			orientation = builtin.type.Orientation.Horizontal,
			children = {
				cargo_react_util.makeCargoIcon(row.cargoType, "luke-lt-cargo", nil, true),
				builtin.TextView{ meta = { class = "font-scale-body" }, text = row.text },
			},
		}
	end
	if info.footer ~= nil then
		children[#children + 1] = builtin.TextView{ meta = { class = "font-scale-annotation" }, text = info.footer }
	end
	return builtin.BoxLayout{
		meta = { class = "luke-lt-info" },
		orientation = builtin.type.Orientation.Vertical,
		children = children,
	}
end)

---------------------------------------------------------------------------
-- drawing primitives
---------------------------------------------------------------------------

local function circleImage() : NinePatch
	local patch = api.gui.NinePatch.new()
	patch.fileName = CIRCLE_IMAGE
	return patch
end

-- circle: vanilla's round line-colour dot, i.e. a circle image tinted with backgroundColor1
local function shapeStyle(w : number, h : number, color : {number}, circle : boolean) : StyleSheet
	if circle then
		return styleutil.makeStyle{ size = { w, h }, backgroundImage1 = circleImage(), backgroundColor1 = color }
	end
	return styleutil.makeStyle{ size = { w, h }, backgroundColor = color }
end

-- a non-interactive shape (mouse passes through, so it never blocks a marker's hover)
local function shape(w : number, h : number, color : {number}, circle? : boolean) : TreeNodeId
	return builtin.Component{
		mouseTransparent = true,
		meta = { styleSheet = shapeStyle(w, h, color, circle or false) },
	}
end

-- the d.tl types overflowMode as boolean, but vanilla (callout_container) passes this enum value
local KEEP_INSIDE = builtin.type.FloatingLayoutOverflowMode.KeepInside as any as boolean

-- Place an item of size (w, h) with its centre at (cx, cy) canvas pixels. h/v are gravity: the
-- item's left edge lands at h * (canvas width - w), as measured in-game (the end stations sat
-- 6 px inwards while the full-width track did not when this assumed h * canvas width).
local function place(canvas : Canvas, key : string, cx : number, cy : number, w : number, h : number, item : TreeNodeId) : TreeNodeId
	local hx = canvas.w > w and (cx - w * 0.5) / (canvas.w - w) or 0
	local vy = canvas.h > h and (cy - h * 0.5) / (canvas.h - h) or 0
	return builtin.FloatingLayoutChild{
		localKey = key,
		h = clamp(hx, 0, 1),
		v = clamp(vy, 0, 1),
		overflowMode = KEEP_INSIDE,
		item = item,
	}
end

local record MarkerParams
	size : number
	color : {number}
	info : Info
	gameCtx : GameContext
end

-- A round station or vehicle marker. Hovering it opens the game's callout bubble with the info
-- (cargo icons + text), the same hover pattern as vanilla's content_card InfoCalloutWrapper;
-- without a callout container it falls back to a plain-text tooltip.
local Marker = react.RegisterRecipe("LukeLineMarker", function(params : MarkerParams) : TreeNodeId
	local nodeRef = react.useNodeRef()
	local wantRef = react.useRef(false)
	local shownKeyRef = react.useRef("") -- "" = no popup shown
	local infoRef = react.useRef(params.info)
	infoRef:set(params.info)
	local hasCallouts = params.gameCtx ~= nil and params.gameCtx.calloutContainerRef ~= nil

	local function calloutApi() : CalloutApi
		if not hasCallouts then return nil end
		local ok, capi = pcall(function() : CalloutApi return params.gameCtx.calloutContainerRef:get():getApi() end)
		if ok then return capi end
		return nil
	end
	local function closePopup()
		if shownKeyRef:get() == "" then return end
		local capi = calloutApi()
		if capi ~= nil then pcall(capi.close, nodeRef) end
		shownKeyRef:set("")
	end

	react.onStep(function()
		if not wantRef:get() then return end
		local info = infoRef:get() as Info
		local key = infoText(info)
		if shownKeyRef:get() == key then return end
		local capi = calloutApi()
		if capi == nil then return end
		local ok = pcall(capi.open, {
			recipe = callout_react_util.DefaultCalloutWrapper,
			recipeParam = { recipe = LineInfoContent, recipeParam = info },
			anchor = api.type.Vec2f.new(0.5, 1.0),
			gravity = api.type.Vec2f.new(0.5, 0.0),
			parent = nodeRef,
		} as CalloutApi.CalloutParamsT<IRecipeParamWithMeta>)
		if ok then shownKeyRef:set(key) end
	end)
	react.onUnmount(function()
		closePopup()
	end)

	-- a recipe must return a layout ("Recipe child must be a layout" crashes the game UI), so the
	-- component is wrapped in a BoxLayout like every vanilla recipe does
	return builtin.BoxLayout{ child = builtin.Component(react.ref(nodeRef), {
		meta = {
			tooltip = not hasCallouts and infoText(params.info) or nil,
			styleSheet = shapeStyle(params.size, params.size, params.color, true),
			onAttention = function(attention : boolean)
				wantRef:set(attention)
				if not attention then closePopup() end
			end,
		},
	}) }
end)

-- A triangle (combobox arrow mask, tinted) whose flat base is centred at (baseX, cy) and whose tip
-- points dir (+1 right, -1 left), reaching w beyond the base, h tall. The mask image is stretched
-- so the triangle itself, not the padded 48x48 image, gets that size.
local function pointer(canvas : Canvas, key : string, baseX : number, cy : number, dir : number, w : number, h : number, color : {number}) : TreeNodeId
	local boxW = w / MASK_W
	local boxH = h / MASK_H
	local baseFrac = dir > 0 and MASK_BASE or (1 - MASK_BASE)
	local centerX = baseX - baseFrac * boxW + boxW * 0.5
	return place(canvas, key, centerX, cy, boxW, boxH, builtin.Component{
		mouseTransparent = true,
		meta = { styleSheet = styleutil.makeStyle{ size = { boxW, boxH } } },
		layout = builtin.BoxLayout{ child = builtin.ImageView{
			path = dir > 0 and ARROW_RIGHT_IMAGE or ARROW_LEFT_IMAGE,
			scaling = builtin.type.ImageViewScaling.Stretch,
			meta = { styleSheet = styleutil.makeStyle{ size = { boxW, boxH }, color = color } },
		} },
	})
end

---------------------------------------------------------------------------
-- the route strip
---------------------------------------------------------------------------

-- stops that refer to the same station group only get one marker; waiting cargo is summed
local function uniqueStations(stops : {StopInfo}) : {StopInfo}, {integer}, {{{CargoCount}}}
	local seen : {Engine.Entity : integer} = {}
	local list : {StopInfo} = {}
	local indexOf : {integer} = {}
	local waitingOf : {{{CargoCount}}} = {}
	for i, s in ipairs(stops) do
		if seen[s.group] == nil then
			list[#list + 1] = s
			seen[s.group] = #list
			waitingOf[#list] = {}
		end
		local u = seen[s.group]
		indexOf[i] = u
		local w = waitingOf[u]
		w[#w + 1] = s.waiting
	end
	return list, indexOf, waitingOf
end

-- One straight line with the stations in order of first visit, spaced by real distance (with a
-- minimum gap). Stations are circles in the line colour with a white centre. Vehicles ride on the
-- line as load-coloured teardrops: a circle with a pointed tip towards where they are heading.
local function buildRoute(canvas : Canvas, line : LineInfo, vehicles : {VehicleInfo}) : {TreeNodeId}
	local stops = line.stops
	local unique, indexOf, waitingOf = uniqueStations(stops)
	local count = #unique
	local n = #stops

	local gaps : {number} = {}
	local totalGap = 0.0
	for i = 2, count do
		local a, b = unique[i - 1], unique[i]
		gaps[i] = math.max(dist(a.x, a.y, b.x, b.y), 1)
		totalGap = totalGap + gaps[i]
	end
	local usable = canvas.w - 2 * PAD
	local minGap = math.min(STATION_SIZE + 6, usable / math.max(count - 1, 1))
	-- on very long lines the stations get closer than a marker is wide; shrink them to fit
	local stationSize = math.floor(clamp(minGap - 2, 6, STATION_SIZE))
	local dotSize = math.max(2, math.floor(stationSize * STATION_DOT / STATION_SIZE))
	local flexible = usable - minGap * math.max(count - 1, 0)
	local xs : {number} = { PAD }
	for i = 2, count do
		xs[i] = xs[i - 1] + minGap + (totalGap > 0 and flexible * gaps[i] / totalGap or 0)
	end
	if count == 1 then xs[1] = canvas.w * 0.5 end

	local midY = canvas.h * 0.5
	local children : {TreeNodeId} = {}

	-- track: from the first to the last station centre, so its ends stay under the end circles
	local x0, x1 = xs[1], xs[count]
	if x1 - x0 >= 1 then
		children[#children + 1] = place(canvas, "track", (x0 + x1) * 0.5, midY, x1 - x0, TRACK_THICKNESS, shape(x1 - x0, TRACK_THICKNESS, line.color))
	end

	for i, s in ipairs(unique) do
		children[#children + 1] = place(canvas, "st" .. i, xs[i], midY, stationSize, stationSize, Marker{
			size = stationSize,
			color = line.color,
			info = stationInfo(s.name, waitingOf[i]),
			gameCtx = canvas.gameCtx,
		})
		children[#children + 1] = place(canvas, "stDot" .. i, xs[i], midY, dotSize, dotSize, shape(dotSize, dotSize, COLOR_STATION_DOT, true))
	end

	local outline = VEHICLE_SIZE + 2 * VEHICLE_OUTLINE
	local r = VEHICLE_SIZE * 0.5
	-- the tip's base sits where the circle is exactly POINTER_H tall, so the two blend into one shape
	local baseInset = math.sqrt(math.max(r * r - (POINTER_H * 0.5) ^ 2, 0))
	-- with a highlighted vehicle, draw it last so it sits on top of the faded others
	local ordered : {VehicleInfo} = {}
	for __, v in ipairs(vehicles) do
		if v.id ~= canvas.highlight then ordered[#ordered + 1] = v end
	end
	for __, v in ipairs(vehicles) do
		if v.id == canvas.highlight then ordered[#ordered + 1] = v end
	end
	for __, v in ipairs(ordered) do
		local xa, xb = xs[indexOf[v.prev]], xs[indexOf[v.next]]
		local x = lerp(xa, xb, v.frac)
		-- heading: the section it is on; a vehicle standing at a stop heads to the stop after it
		local fromX, toX = xa, xb
		if v.atStop then
			fromX, toX = xs[indexOf[v.next]], xs[indexOf[(v.next % n) + 1]]
		end
		local key = tostring(v.id)
		local dim = canvas.highlight ~= nil and v.id ~= canvas.highlight
		local color = loadColor(v.fill)
		local outlineColor = COLOR_VEHICLE_OUTLINE
		if dim then
			color = faded(color)
			outlineColor = { COLOR_VEHICLE_OUTLINE[1], COLOR_VEHICLE_OUTLINE[2], COLOR_VEHICLE_OUTLINE[3], FADE_ALPHA }
		end
		local dir = 0
		if math.abs(toX - fromX) >= 0.5 then dir = toX > fromX and 1 or -1 end
		-- dark outline first (circle + tip, 1 px larger), then the load-coloured teardrop on top
		children[#children + 1] = place(canvas, "vehO" .. key, x, midY, outline, outline, shape(outline, outline, outlineColor, true))
		if dir ~= 0 then
			children[#children + 1] = pointer(canvas, "vehPO" .. key, x + dir * (baseInset - VEHICLE_OUTLINE), midY, dir,
				POINTER_W + 2 * VEHICLE_OUTLINE, POINTER_H + 2 * VEHICLE_OUTLINE + 1, outlineColor)
			children[#children + 1] = pointer(canvas, "vehP" .. key, x + dir * baseInset, midY, dir, POINTER_W, POINTER_H, color)
		end
		children[#children + 1] = place(canvas, "veh" .. key, x, midY, VEHICLE_SIZE, VEHICLE_SIZE, Marker{
			size = VEHICLE_SIZE,
			color = color,
			info = vehicleInfo(v),
			gameCtx = canvas.gameCtx,
		})
	end
	return children
end

---------------------------------------------------------------------------
-- map content (shared by the line window card and the line manager card)
---------------------------------------------------------------------------

local function legend(vehicleCount : integer) : TreeNodeId
	local children : {TreeNodeId} = {
		builtin.TextView{ meta = { class = "font-scale-annotation" }, text = _("Empty") },
	}
	for i = 0, 4 do
		children[#children + 1] = builtin.Component{ meta = { styleSheet = shapeStyle(14, 8, loadColor(i / 4), false) } }
	end
	children[#children + 1] = builtin.TextView{ meta = { class = "font-scale-annotation" }, text = _("Full") }
	children[#children + 1] = builtin.Component{ meta = { styleSheet = shapeStyle(24, 1, { 0, 0, 0, 0 }, false) } }
	children[#children + 1] = builtin.TextView{
		meta = { class = "font-scale-annotation" },
		text = tostring(vehicleCount) .. " " .. _("vehicles"),
	}
	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Horizontal,
		children = children,
	}
end

local record ContentParams
	lineId : Engine.Entity
	width : number
	gameCtx : GameContext
	highlight : Engine.Entity -- optional: only this vehicle in full colour
end

local LineTrackerContent = react.RegisterRecipe("LukeLineTrackerContent", function(params : ContentParams) : TreeNodeId
	local lineId = params.lineId
	-- stops, colour and waiting cargo change slowly, so poll them once a second
	local lineState = engine_react_util.useStepStateTimer(function() : LineInfo
		return readLine(lineId)
	end, LINE_REFRESH_SECONDS)
	local vehicleState = engine_react_util.useStepStateTimer(function() : {VehicleInfo}
		local line = api.engine.getComponent(lineId, api.type.ComponentType.LINE) as Engine.Component.Line
		if line == nil then return {} end
		-- vehicles only need stop positions; skip the waiting-cargo queries of a full readLine
		local stops : {StopInfo} = {}
		local info = lineState:old()
		if info ~= nil and #info.stops == #line.stops then stops = info.stops else stops = (readLine(lineId) or {}).stops or {} end
		return readVehicles(lineId, stops)
	end, REFRESH_SECONDS)

	local line = lineState:old()
	local vehicles = vehicleState:old() or {}

	local canvasNode : TreeNodeId
	local shown = 0
	if line == nil or #line.stops < 2 then
		canvasNode = builtin.TextView{
			meta = { class = "font-scale-body" },
			text = _("Add at least two stops to see the line map."),
		}
	else
		-- vehicle data can briefly lag a stop-list edit; drop anything pointing at missing stops
		local valid : {VehicleInfo} = {}
		for __, v in ipairs(vehicles) do
			if line.stops[v.prev] ~= nil and line.stops[v.next] ~= nil then valid[#valid + 1] = v end
		end
		shown = #valid

		local canvas : Canvas = { w = params.width, h = ROUTE_H, gameCtx = params.gameCtx, highlight = params.highlight }
		local children = buildRoute(canvas, line, valid)

		-- A FloatingLayout only grows to fit its children, so without this full-size first child
		-- it collapses to the size of one marker. Vanilla uses the same h = -1, v = -1 (stretch)
		-- base child, e.g. in construction.tl.
		table.insert(children, 1, builtin.FloatingLayoutChild{
			localKey = "background",
			h = -1,
			v = -1,
			item = shape(canvas.w, canvas.h, COLOR_BACKGROUND),
		})

		-- Clipper (vanilla gui_react_util) keeps the drawing inside the canvas, e.g. when the line
		-- window is scrolled and the canvas is partly out of view
		canvasNode = builtin.Component{
			meta = { styleSheet = styleutil.makeStyle{ size = { canvas.w, canvas.h } } },
			layout = builtin.BoxLayout{
				child = gui_react_util.Clipper{
					layout = builtin.FloatingLayout{ children = children },
				},
			},
		}
	end

	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Vertical,
		children = {
			canvasNode,
			legend(shown),
		},
	}
end)

---------------------------------------------------------------------------
-- 1. card in the line window
---------------------------------------------------------------------------

local LineTrackerPlugin = react.RegisterPluginRecipe(line_eow.LineEowExtensionPoint, "LukeLineTrackerPlugin", function(params : LineEow.LineWidgetPluginParams) : TreeNodeId
	return builtin.BoxLayout{
		child = content_card.ContentCard{
			meta = { localKey = "lukeLineTracker" },
			title = _("Line Map"),
			initialCalloutTextPermanent = "",
			recipeAndParamPermanent = content_card.makeRecipeAndParam(LineTrackerContent, { lineId = params.entityId, width = CARD_W, gameCtx = params.gameCtx }),
			gameCtx = params.gameCtx,
			showOnRightSide = params.showCalloutOnRightSide,
		}
	}
end)

---------------------------------------------------------------------------
-- 2. card right below the stop list in the line manager
--
-- The line manager keeps its selection private, so its exported LineManagerPanel recipe (the
-- stop list of the open line) is replaced, before the UI starts (doReplace), by a pass-through:
-- it builds the original stop list with the very same arguments (ref included) and adds the
-- route card under it. The open line comes from params.commonParams.lineState.
---------------------------------------------------------------------------

local record ManagerCardParams
	lineState : ReactStateT<Line.ReactLine>
	gameCtx : GameContext
end

local function lineOf(lineState : ReactStateT<Line.ReactLine>) : Engine.Entity
	if lineState == nil then return nil end
	local ok, entity = pcall(function() : Engine.Entity
		if lineState:hasExpired() then return nil end
		local reactLine = lineState:old()
		return reactLine and reactLine.entityAndRevision and reactLine.entityAndRevision.entity or nil
	end)
	if not ok then return nil end
	return entity
end

local ManagerRouteCard = react.RegisterRecipe("LukeManagerRoute", function(params : ManagerCardParams) : TreeNodeId
	local lineState = engine_react_util.useStepStateTimer(function() : Engine.Entity
		return lineOf(params.lineState)
	end, 0.1)
	local line = lineState:old()
	if line == nil then
		return builtin.BoxLayout{}
	end
	return builtin.BoxLayout{
		child = builtin.Component{
			meta = { class = "luke-lt-manager-card" },
			layout = builtin.BoxLayout{
				-- a new localKey per line gives each line fresh state instead of briefly showing the old one
				child = LineTrackerContent{ meta = { localKey = "line" .. tostring(line) }, lineId = line, width = MANAGER_W, gameCtx = params.gameCtx } as TreeNodeId,
			},
		},
	}
end)

-- pass-through replacement for LineManagerPanel, called with the raw (ref, params) arguments
local function lineManagerPanelWithRoute(...: any) : TreeNodeId
	local original = (react as any as {string : function(...: any) : TreeNodeId}).CallOriginalRecipe(LineManagerPanel as any, ...)
	local cardParams : ManagerCardParams = nil
	for __, a in ipairs({ ... }) do
		local params = a as LineManagerPanelParams
		if type(a) == "table" and params.commonParams ~= nil and params.commonParams.lineState ~= nil then
			cardParams = { lineState = params.commonParams.lineState, gameCtx = params.commonParams.gameCtx }
		end
	end
	if cardParams == nil then return original end
	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Vertical,
		children = {
			original,
			ManagerRouteCard(cardParams),
		},
	}
end

local function doReplace(replacementApi : ReactReplacementApi)
	local ok, err : boolean, any = pcall(function()
		replacementApi.ReplaceRecipe(LineManagerPanel, lineManagerPanelWithRoute as any as Recipe<LineManagerPanelParams>)
	end)
	if not ok then log.warning("Line Tracker: could not hook the line manager: " .. tostring(err)) end
end

---------------------------------------------------------------------------
-- 3. card in the vehicle window: the vehicle's line, this vehicle in full colour
---------------------------------------------------------------------------

local record VehicleCardParams
	vehicleId : Engine.Entity
	gameCtx : GameContext
end

-- the line the vehicle is serving, or nil (in or heading to a depot, or no line)
local function lineOfVehicle(vehicleId : Engine.Entity) : Engine.Entity
	local tv = api.engine.getComponent(vehicleId, api.type.ComponentType.TRANSPORT_VEHICLE) as Engine.Component.TransportVehicle
	if tv == nil then return nil end
	local onLine = tv.state == api.type["enum"].TransportVehicleState.EN_ROUTE or tv.state == api.type["enum"].TransportVehicleState.AT_TERMINAL
	if not onLine or tv.line == nil or tv.line < 0 then return nil end
	return tv.line
end

local VehicleRouteCard = react.RegisterRecipe("LukeVehicleRoute", function(params : VehicleCardParams) : TreeNodeId
	local lineState = engine_react_util.useStepStateTimer(function() : Engine.Entity
		return lineOfVehicle(params.vehicleId)
	end, LINE_REFRESH_SECONDS)
	local line = lineState:old()
	if line == nil then
		return builtin.BoxLayout{
			child = builtin.TextView{ meta = { class = "font-scale-body" }, text = _("Not running on a line.") },
		}
	end
	return builtin.BoxLayout{
		-- a new localKey per line gives a line change fresh state instead of briefly showing the old one
		child = LineTrackerContent{ meta = { localKey = "line" .. tostring(line) }, lineId = line, width = CARD_W, gameCtx = params.gameCtx, highlight = params.vehicleId } as TreeNodeId,
	}
end)

local VehicleLinePlugin = react.RegisterPluginRecipe(vehicle_eow.VehicleEowExtensionPoint, "LukeVehicleLinePlugin", function(params : VehicleEow.VehicleWidgetPluginParams) : TreeNodeId
	return builtin.BoxLayout{
		child = content_card.ContentCard{
			meta = { localKey = "lukeVehicleLine" },
			title = _("Line Map"),
			initialCalloutTextPermanent = "",
			recipeAndParamPermanent = content_card.makeRecipeAndParam(VehicleRouteCard, { vehicleId = params.entityId, gameCtx = params.gameCtx }),
			gameCtx = params.gameCtx,
			showOnRightSide = params.showCalloutOnRightSide,
		}
	}
end)


local result = {
	LineTrackerPlugin = LineTrackerPlugin,
	VehicleLinePlugin = VehicleLinePlugin,
	doReplace = doReplace,
}

return result
