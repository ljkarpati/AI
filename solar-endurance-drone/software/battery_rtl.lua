-- ============================================================
-- battery_rtl.lua — HELIOS-10 onboard battery guardian (layer 2)
--
-- Runs ON the flight controller (ArduPilot Lua scripting), so it
-- works even if the Raspberry Pi or the radio link dies.
--   <= 10%  -> force RTL  (Return To Launch)
--   <=  5%  -> force LAND (came home too late: get down now)
--
-- Install:
--   1. Set SCR_ENABLE = 1 (already in helios10.param), reboot.
--   2. Copy this file to the SD card:  APM/scripts/battery_rtl.lua
--   3. Reboot. You should see "BattGuard: armed and watching"
--      in Mission Planner / QGC messages.
--
-- Requires BATT_CAPACITY to be set correctly (10000 mAh for the
-- 6S2P pack) — percentage comes from consumed mAh.
-- This DUPLICATES the BATT_FS_* failsafes on purpose: two
-- independent layers, plus the Pi script makes three.
-- ============================================================

local RTL_PCT       = 10    -- force RTL at or below this %
local LAND_PCT      = 5     -- force LAND at or below this %
local RETRIGGER_MS  = 15000 -- re-assert if pilot overrides while low
local MODE_AUTO     = 3
local MODE_RTL      = 6
local MODE_LAND     = 9
local MODE_SMARTRTL = 21

local MAV_WARN = 4
local MAV_INFO = 6

local last_action_ms = 0
local announced = false

local function now_ms() return millis():toint() end

function update()
  if not arming:is_armed() then
    announced = false
    return update, 5000
  end

  if not announced then
    gcs:send_text(MAV_INFO, "BattGuard: armed and watching (RTL@" ..
                  RTL_PCT .. "% LAND@" .. LAND_PCT .. "%)")
    announced = true
  end

  local pct = battery:capacity_remaining_pct(0)
  if pct == nil then
    gcs:send_text(MAV_WARN, "BattGuard: no battery %% (set BATT_CAPACITY!)")
    return update, 5000
  end

  local mode = vehicle:get_mode()

  if pct <= LAND_PCT and mode ~= MODE_LAND then
    if now_ms() - last_action_ms > RETRIGGER_MS then
      gcs:send_text(MAV_WARN, "BattGuard: " .. pct .. "%% CRITICAL -> LAND")
      vehicle:set_mode(MODE_LAND)
      last_action_ms = now_ms()
    end
  elseif pct <= RTL_PCT
         and mode ~= MODE_RTL and mode ~= MODE_LAND
         and mode ~= MODE_SMARTRTL then
    if now_ms() - last_action_ms > RETRIGGER_MS then
      gcs:send_text(MAV_WARN, "BattGuard: " .. pct .. "%% low -> RTL")
      vehicle:set_mode(MODE_RTL)
      last_action_ms = now_ms()
    end
  end

  return update, 1000   -- check every second
end

gcs:send_text(MAV_INFO, "BattGuard: loaded")
return update, 1000
