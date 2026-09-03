--!nonstrict

-- Bar widget: llama-swap status glyph. Green dot while a model is ready,
-- amber while loading, red when unreachable, grey when unconfigured.

local showLoadedModel = noctalia.getConfig("show_loaded_model")

local status = "unconfigured"
local models = {}
local loadedCount = 0
local pendingLoads = {}

local render

local function tr(key, subst)
  return noctalia.tr("widget." .. key, subst)
end

noctalia.state.watch("status", function(value)
  status = value or "unconfigured"
  if render then render() end
end)

noctalia.state.watch("models", function(value)
  models = type(value) == "table" and value or {}
  if render then render() end
end)

noctalia.state.watch("loaded_count", function(value)
  loadedCount = value or 0
  if render then render() end
end)

noctalia.state.watch("pending_loads", function(value)
  pendingLoads = type(value) == "table" and value or {}
  if render then render() end
end)

local function loadedModelName()
  for _, m in ipairs(models) do
    if m.loaded then return m.name or m.id end
  end
  return nil
end

local function getStatusText()
  if status == "connected" then
    if loadedCount > 0 then
      local name = loadedModelName()
      if name then
        return tr("tooltip_loaded", { model = name })
      end
      return tr("tooltip_loaded_count", { count = loadedCount })
    end
    return tr("tooltip_idle")
  elseif status == "auth_failed" then
    return tr("status_auth_failed")
  elseif status == "unreachable" then
    return tr("status_unreachable")
  elseif status == "error" then
    return tr("status_error")
  else
    return tr("status_unconfigured")
  end
end

local function getStatusColor()
  if status ~= "connected" then
    if status == "auth_failed" or status == "error" then return "error" end
    if status == "unreachable" then return "error" end
    return "on_surface_variant"
  end
  if next(pendingLoads) ~= nil then
    return "warning"
  end
  if loadedCount > 0 then
    return "success"
  end
  return "primary"
end

render = function()
  barWidget.setGlyph("cpu")
  barWidget.setGlyphColor(getStatusColor())

  if showLoadedModel then
    local name = loadedModelName()
    if name then
      -- keep the bar compact: strip common quant/size suffixes
      local short = name:gsub("%-?Q%d[_%w]*", ""):gsub("%-?GGUF", "")
      barWidget.setText(short)
    else
      barWidget.setText("")
    end
  else
    barWidget.setText("")
  end

  barWidget.setTooltip(getStatusText())
end

function update()
  noctalia.setUpdateInterval(5000)
  if status == "unconfigured" then
    local s = noctalia.state.get("status")
    if s then status = s end
  end
  render()
end

-- Pick a panel size that fits the model list: the host fixes panel sizes at
-- manifest level, so we register three panel entries (S/M/L) sharing one
-- script and open the one that matches the current model count.
local function panelIdForCount(n)
  if n <= 2 then return "manager-s" end
  if n <= 4 then return "manager-m" end
  return "manager-l"
end

local modelCount = 0

noctalia.state.watch("model_count", function(value)
  modelCount = value or 0
end)

function onClick()
  noctalia.togglePanel("carlocamacho/llama-swap:" .. panelIdForCount(modelCount))
end

function onRightClick()
  noctalia.openSettings()
end

update()
