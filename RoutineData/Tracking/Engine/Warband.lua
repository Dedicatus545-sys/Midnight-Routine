local _, addonNS = ...
local tracking = addonNS.Tracking

tracking.installers["Warband"] = function(owner, context)
    local ns = context.namespace
    local MR = ns.MR

    local function ParseCharacterKey(charKey)
        if type(charKey) ~= "string" then
            return "Unknown", ""
        end

        local name, realm = charKey:match("^(.-)%s%-%s(.+)$")
        if name and realm then
            return name, realm
        end

        return charKey, ""
    end

    function MR:GetCharacters()
        local sv = self.db and self.db.sv
        return sv and sv.char or nil
    end

    function MR:GetCharacter(charKey)
        local characters = self:GetCharacters()
        return characters and characters[charKey] or nil
    end

    function MR:GetCurrentCharacterKey()
        if self.db and self.db.GetNativeHandles then
            local handles = self.db:GetNativeHandles()
            if handles and handles.charKey then
                return handles.charKey
            end
        end

        local name, realm
        if UnitFullName then
            name, realm = UnitFullName("player")
        end
        if name and realm and realm ~= "" then
            return string.format("%s - %s", name, realm)
        end

        return UnitName and UnitName("player") or "Unknown"
    end

    function MR:ParseCharacterKey(charKey)
        return ParseCharacterKey(charKey)
    end

    function MR:RefreshCurrentMythicPlusScore()
        if not (self.db and self.db.char and C_PlayerInfo and C_PlayerInfo.GetPlayerMythicPlusRatingSummary) then
            return false
        end

        local summary = C_PlayerInfo.GetPlayerMythicPlusRatingSummary("player")
        local score = summary and tonumber(summary.currentSeasonScore)
        if not score or self.db.char.mythicPlusScore == score then
            return false
        end

        self.db.char.mythicPlusScore = score
        return true
    end

    function MR:RefreshCurrentGold()
        if not (self.db and self.db.char and GetMoney) then
            return false
        end

        local gold = tonumber(GetMoney())
        if gold == nil or self.db.char.gold == gold then
            return false
        end

        self.db.char.gold = gold
        return true
    end

    function MR:RefreshWarbandGold()
        if not (self.db and self.db.global and C_Bank and C_Bank.FetchDepositedMoney
            and Enum and Enum.BankType and Enum.BankType.Account) then
            return false
        end
        if C_PlayerInfo and C_PlayerInfo.HasAccountInventoryLock and not C_PlayerInfo.HasAccountInventoryLock() then
            return false
        end

        local ok, gold = pcall(C_Bank.FetchDepositedMoney, Enum.BankType.Account)
        gold = ok and tonumber(gold) or nil
        if gold == nil then
            return false
        end

        local changed = self.db.global.warbandGold ~= gold
        self.db.global.warbandGold = gold
        self.db.global.warbandGoldUpdatedAt = (GetServerTime and GetServerTime()) or time()
        return changed
    end

    local function CompareWhatsLeft(a, b)
        if a.remaining ~= b.remaining then
            return a.remaining > b.remaining
        end
        if a.isCurrent ~= b.isCurrent then
            return a.isCurrent
        end
        if (a.name or "") ~= (b.name or "") then
            return (a.name or "") < (b.name or "")
        end
        return (a.realm or "") < (b.realm or "")
    end

    function MR:GetWarbandWhatsLeft()
        if self.GetWarbandMainOverview then
            return self:GetWarbandMainOverview()
        end
        if not self.GetWarbandWeeklyData then
            return {}
        end
        local results = {}
        for _, snapshot in ipairs(self:GetWarbandWeeklyData() or {}) do
            local entry = {
                key = snapshot.key,
                name = snapshot.name,
                realm = snapshot.realm,
                classFile = snapshot.classFile,
                isCurrent = snapshot.isCurrent and true or false,
                stale = snapshot.stale and true or false,
                remaining = 0,
                done = 0,
                total = 0,
                groups = {},
            }
            for _, moduleEntry in ipairs(snapshot.modules or {}) do
                local group
                for _, row in ipairs(moduleEntry.rows or {}) do
                    if not row.currencyBrowserButton and not row.noMax and (tonumber(row.max) or 0) > 0 then
                        entry.total = entry.total + 1
                        if row.complete then
                            entry.done = entry.done + 1
                        else
                            if not group then
                                group = {
                                    key = moduleEntry.key,
                                    label = moduleEntry.label,
                                    color = moduleEntry.color,
                                    rows = {},
                                }
                                entry.groups[#entry.groups + 1] = group
                            end
                            group.rows[#group.rows + 1] = {
                                key = row.key,
                                label = row.label,
                                value = tonumber(row.value) or 0,
                                max = tonumber(row.max) or 0,
                                displayValue = row.displayValue,
                            }
                            entry.remaining = entry.remaining + 1
                        end
                    end
                end
            end
            results[#results + 1] = entry
        end
        table.sort(results, CompareWhatsLeft)
        return results
    end

end
