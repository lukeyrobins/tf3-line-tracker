function data()
	return {
		type = "react-plugin ::LineEowExtensionPoint",
		data = {
			filePath = "luke_line_tracker_1::/gui/line_tracker/line_tracker.script@LineTrackerPlugin",
			-- vanilla Balance (income graph) is 60, so this lands directly below it
			order = 70,
		}
	}
end
