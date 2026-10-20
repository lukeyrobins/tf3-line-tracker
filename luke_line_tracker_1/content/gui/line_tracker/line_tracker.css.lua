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

	-- Make the line manager taller by the height of the Line Map card, so the card fits under the
	-- stop list instead of being squeezed into its scroll area. Vanilla values (line_vehicle_mgmt.css.lua):
	-- line panel 360 px (lvmSectionLargeMaxHeight), whole content at most 894 px (lvmWindowHeight).
	-- Scoped to #menu.management so these win over the vanilla rules.
	local lineMapCardHeight = 140 -- heading + 40 px map + legend + card padding and margins
	a("#menu.management R::LinePanel", {
		size = { -1, 360 + lineMapCardHeight },
	})
	a("#menu.management R::ManagerWindowContent", {
		maxSize = { 500, 894 + lineMapCardHeight },
	})

	-- Let info windows grow taller than the vanilla 900 px before they scroll, so a line window
	-- with the Line Map card fits without scrolling. Windows only grow as far as their content.
	a("Window!entity-window", {
		maxSize = { 450, 1300 },
	})

	return result
end
