local ssu = require "::/gui/main/stylesheetutil.lua"

-- Classes in this game are written !name.
function data()
	local result = { }
	local a = ssu.makeAdder(result)

	-- exact placement rows on the line map: [lead spacer][item][filler], no extra spacing, and the
	-- lead spacer keeps exactly the width the script gives it
	a("BoxLayout!luke-lt-pos", { innerSpacing = { 0, 0 }, padding = { 0, 0, 0, 0 }, margin = { 0, 0, 0, 0 } })
	a("Component!luke-lt-lead", { gravity = { 0, 0.5 }, padding = { 0, 0, 0, 0 }, margin = { 0, 0, 0, 0 } })

	-- hover popup content (inside the game's DefaultCalloutWrapper bubble)
	a("BoxLayout!luke-lt-info", { innerSpacing = { 0, 4 } })
	a("BoxLayout!luke-lt-row", { innerSpacing = { 6, 0 } })
	a("ImageView!luke-lt-cargo", { size = { 18, 18 }, gravity = { 0, 0.5 } })

	-- Route card under the line manager's stop list: just spacing around the game's own ContentCard
	-- (which draws the "Line Map" heading and the card outline, like in the line and vehicle windows)
	a("Component!luke-lt-manager-card", {
		margin = { 8, 4, 4, 4 },
	})

	-- Let info windows grow taller than the vanilla 900 px before they scroll, so a line window
	-- with the Line Map card fits without scrolling. Windows only grow as far as their content.
	a("Window!entity-window", {
		maxSize = { 450, 1300 },
	})

	return result
end
