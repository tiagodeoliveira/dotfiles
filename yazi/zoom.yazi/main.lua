--- @since 26.1.22

-- Forked from https://github.com/yazi-rs/plugins/tree/main/zoom.yazi --
-- crop-based zoom-in, panning, and a higher zoom ceiling are local additions.

ya.clone = ya.clone or Url -- TODO: remove

local MAX_LEVEL = 30

local get = ya.sync(function(st, url)
	if st.last ~= url then
		return
	end
	return st.level, st.pan_x or 0, st.pan_y or 0
end)

local save = ya.sync(function(st, url, new)
	local h = cx.active.current.hovered
	if h and h.url == url then
		st.last, st.level, st.pan_x, st.pan_y = url, new.level, new.pan_x, new.pan_y
		return true
	end
end)

local lock = ya.sync(function(st, url, old, new)
	if st.last == url and st.level == old.level and (st.pan_x or 0) == old.pan_x and (st.pan_y or 0) == old.pan_y then
		st.level, st.pan_x, st.pan_y = new.level, new.pan_x, new.pan_y
		return true
	end
end)

local move = ya.sync(function(st)
	local h = cx.active.current.hovered
	if not h then
		return
	end

	if st.last ~= h.url then
		st.last, st.level, st.pan_x, st.pan_y = ya.clone(h.url), 0, 0, 0
	end

	return { url = h.url, level = st.level, pan_x = st.pan_x or 0, pan_y = st.pan_y or 0 }
end)

local function end_(job, err)
	if not job.old then
		ya.preview_widget(job, err and ui.Text(err):area(job.area):wrap(ui.Wrap.YES))
	elseif err then
		ya.notify { title = "Zoom", content = tostring(err), timeout = 5, level = "error" }
	end
end

local function canvas(area)
	local cw, ch = rt.term.cell_size()
	if not cw then
		return rt.preview.max_width, rt.preview.max_height
	end

	return math.min(rt.preview.max_width, math.floor(area.w * cw)),
		math.min(rt.preview.max_height, math.floor(area.h * ch))
end

local function peek(_, job)
	local url = job.file.url
	local info, err = ya.image_info(url)
	if not info then
		return end_(job, Err("Failed to get image info: %s", err))
	end

	local got_level, got_pan_x, got_pan_y = get(ya.clone(url))
	local level = ya.clamp(-MAX_LEVEL, (job.new and job.new.level) or got_level or tonumber(job.args[1]) or 0, MAX_LEVEL)
	local pan_x = (job.new and job.new.pan_x) or got_pan_x or 0
	local pan_y = (job.new and job.new.pan_y) or got_pan_y or 0
	local sync = function()
		if job.old then
			return lock(url, job.old, { level = level, pan_x = pan_x, pan_y = pan_y })
		else
			return save(url, { level = level, pan_x = pan_x, pan_y = pan_y })
		end
	end

	local max_w, max_h = canvas(job.area)
	local min_w, min_h = math.min(max_w, info.w), math.min(max_h, info.h)
	local new_w = min_w + math.floor(min_w * level * 0.1)
	local new_h = min_h + math.floor(min_h * level * 0.1)

	-- Zooming in past the pane's max size can't render a bigger image than
	-- the pane -- crop a smaller window of the source instead and scale it
	-- up to fill the pane, so zoom-in still has a visible effect. pan_x/pan_y
	-- (-1..1, 0 = centered) shift that crop window within the source.
	local crop_w, crop_h, crop_x, crop_y
	if new_w > max_w or new_h > max_h then
		crop_w = new_w > max_w and math.floor(info.w * max_w / new_w) or info.w
		crop_h = new_h > max_h and math.floor(info.h * max_h / new_h) or info.h
		crop_x = math.floor((info.w - crop_w) / 2 * (1 + pan_x))
		crop_y = math.floor((info.h - crop_h) / 2 * (1 + pan_y))
		new_w, new_h = max_w, max_h
	end

	local tmp = os.tmpname()
	local args = { tostring(job.file.path), "-auto-orient", "-strip" }
	if crop_w and crop_h then
		table.insert(args, "-crop")
		table.insert(args, string.format("%dx%d+%d+%d", crop_w, crop_h, crop_x, crop_y))
		table.insert(args, "+repage")
	end
	table.insert(args, "-sample")
	table.insert(args, string.format("%dx%d", new_w, new_h))
	table.insert(args, "-quality")
	table.insert(args, rt.preview.image_quality)
	table.insert(args, string.format("WEBP:%s", tmp))

	local output, err = Command("magick"):arg(args):output()

	if not output then
		end_(job, Err("Failed to start `magick`, error: %s", err))
	elseif not output.status.success then
		end_(job, Err("`magick` exited with error code %s: %s", output.status.code, output.stderr))
	elseif sync() then
		ya.image_show(Url(tmp), job.area)
	end
	end_(job)
end

local PAN_STEP = 0.2
local PAN_DIRS = {
	left = { -1, 0 },
	right = { 1, 0 },
	up = { 0, -1 },
	down = { 0, 1 },
}

local function entry(self, job)
	local st = move()
	if not st then
		return
	end

	local dir = PAN_DIRS[job.args[1]]
	local new_level, new_pan_x, new_pan_y
	if dir then
		if st.level <= 0 then
			return -- nothing to pan across when not zoomed in
		end
		new_level = st.level
		new_pan_x = ya.clamp(-1, st.pan_x + dir[1] * PAN_STEP, 1)
		new_pan_y = ya.clamp(-1, st.pan_y + dir[2] * PAN_STEP, 1)
	else
		local motion = tonumber(job.args[1]) or 0
		new_level = ya.clamp(-MAX_LEVEL, st.level + motion, MAX_LEVEL)
		if new_level == st.level then
			return
		end
		-- Re-center once fully zoomed back out.
		new_pan_x = new_level == 0 and 0 or st.pan_x
		new_pan_y = new_level == 0 and 0 or st.pan_y
	end

	Stat = Stat or Cha -- TODO: remove
	local stat = Stat { mode = tonumber("100644", 8) }
	peek(self, {
		area = ui.area("preview"),
		args = {},
		file = File { url = st.url, cha = stat, stat = stat, lstat = stat }, -- TODO: remove `cha`
		skip = 0,
		old = { level = st.level, pan_x = st.pan_x, pan_y = st.pan_y },
		new = { level = new_level, pan_x = new_pan_x, pan_y = new_pan_y },
	})
end

return { peek = peek, entry = entry }
