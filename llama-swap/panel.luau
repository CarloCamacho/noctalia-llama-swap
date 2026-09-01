--!nonstrict

-- llama-swap manager panel: tok/s sparkline header, compact recent activity,
-- one-line model rows with inline load/unload.

local serverUrlRaw = noctalia.getConfig("server_url")
local apiKeyRaw = noctalia.getConfig("api_key")

local status = "unconfigured"
local models = {}
local stats = nil
local activity = {}
local tpsHistory = {}
local pendingLocal = {}   -- id -> true, loads this panel requested

local function tr(key, subst)
  return noctalia.tr("panel." .. key, subst)
end

local function getCleanUrl()
  if type(serverUrlRaw) ~= "string" then return "" end
  return (serverUrlRaw:gsub("/$", ""):gsub("%s+$", ""))
end

local function getCleanKey()
  if type(apiKeyRaw) ~= "string" then return "" end
  return noctalia.string.trim(apiKeyRaw)
end

-- -------------------------------------------------------------- state sync

noctalia.state.watch("status", function(v) status = v or "unconfigured"; panelRender() end)
noctalia.state.watch("models", function(v) models = type(v) == "table" and v or {}; panelRender() end)
noctalia.state.watch("stats", function(v) stats = type(v) == "table" and v or nil; panelRender() end)
noctalia.state.watch("activity", function(v) activity = type(v) == "table" and v or {}; panelRender() end)
noctalia.state.watch("req_tokens_history", function(v) tpsHistory = type(v) == "table" and v or {}; panelRender() end)

-- -------------------------------------------------------------- actions

local function llamaRequest(path, method, callback)
  local url = getCleanUrl()
  if url == "" then
    if callback then callback({ ok = false, status = 0 }) end
    return
  end

  local headers = {}
  local key = getCleanKey()
  if key ~= "" then
    table.insert(headers, "Authorization: Bearer " .. key)
  end

  noctalia.http({
      url = url .. path,
      method = method,
      headers = headers,
    }, function(response: HttpResponse)
      local ok = response and response.status >= 200 and response.status < 300
      if callback then callback({ ok = ok, status = response and response.status or 0 }) end
    end)
end

-- Loading = warm the upstream; llama-swap starts the process and /v1/models
-- status flips to "loaded" (the service poller picks it up).
local function loadModel(id)
  pendingLocal[id] = true
  panelRender()

  local url = getCleanUrl()
  local headers = {}
  local key = getCleanKey()
  if key ~= "" then table.insert(headers, "Authorization: Bearer " .. key) end

  noctalia.http({
      url = url .. "/upstream/" .. id .. "/v1/models",
      method = "GET",
      headers = headers,
    }, function(response: HttpResponse)
      if not response or response.status < 200 or response.status >= 300 then
        pendingLocal[id] = nil
        noctalia.notifyError(noctalia.tr("notifications.load_failed", { model = id }))
        panelRender()
      end
      -- on success keep the pending flag until the poller sees "ready"
    end)
end

local function unloadModel(id)
  pendingLocal[id] = nil
  -- /api/models/unload/<id> — id may contain slashes, use the wildcard form
  llamaRequest("/api/models/unload/" .. id, "POST", function(res)
    if not res.ok then
      noctalia.notifyError(noctalia.tr("notifications.unload_failed", { model = id }))
    end
    panelRender()
  end)
end

-- -------------------------------------------------------------- formatting

local function fmtTps(v)
  if not v or v <= 0 then return "–" end
  if v >= 100 then return string.format("%.0f", v) end
  return string.format("%.1f", v)
end

local function fmtTokens(n)
  if n >= 1000000 then return string.format("%.1fM", n / 1000000) end
  if n >= 1000 then return string.format("%.1fk", n / 1000) end
  return tostring(n)
end

local function fmtDuration(ms)
  if ms >= 1000 then return string.format("%.1fs", ms / 1000) end
  return string.format("%dms", ms)
end

local function relativeTime(ts)
  local y, mo, d, h, mi, s = ts:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
  if not y then return "" end
  local t = os.time({ year = y, month = mo, day = d, hour = h, min = mi, sec = s, isdst = false })
  local age = os.time() - t
  if age < 0 then age = 0 end
  if age < 60 then return tr("time_now") end
  if age < 3600 then return tr("time_min", { n = math.floor(age / 60) }) end
  if age < 86400 then return tr("time_hour", { n = math.floor(age / 3600) }) end
  return tr("time_day", { n = math.floor(age / 86400) })
end

local function statusColor()
  if status == "connected" then return "primary" end
  if status == "auth_failed" or status == "unreachable" or status == "error" then return "error" end
  return "on_surface_variant"
end

local function statusText()
  if status == "connected" then return tr("status_connected")
  elseif status == "auth_failed" then return tr("status_auth_failed")
  elseif status == "unreachable" then return tr("status_unreachable")
  elseif status == "error" then return tr("status_error")
  else return tr("status_unconfigured") end
end

-- -------------------------------------------------------------- UI builders

local function headerSection()
  local children = {}

  table.insert(children, ui.row({ align = "center", gap = 8 }, {
    ui.glyph({ name = "cpu", size = 16, color = statusColor() }),
    ui.label({ text = "llama-swap", fontWeight = "bold" }),
    ui.spacer({}),
    ui.label({ text = statusText(), color = statusColor(), fontSize = 11 }),
  }))

  local s = stats
  if status == "connected" and s then
    -- plain-language summary: last tok/s, total work done
    local lastTps = tpsHistory[#tpsHistory] or 0
    local line = tr("summary_line", {
      last_tps = fmtTps(lastTps),
      requests = tostring(s.requests or 0),
      out_tokens = fmtTokens(s.output_tokens or 0),
    })
    table.insert(children, ui.label({ text = line, color = "on_surface_variant", fontSize = 11 }))
    table.insert(children, ui.graph({
      values = tpsHistory,
      color = "primary",
      fillOpacity = 0.2,
      lineWidth = 2,
      height = 36,
    }))
    table.insert(children, ui.label({
      text = tr("spark_caption", { count = tostring(#tpsHistory) }),
      fontSize = 9,
      color = "on_surface_variant",
    }))
  elseif status == "connected" then
    table.insert(children, ui.label({ text = tr("summary_no_data"), color = "on_surface_variant", fontSize = 11 }))
  else
    table.insert(children, ui.label({ text = statusText(), color = "on_surface_variant", fontSize = 11 }))
  end

  return ui.column({ gap = 6 }, children)
end

-- One compact line per request: tok/s · model · duration · when
local function activitySection()
  if status ~= "connected" or #activity == 0 then return nil end

  local rows = {
    ui.label({ text = tr("recent_requests"), fontSize = 10, fontWeight = "bold",
      color = "on_surface_variant" }),
  }

  for i, a in ipairs(activity) do
    if i > 3 then break end
    local color = a.status == 200 and "on_surface_variant" or "error"
    table.insert(rows, ui.label({
      text = tr("activity_line", {
        tps = fmtTps(a.tps),
        model = a.model,
        duration = fmtDuration(a.duration_ms),
        when = relativeTime(a.timestamp),
      }),
      fontSize = 11,
      color = color,
    }))
  end

  return ui.column({ gap = 3 }, rows)
end

local function modelRow(m)
  local stateColor = m.loaded and "primary" or "on_surface_variant"
  local stateText = m.loaded and tr("state_loaded")
    or (pendingLocal[m.id] and tr("state_loading") or "")

  local action
  if m.loaded then
    action = ui.button({
      glyph = "player-stop",
      onClick = function() unloadModel(m.id) end,
      tooltip = tr("btn_unload"),
    })
  elseif pendingLocal[m.id] then
    action = ui.glyph({ name = "loader", size = 14, color = "warning" })
  else
    action = ui.button({
      glyph = "player-play",
      onClick = function() loadModel(m.id) end,
      tooltip = tr("btn_load"),
    })
  end

  -- single condensed row: play button · name (+ inline status) · spacer
  return ui.row({ align = "center", gap = 8, key = m.id }, {
    action,
    ui.label({ text = m.name or m.id, fontSize = 12 }),
    pendingLocal[m.id] and ui.glyph({ name = "loader", size = 11, color = "warning" }) or nil,
    stateText ~= "" and ui.label({ text = stateText, fontSize = 9, color = stateColor }) or nil,
    ui.spacer({}),
  })
end

local function modelList()
  if status == "unconfigured" then
    return ui.label({ text = tr("not_configured"), color = "on_surface_variant", fontSize = 11 })
  elseif status == "auth_failed" then
    return ui.label({ text = tr("auth_failed"), color = "error", fontSize = 11 })
  elseif status == "unreachable" or status == "error" then
    return ui.label({ text = tr("unreachable"), color = "error", fontSize = 11 })
  elseif #models == 0 then
    return ui.label({ text = tr("no_models"), color = "on_surface_variant", fontSize = 11 })
  end

  local rows = {}
  for _, m in ipairs(models) do
    table.insert(rows, modelRow(m))
  end
  return ui.column({ gap = 2 }, rows)
end

-- Clear stale pending flags once the poller reports the model ready.
local function syncPendingWithModels()
  local byId = {}
  for _, m in ipairs(models) do
    byId[m.id] = m
  end
  for id in pairs(pendingLocal) do
    local m = byId[id]
    if m and m.loaded then
      pendingLocal[id] = nil
    end
  end
end

-- -------------------------------------------------------------- render

function panelRender()
  syncPendingWithModels()
  local children = {
    headerSection(),
  }

  local act = activitySection()
  if act then
    table.insert(children, ui.separator({}))
    table.insert(children, act)
  end

  table.insert(children, ui.separator({}))
  table.insert(children, ui.scroll({ flexGrow = 1, gap = 2 }, { modelList() }))

  panel.render(ui.column({ gap = 6 }, children))
end

function onOpen(_context)
  status = noctalia.state.get("status") or "unconfigured"
  models = noctalia.state.get("models") or {}
  stats = noctalia.state.get("stats")
  activity = noctalia.state.get("activity") or {}
  tpsHistory = noctalia.state.get("req_tokens_history") or {}
  panelRender()
end

function update()
  -- Panel gets ticks while open; re-render keeps relative times fresh.
  noctalia.setUpdateInterval(5000)
  panelRender()
end
