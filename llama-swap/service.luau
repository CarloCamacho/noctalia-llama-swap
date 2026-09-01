--!nonstrict

-- llama-swap poller service: fetches /v1/models, /running, /api/metrics/stats
-- and /api/metrics/activity from the configured llama-swap server and publishes
-- them to shared state for the bar widget and panel.

local serverUrlRaw = noctalia.getConfig("server_url")
local apiKeyRaw = noctalia.getConfig("api_key")
local refreshInterval = tonumber(noctalia.getConfig("refresh_interval")) or 5

local LOAD_TIMEOUT_SECONDS = 180
local MAX_PENDING_AGE_NOTIFY = LOAD_TIMEOUT_SECONDS

local status = "unconfigured"
local models = {}            -- array of { id, name, loaded }
local runningInfo = {}       -- id -> { name, model, state, ttl }
local loadedSince = {}       -- id -> os.clock() when first observed ready
local pendingLoads = {}      -- id -> os.clock() when load was requested
local pendingNotified = {}   -- id -> true (timeout already reported)
local authNotified = false
local errorLogged = false

local function getCleanUrl()
  if type(serverUrlRaw) ~= "string" then return "" end
  return (serverUrlRaw:gsub("/$", ""):gsub("%s+$", ""))
end

local function getCleanKey()
  if type(apiKeyRaw) ~= "string" then return "" end
  return noctalia.string.trim(apiKeyRaw)
end

local function isConfigured()
  return getCleanUrl() ~= ""
end

local function requestHeaders()
  local h = {}
  local key = getCleanKey()
  if key ~= "" then
    table.insert(h, "Authorization: Bearer " .. key)
  end
  return h
end

local function setStatus(next, reason)
  if status == next then return end
  status = next
  noctalia.state.set("status", status)
  noctalia.log("llama-swap status -> " .. status .. (reason and (" (" .. reason .. ")") or ""))

  if status == "auth_failed" and not authNotified then
    authNotified = true
    noctalia.notifyError(noctalia.tr("notifications.auth_failed"))
  elseif status == "connected" then
    authNotified = false
    errorLogged = false
  end
end

-- Fire one GET against llama-swap. Callback receives a normalized result.
local function llamaGet(path, callback)
  if not isConfigured() then return false end

  return noctalia.http({
      url = getCleanUrl() .. path,
      method = "GET",
      headers = requestHeaders(),
    }, function(response: HttpResponse)
      if not response then
        callback({ ok = false, status = 0, body = "" })
        return
      end
      callback({
        ok = response.status >= 200 and response.status < 300,
        status = response.status,
        body = response.body or "",
      })
    end)
end

-- ---------------------------------------------------------------- parsing

local function parseModels(body)
  local parsed = noctalia.json.decode(body)
  if type(parsed) ~= "table" or type(parsed.data) ~= "table" then return nil end

  local out = {}
  for _, m in ipairs(parsed.data) do
    local id = m.id or m.name
    if id then
      local loaded = false
      if type(m.status) == "table" and m.status.value == "loaded" then
        loaded = true
      end
      table.insert(out, { id = id, name = m.name or id, loaded = loaded })
    end
  end
  table.sort(out, function(a, b) return a.id:lower() < b.id:lower() end)
  return out
end

local function parseRunning(body)
  local parsed = noctalia.json.decode(body)
  if type(parsed) ~= "table" or type(parsed.running) ~= "table" then return nil end

  local out = {}
  for _, r in ipairs(parsed.running) do
    local id = r.model
    if id then
      out[id] = {
        name = r.name or id,
        model = id,
        state = r.state or "ready",
        ttl = r.ttl,
      }
    end
  end
  return out
end

local function parseStats(body)
  local parsed = noctalia.json.decode(body)
  if type(parsed) ~= "table" then return nil end

  local gen = parsed.gen_histogram or {}
  return {
    requests = parsed.total_requests or 0,
    input_tokens = parsed.total_input_tokens or 0,
    output_tokens = parsed.total_output_tokens or 0,
    cache_tokens = parsed.total_cache_tokens or 0,
    p50 = gen.p50 or 0,
    p95 = gen.p95 or 0,
  }
end

local function parseActivity(body)
  local parsed = noctalia.json.decode(body)
  if type(parsed) ~= "table" or type(parsed.data) ~= "table" then return nil end

  local out = {}
  local history = {}
  for i, entry in ipairs(parsed.data) do
    if i > 24 then break end
    local tok = entry.tokens or {}
    local tps = tok.tokens_per_second or 0
    table.insert(history, tps)
    if i <= 6 then
      table.insert(out, {
        id = entry.id,
        model = entry.model or "?",
        path = entry.req_path or "",
        status = entry.resp_status_code or 0,
        input_tokens = tok.input_tokens or 0,
        output_tokens = tok.output_tokens or 0,
        tps = tps,
        prompt_tps = tok.prompt_per_second or 0,
        duration_ms = entry.duration_ms or 0,
        timestamp = entry.timestamp or "",
      })
    end
  end
  -- sparkline wants oldest -> newest
  local ordered = {}
  for i = #history, 1, -1 do
    table.insert(ordered, history[i])
  end
  noctalia.state.set("tps_history", ordered)
  return out
end

-- ---------------------------------------------------------------- publishing

local function mergeLoadedFlags()
  for _, m in ipairs(models) do
    local run = runningInfo[m.id]
    m.loaded = run ~= nil and run.state == "ready"
  end
end

local function publishModels()
  mergeLoadedFlags()
  noctalia.state.set("models", models)
  local count = 0
  for id, run in pairs(runningInfo) do
    if run.state == "ready" then count = count + 1 end
  end
  noctalia.state.set("loaded_count", count)
end

local function publishStats(stats)
  noctalia.state.set("stats", stats)
end

local function publishActivity(activity)
  noctalia.state.set("activity", activity)
end

-- ---------------------------------------------------------------- pending loads

-- Panel writes its requested loads into state; we reconcile them here.
noctalia.state.watch("pending_loads", function(value)
  if type(value) ~= "table" then return end
  for id in pairs(value) do
    if pendingLoads[id] == nil then
      pendingLoads[id] = os.clock()
      pendingNotified[id] = nil
      loadedSince[id] = nil
    end
  end
end)

local function reconcilePending(runningSet)
  local expired = {}
  for id, startedAt in pairs(pendingLoads) do
    local run = runningSet[id]
    if run and run.state == "ready" then
      pendingLoads[id] = nil
      pendingNotified[id] = nil
    elseif (os.clock() - startedAt) > LOAD_TIMEOUT_SECONDS then
      pendingLoads[id] = nil
      if not pendingNotified[id] then
        pendingNotified[id] = true
        table.insert(expired, id)
      end
    end
  end
  for _, id in ipairs(expired) do
    noctalia.notifyError(noctalia.tr("notifications.load_timeout", { model = id }))
  end
end

-- ---------------------------------------------------------------- main poll

local function poll()
  if not isConfigured() then
    setStatus("unconfigured")
    return
  end

  -- Models + running state
  local gotModels = llamaGet("/v1/models", function(res)
    if res.status == 401 or res.status == 403 then
      setStatus("auth_failed", "HTTP " .. res.status)
      return
    elseif res.status == 0 then
      setStatus("unreachable")
      return
    elseif not res.ok then
      setStatus("error", "models HTTP " .. res.status)
      return
    end

    local parsed = parseModels(res.body)
    if not parsed then
      setStatus("error", "models parse")
      return
    end

    setStatus("connected")
    models = parsed

    llamaGet("/running", function(res2)
      if res2.ok then
        local parsedRun = parseRunning(res2.body)
        if parsedRun then
          runningInfo = parsedRun
          for id in pairs(parsedRun) do
            if loadedSince[id] == nil then loadedSince[id] = os.clock() end
          end
          for id in pairs(loadedSince) do
            if parsedRun[id] == nil then loadedSince[id] = nil end
          end
          reconcilePending(parsedRun)
        end
      end
      publishModels()
    end)
  end)

  -- Aggregate stats (independent)
  llamaGet("/api/metrics/stats", function(res)
    if res.ok then
      publishStats(parseStats(res.body))
    end
  end)

  -- Recent activity (independent)
  llamaGet("/api/metrics/activity?limit=24", function(res)
    if res.ok then
      publishActivity(parseActivity(res.body))
    end
  end)

  if not gotModels and status ~= "unconfigured" then
    setStatus("unreachable")
  end
end

-- ---------------------------------------------------------------- lifecycle

function update()
  if refreshInterval < 3 then refreshInterval = 3 end
  noctalia.setUpdateInterval(refreshInterval * 1000)
  poll()
end

update()
