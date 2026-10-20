local ssu = require "::/gui/main/stylesheetutil.lua"

-- Classes in this game are written !name.
function data()
	local result = { }
	local a = ssu.makeAdder(result)

	local colorDefault = api.gui.genericRep.get(api.gui.genericRep.find("::/gui/main/default_colors.gres")).data

	-- hover popup content (inside the game's DefaultCalloutWrapper bubble)
	a("BoxLayout!luke-lt-info", { innerSpacing = { 0, 4 } })
	a("BoxLayout!luke-lt-row", { innerSpacing = { 6, 0 } })
	a("ImageView!luke-lt-cargo", { size = { 18, 18 }, gravity = { 0, 0.5 } })

	-- Route card under the line manager's stop list: same card look as the manager's line panel
	-- (line_vehicle_mgmt.css.lua, R::LinePanel), a gap above it and a slim margin to the sides.
	a("Component!luke-lt-manager-card", {
		backgroundImage1 = {
			fileName = "::/gui/entity_window/design/card_surface.tga",
			horizontal = { 0, 6, 26, 32 },
			vertical = { 0, 6, 26, 32 }
		},
		borderImage = {
			fileName = "::/gui/entity_window/design/card_contour.tga",
			horizontal = { 0, 6, 26, 32 },
			vertical = { 0, 6, 26, 32 }
		},
		borderColor = colorDefault.BaseVeryLight,
		backgroundColor1 = colorDefault.BaseDark,
		padding = { 6, 8, 6, 8 },
		margin = { 8, 4, 4, 4 },
	})

	-- Let info windows grow taller than the vanilla 900 px before they scroll, so a line window
	-- with the Line Map card fits without scrolling. Windows only grow as far as their content.
	a("Window!entity-window", {
		maxSize = { 450, 1300 },
	})

	return result
end
