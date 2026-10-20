function data()
	return {
		-- lets the mod see which line the line manager is showing (see doReplace in the script)
		type = "react-replacement-config",
		data = {
			filePath = "luke_line_tracker_1::/gui/line_tracker/line_tracker.script",
			doReplaceFn = "doReplace",
		},
	}
end
