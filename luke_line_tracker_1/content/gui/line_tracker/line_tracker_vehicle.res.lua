function data()
	return {
		type = "react-plugin ::VehicleEowExtensionPoint",
		data = {
			filePath = "luke_line_tracker_1::/gui/line_tracker/line_tracker.script@VehicleLinePlugin",
			-- vanilla Balance (the last vehicle section) is 70, so this lands directly below it
			order = 80,
		}
	}
end
