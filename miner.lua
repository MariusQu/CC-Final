-- ============================================================
-- Start:
--
--        MINING-BEREICH
--              ↑
--              🐢
--              ↓
--            [KISTE]
--
-- Inhalt der Kiste:
--   - Fuel
--   - Fackeln
--   - leere Eimer
--   - Platz fuer abgebaute Items
--
-- Befehle:
--
--   miner <breite> <tiefe> <hoehe>
--   miner <breite> <tiefe> <hoehe> <fackelabstand>
--
-- Beispiele:
--
--   miner 5 5 2
--   miner 20 20 5 6
--   miner 30 30 10 8
--
-- Status:
--
--   miner status
--
-- Neuen Auftrag:
--
--   miner new 20 20 5 6
--
-- Zustand loeschen:
--
--   miner reset
--
-- ============================================================


-- ============================================================
-- EINSTELLUNGEN
-- ============================================================

local STATE_FILE = "miner_state"

local VERSION = 1

-- Ab dieser Anzahl freier Inventarplaetze wird
-- normalerweise eine Versorgung durchgefuehrt.
local MIN_FREE_SLOTS = 2

-- Fuel-Reserve fuer die Rueckkehr.
local FUEL_RESERVE = 100

-- Mindestanzahl Fackeln.
local MIN_TORCHES = 8

-- Zielanzahl Fackeln nach dem Auffuellen.
local TARGET_TORCHES = 64

-- Mindestanzahl leerer Eimer.
local MIN_BUCKETS = 2

-- Zielanzahl Eimer.
local TARGET_BUCKETS = 4

-- Standard-Fackelabstand.
local DEFAULT_TORCH_DISTANCE = 6


-- ============================================================
-- ARGUMENTE
-- ============================================================

local args = { ... }


-- ============================================================
-- HILFSFUNKTION: ZAHL
-- ============================================================

local function number(value)
    if value == nil then
        return nil
    end

    return tonumber(value)
end


-- ============================================================
-- RESET
-- ============================================================

if args[1] == "reset" then

    if fs.exists(STATE_FILE) then
        fs.delete(STATE_FILE)
        print("Miner-Zustand geloescht.")
    else
        print("Kein gespeicherter Zustand vorhanden.")
    end

    return
end


-- ============================================================
-- STATUS
-- ============================================================

if args[1] == "status" then

    if not fs.exists(STATE_FILE) then
        print("Kein gespeicherter Auftrag.")
        return
    end

    local file = fs.open(STATE_FILE, "r")

    if not file then
        print("Zustand konnte nicht gelesen werden.")
        return
    end

    local data =
        textutils.unserialize(
            file.readAll()
        )

    file.close()

    if not data then
        print("Zustand ist beschaedigt.")
        return
    end

    print("")
    print("========== MINER ==========")
    print("Groesse:")
    print(
        tostring(data.width)
        .. " x "
        .. tostring(data.depth)
        .. " x "
        .. tostring(data.height)
    )

    print("")
    print("Position:")
    print("X: " .. tostring(data.x))
    print("Y: " .. tostring(data.y))
    print("Z: " .. tostring(data.z))
    print("Richtung: " .. tostring(data.dir))

    print("")
    print("Phase: " .. tostring(data.phase))

    print(
        "Fackelzaehler: "
        .. tostring(data.torchCounter)
    )

    print("")
    print("Fortschritt:")
    print(
        "Ebene: "
        .. tostring(data.layer)
        .. "/"
        .. tostring(data.height)
    )

    print(
        "Reihe: "
        .. tostring(data.row)
        .. "/"
        .. tostring(data.depth)
    )

    print(
        "Spalte: "
        .. tostring(data.col)
        .. "/"
        .. tostring(data.width)
    )

    print("============================")
    print("")

    return
end


-- ============================================================
-- NEUER AUFTRAG
-- ============================================================

local newJob = false

if args[1] == "new" then
    newJob = true
    table.remove(args, 1)
end


-- ============================================================
-- RAUMGROESSE
-- ============================================================

local WIDTH = number(args[1])
local DEPTH = number(args[2])
local HEIGHT = number(args[3])

local TORCH_DISTANCE =
    number(args[4])
    or DEFAULT_TORCH_DISTANCE


if not WIDTH or not DEPTH or not HEIGHT then

    print("")
    print("Benutzung:")
    print("")
    print("  miner <breite> <tiefe> <hoehe>")
    print("  miner <breite> <tiefe> <hoehe> <fackelabstand>")
    print("")
    print("Beispiele:")
    print("")
    print("  miner 5 5 2")
    print("  miner 20 20 5 6")
    print("  miner 30 30 10 8")
    print("")
    print("Neuer Auftrag:")
    print("")
    print("  miner new 20 20 5 6")
    print("")

    return
end


if WIDTH < 1
    or DEPTH < 1
    or HEIGHT < 1 then

    error("Die Raumgroesse muss mindestens 1 sein.")
end


if TORCH_DISTANCE < 0 then
    error("Der Fackelabstand darf nicht negativ sein.")
end


-- ============================================================
-- POSITION
--
-- Start:
--
-- x = 0
-- y = 0
-- z = 0
--
-- Die Turtle schaut in Richtung +X.
--
-- Die Kiste steht bei x = -1.
--
-- Richtung:
--
-- 0 = +X
-- 1 = +Z
-- 2 = -X
-- 3 = -Z
--
-- ============================================================

local x = 0
local y = 0
local z = 0
local dir = 0


-- ============================================================
-- FORTSCHRITT
--
-- layer = Ebene
-- row   = Reihe
-- col   = Spalte
--
-- Alles beginnt bei 1.
-- ============================================================

local layer = 1
local row = 1
local col = 1

local cellDone = false

local torchCounter = 0

local phase = "mining"

local target = nil


-- ============================================================
-- ZUSTAND SPEICHERN
-- ============================================================

local function saveState()

    local data = {
        version = VERSION,

        width = WIDTH,
        depth = DEPTH,
        height = HEIGHT,

        torchDistance = TORCH_DISTANCE,

        x = x,
        y = y,
        z = z,
        dir = dir,

        layer = layer,
        row = row,
        col = col,

        cellDone = cellDone,

        torchCounter = torchCounter,

        phase = phase,

        target = target
    }


    local file =
        fs.open(STATE_FILE, "w")


    if not file then
        error("Kann Miner-Zustand nicht speichern.")
    end


    file.write(
        textutils.serialize(data)
    )

    file.close()
end


-- ============================================================
-- ZUSTAND LADEN
-- ============================================================

local function loadState()

    if newJob then
        return false
    end


    if not fs.exists(STATE_FILE) then
        return false
    end


    local file =
        fs.open(STATE_FILE, "r")


    if not file then
        error("Miner-Zustand kann nicht gelesen werden.")
    end


    local data =
        textutils.unserialize(
            file.readAll()
        )


    file.close()


    if not data then
        error("Miner-Zustand ist beschaedigt.")
    end


    if data.version ~= VERSION then

        error(
            "Miner-Zustand stammt aus einer "
            .. "anderen Version.\n"
            .. "Fuehre 'miner reset' aus."
        )
    end


    -- Wenn beim Start keine Groesse angegeben wurde,
    -- verwenden wir die gespeicherte.
    if not WIDTH then
        WIDTH = data.width
        DEPTH = data.depth
        HEIGHT = data.height
    end


    -- Bei expliziter Groesse muss sie passen.
    if WIDTH ~= data.width
        or DEPTH ~= data.depth
        or HEIGHT ~= data.height then

        error(
            "Die Raumgroesse passt nicht zum "
            .. "gespeicherten Auftrag.\n"
            .. "Fuer einen neuen Auftrag:\n"
            .. "miner new "
            .. tostring(WIDTH)
            .. " "
            .. tostring(DEPTH)
            .. " "
            .. tostring(HEIGHT)
        )
    end


    TORCH_DISTANCE =
        data.torchDistance
        or TORCH_DISTANCE


    x = data.x or 0
    y = data.y or 0
    z = data.z or 0

    dir = data.dir or 0

    layer = data.layer or 1
    row = data.row or 1
    col = data.col or 1

    cellDone =
        data.cellDone or false

    torchCounter =
        data.torchCounter or 0

    phase =
        data.phase or "mining"

    target =
        data.target


    return true
end


-- ============================================================
-- FREIE INVENTARPLAETZE
-- ============================================================

local function freeSlots()

    local count = 0

    for slot = 1, 16 do

        if turtle.getItemCount(slot) == 0 then
            count = count + 1
        end
    end

    return count
end


-- ============================================================
-- TORCHEN
-- ============================================================

local function isTorch(item)

    if not item then
        return false
    end

    local name =
        string.lower(item.name)


    if name == "minecraft:torch" then
        return true
    end


    if string.find(
        name,
        "redstone_torch",
        1,
        true
    ) then
        return false
    end


    return string.find(
        name,
        "torch",
        1,
        true
    ) ~= nil
end


local function torchCount()

    local total = 0

    for slot = 1, 16 do

        local item =
            turtle.getItemDetail(slot)


        if isTorch(item) then
            total = total + item.count
        end
    end


    return total
end


local function selectTorch()

    for slot = 1, 16 do

        local item =
            turtle.getItemDetail(slot)


        if isTorch(item) then

            turtle.select(slot)

            return true
        end
    end


    return false
end


local function placeTorch()

    if not selectTorch() then
        return false
    end


    local ok =
        turtle.placeDown()


    turtle.select(1)


    return ok
end


-- ============================================================
-- EIMER
-- ============================================================

local function isEmptyBucket(item)

    if not item then
        return false
    end


    local name =
        string.lower(item.name)


    return
        name == "minecraft:bucket"
        or string.find(
            name,
            "empty_bucket",
            1,
            true
        ) ~= nil
end


local function emptyBucketCount()

    local total = 0


    for slot = 1, 16 do

        local item =
            turtle.getItemDetail(slot)


        if isEmptyBucket(item) then
            total = total + item.count
        end
    end


    return total
end


local function findEmptyBucket()

    for slot = 1, 16 do

        local item =
            turtle.getItemDetail(slot)


        if isEmptyBucket(item) then
            return slot
        end
    end


    return nil
end


-- ============================================================
-- FLUESSIGKEIT
-- ============================================================

local function isLiquid(data)

    if not data or not data.name then
        return false
    end


    local name =
        string.lower(data.name)


    return
        string.find(
            name,
            "water",
            1,
            true
        ) ~= nil
        or
        string.find(
            name,
            "lava",
            1,
            true
        ) ~= nil
end


-- ============================================================
-- FLUESSIGKEIT VORNE AUFNEHMEN
-- ============================================================

local function collectFrontLiquid()

    local slot =
        findEmptyBucket()


    if not slot then
        return false
    end


    turtle.select(slot)


    local ok =
        turtle.place()


    turtle.select(1)


    return ok
end


-- ============================================================
-- FLUESSIGKEIT OBEN AUFNEHMEN
-- ============================================================

local function collectUpLiquid()

    local slot =
        findEmptyBucket()


    if not slot then
        return false
    end


    turtle.select(slot)


    local ok =
        turtle.placeUp()


    turtle.select(1)


    return ok
end


-- ============================================================
-- FLUESSIGKEIT UNTEN AUFNEHMEN
-- ============================================================

local function collectDownLiquid()

    local slot =
        findEmptyBucket()


    if not slot then
        return false
    end


    turtle.select(slot)


    local ok =
        turtle.placeDown()


    turtle.select(1)


    return ok
end


-- ============================================================
-- RICHTUNG
-- ============================================================

local function turnRight()

    turtle.turnRight()

    dir = (dir + 1) % 4

    saveState()
end


local function turnLeft()

    turtle.turnLeft()

    dir = (dir + 3) % 4

    saveState()
end


local function face(targetDir)

    local difference =
        (targetDir - dir) % 4


    if difference == 1 then

        turnRight()

    elseif difference == 2 then

        turnRight()
        turnRight()

    elseif difference == 3 then

        turnLeft()
    end
end


local function opposite(d)

    return (d + 2) % 4
end


-- ============================================================
-- VORWAERTS
-- ============================================================

local function forwardMining()

    if turtle.forward() then

        if dir == 0 then
            x = x + 1

        elseif dir == 1 then
            z = z + 1

        elseif dir == 2 then
            x = x - 1

        else
            z = z - 1
        end


        saveState()

        return true
    end


    -- Block untersuchen.
    local hasBlock, data =
        turtle.inspect()


    if hasBlock and isLiquid(data) then

        return collectFrontLiquid()
    end


    if hasBlock then

        return turtle.dig()
    end


    turtle.attack()

    sleep(0.1)

    return false
end


-- ============================================================
-- HOCH
-- ============================================================

local function upMining()

    if turtle.up() then

        y = y + 1

        saveState()

        return true
    end


    local hasBlock, data =
        turtle.inspectUp()


    if hasBlock and isLiquid(data) then

        return collectUpLiquid()
    end


    if hasBlock then

        return turtle.digUp()
    end


    turtle.attackUp()

    sleep(0.1)

    return false
end


-- ============================================================
-- OFFENE BEWEGUNG
-- Fuer bereits abgebaute Wege.
-- ============================================================

local function forwardOpen()

    if turtle.forward() then

        if dir == 0 then
            x = x + 1

        elseif dir == 1 then
            z = z + 1

        elseif dir == 2 then
            x = x - 1

        else
            z = z - 1
        end


        saveState()

        return true
    end


    local hasBlock, data =
        turtle.inspect()


    if hasBlock and isLiquid(data) then

        return collectFrontLiquid()
    end


    return false
end


local function upOpen()

    if turtle.up() then

        y = y + 1

        saveState()

        return true
    end


    local hasBlock, data =
        turtle.inspectUp()


    if hasBlock and isLiquid(data) then

        return collectUpLiquid()
    end


    return false
end


local function downOpen()

    if turtle.down() then

        y = y - 1

        saveState()

        return true
    end


    local hasBlock, data =
        turtle.inspectDown()


    if hasBlock and isLiquid(data) then

        return collectDownLiquid()
    end


    return false
end


-- ============================================================
-- ZICKZACK-RICHTUNG
-- ============================================================

local function rowDirection(r)

    if r % 2 == 1 then
        return 0
    else
        return 2
    end
end


local function rowChangeDirection()

    if row % 2 == 1 then
        return 1
    else
        return 3
    end
end


-- ============================================================
-- FUEL
-- ============================================================

local function isUnlimitedFuel()

    return turtle.getFuelLevel()
        == "unlimited"
end


local function refuel()

    if isUnlimitedFuel() then
        return
    end


    local oldSlot =
        turtle.getSelectedSlot()


    for slot = 1, 16 do

        local item =
            turtle.getItemDetail(slot)


        if item then

            turtle.select(slot)


            if turtle.refuel(0) then
                turtle.refuel()
            end
        end
    end


    turtle.select(oldSlot)
end


-- ============================================================
-- KISTE ERREICHEN
--
-- Die Kiste befindet sich bei:
--
-- x = -1
-- y = 0
-- z = 0
--
-- ============================================================

local function goToChest()

    -- Erst Hoehe verlassen.
    while y > 0 do

        face(2)

        if not downOpen() then
            error("Kann nicht nach unten zur Kiste.")
        end
    end


    -- Zuerst Z zurueck.
    while z > 0 do

        face(3)

        if not forwardOpen() then
            error("Rueckweg zur Kiste blockiert.")
        end
    end


    while z < 0 do

        face(1)

        if not forwardOpen() then
            error("Rueckweg zur Kiste blockiert.")
        end
    end


    -- X zurueck zum Start.
    while x > 0 do

        face(2)

        if not forwardOpen() then
            error("Rueckweg zur Kiste blockiert.")
        end
    end


    while x < 0 do

        face(0)

        if not forwardOpen() then
            error("Rueckweg zur Kiste blockiert.")
        end
    end


    -- Jetzt Startposition.
    -- Ein Block zurueck = Kiste.
    face(2)


    if not turtle.back() then
        error(
            "Kann die Kiste nicht erreichen. "
            .. "Steht dort wirklich eine Kiste?"
        )
    end


    x = -1

    saveState()
end


-- ============================================================
-- ZURUECK VOM KISTENPLATZ
-- ============================================================

local function leaveChest()

    face(0)


    if not turtle.forward() then
        error(
            "Kann Kistenplatz nicht verlassen."
        )
    end


    x = 0

    saveState()
end


-- ============================================================
-- INVENTAR IN KISTE
-- ============================================================

local function unload()

    print("Inventar wird entladen...")


    turtle.select(1)


    for slot = 1, 16 do

        if turtle.getItemCount(slot) > 0 then

            turtle.select(slot)


            turtle.drop()


            -- Wenn nach drop noch etwas im Slot ist,
            -- konnte es nicht abgelegt werden.
            if turtle.getItemCount(slot) > 0 then

                print(
                    "WARNUNG: Slot "
                    .. tostring(slot)
                    .. " konnte nicht vollstaendig "
                    .. "entladen werden."
                )
            end
        end
    end


    turtle.select(1)
end


-- ============================================================
-- AUS KISTE HOLEN
-- ============================================================

local function suckUntil(predicate, targetCount)

    local attempts = 0


    while predicate() < targetCount
        and attempts < 20 do

        attempts = attempts + 1


        local needed =
            targetCount - predicate()


        turtle.select(1)


        if not turtle.suck(64) then
            break
        end
    end
end


-- ============================================================
-- FUEL AUS KISTE
-- ============================================================

local function refillFuel()

    if isUnlimitedFuel() then
        return
    end


    print("Fuel wird aufgefuellt...")


    -- Zuerst vorhandenes Fuel verbrauchen.
    refuel()


    -- Dann immer wieder aus der Kiste ziehen.
    for attempt = 1, 20 do

        if turtle.getFuelLevel()
            >= turtle.getFuelLimit() then
            break
        end


        turtle.select(1)


        if not turtle.suck(64) then
            break
        end


        refuel()
    end


    turtle.select(1)


    if turtle.getFuelLevel() < FUEL_RESERVE then

        error(
            "Zu wenig Fuel in der Kiste.\n"
            .. "Bitte Kohle/Holzkohle nachfuellen."
        )
    end
end


-- ============================================================
-- FACKELN AUS KISTE
-- ============================================================

local function refillTorches()

    if TORCH_DISTANCE <= 0 then
        return
    end


    print("Fackeln werden aufgefuellt...")


    for attempt = 1, 10 do

        if torchCount()
            >= TARGET_TORCHES then
            break
        end


        turtle.select(1)


        if not turtle.suck(64) then
            break
        end
    end


    turtle.select(1)


    if torchCount() < MIN_TORCHES then

        error(
            "Zu wenige Fackeln in der Kiste."
        )
    end
end


-- ============================================================
-- EIMER AUS KISTE
-- ============================================================

local function refillBuckets()

    print("Eimer werden aufgefuellt...")


    for attempt = 1, 10 do

        if emptyBucketCount()
            >= TARGET_BUCKETS then
            break
        end


        turtle.select(1)


        if not turtle.suck(64) then
            break
        end
    end


    turtle.select(1)


    if emptyBucketCount()
        < MIN_BUCKETS then

        error(
            "Zu wenige leere Eimer in der Kiste."
        )
    end
end


-- ============================================================
-- GESAMTE VERSORGUNG
-- ============================================================

local function supply()

    print("")
    print("==============================")
    print("       VERSORGUNG")
    print("==============================")


    -- Arbeitsposition speichern.
    target = {
        x = x,
        y = y,
        z = z,
        dir = dir,

        layer = layer,
        row = row,
        col = col,

        cellDone = cellDone,
        torchCounter = torchCounter
    }


    phase = "returning"

    saveState()


    -- Zur Kiste.
    goToChest()


    phase = "at_chest"

    saveState()


    -- Inventar entladen.
    unload()


    -- Fuel, Fackeln, Eimer holen.
    refillFuel()
    refillTorches()
    refillBuckets()


    -- Kiste verlassen.
    leaveChest()


    phase = "returning_to_work"

    saveState()


    -- Zur gespeicherten Position.
    returnToTarget()


    -- Zustand wiederherstellen.
    x = target.x
    y = target.y
    z = target.z
    dir = target.dir

    layer = target.layer
    row = target.row
    col = target.col

    cellDone =
        target.cellDone

    torchCounter =
        target.torchCounter


    target = nil

    phase = "mining"

    saveState()


    print("Versorgung abgeschlossen.")
    print("")
end


-- ============================================================
-- ZUR ARBEITSPOSITION
--
-- Da der Raum in Zickzack-Reihen bearbeitet wird,
-- wird die bereits abgebaute Strecke wieder verwendet.
-- ============================================================

function returnToTarget()

    if not target then
        error("Keine gespeicherte Arbeitsposition.")
    end


    -- Aktuelle Position ist normalerweise Start.
    -- Die Zielposition wird entlang des gleichen Weges
    -- abgefahren.
    --
    -- Wir verwenden die logische Reihenfolge.
    --
    local targetLayer =
        target.layer

    local targetRow =
        target.row

    local targetCol =
        target.col


    -- Ebene fuer Ebene.
    for l = 1, targetLayer do

        local maxRow = DEPTH

        if l == targetLayer then
            maxRow = targetRow
        end


        for r = 1, maxRow do

            local maxCol = WIDTH

            if l == targetLayer
                and r == targetRow then

                maxCol = targetCol
            end


            local direction =
                rowDirection(r)


            face(direction)


            for c = 2, maxCol do

                if not forwardOpen() then

                    error(
                        "Rueckweg zur Arbeitsposition "
                        .. "ist blockiert."
                    )
                end
            end


            if l == targetLayer
                and r == targetRow then

                face(target.dir)

                return
            end


            -- Naechste Reihe.
            if r < DEPTH then

                face(
                    rowChangeDirection()
                )


                if not forwardOpen() then

                    error(
                        "Rueckweg zwischen Reihen "
                        .. "ist blockiert."
                    )
                end
            end
        end


        -- Naechste Ebene.
        if l < targetLayer then

            if not upOpen() then

                error(
                    "Rueckweg zur naechsten Ebene "
                    .. "ist blockiert."
                )
            end
        end
    end
end


-- ============================================================
-- KANN VERSORGUNG NOETIG SEIN?
-- ============================================================

local function needSupply()

    -- Fast volles Inventar.
    if freeSlots() < MIN_FREE_SLOTS then
        return true
    end


    -- Fackeln.
    if TORCH_DISTANCE > 0 then

        if torchCount() < MIN_TORCHES then
            return true
        end
    end


    -- Eimer.
    if emptyBucketCount() < MIN_BUCKETS then
        return true
    end


    -- Fuel.
    if not isUnlimitedFuel() then

        local fuel =
            turtle.getFuelLevel()


        if fuel < FUEL_RESERVE then
            return true
        end
    end


    return false
end


-- ============================================================
-- AKTUELLE ZELLE BEARBEITEN
-- ============================================================

local function mineCell()

    -- Block ueber uns abbauen,
    -- solange wir nicht in der letzten Ebene sind.
    if layer < HEIGHT then

        local hasBlock, data =
            turtle.inspectUp()


        if hasBlock and isLiquid(data) then

            if not collectUpLiquid() then

                return false
            end

        elseif hasBlock then

            turtle.digUp()
        end
    end


    -- Fackel setzen.
    if TORCH_DISTANCE > 0 then

        torchCounter =
            torchCounter + 1


        if torchCounter >= TORCH_DISTANCE then

            if not placeTorch() then
                return false
            end

            torchCounter = 0
        end
    end


    return true
end


-- ============================================================
-- HAUPT-MINING
-- ============================================================

local function mine()

    while true do

        -- ----------------------------------------------------
        -- Aktuelle Zelle
        -- ----------------------------------------------------

        if not cellDone then

            if needSupply() then
                supply()
            end


            local ok =
                mineCell()


            if not ok then

                supply()

                ok = mineCell()


                if not ok then
                    error(
                        "Zelle konnte nicht bearbeitet werden."
                    )
                end
            end


            cellDone = true

            saveState()
        end


        -- ----------------------------------------------------
        -- FERTIG?
        -- ----------------------------------------------------

        if layer == HEIGHT
            and row == DEPTH
            and col == WIDTH then

            print("")
            print("==============================")
            print("        MINING FERTIG")
            print("==============================")
            print("")


            phase = "finished_return"

            saveState()


            -- Zur Kiste zurueck.
            goToChest()


            phase = "finished"

            saveState()


            print("Turtle ist wieder bei der Kiste.")
            print("Inventar wird entladen...")


            unload()


            print("")
            print("Fertig!")
            print("")

            return
        end


        -- ----------------------------------------------------
        -- Naechste Zelle
        -- ----------------------------------------------------

        if needSupply() then
            supply()
        end


        -- Naechste Spalte.
        if col < WIDTH then

            face(
                rowDirection(row)
            )


            local ok = false

            for attempt = 1, 20 do

                if forwardMining() then
                    ok = true
                    break
                end

                sleep(0.1)
            end


            if not ok then
                error(
                    "Kann nicht zur naechsten Zelle."
                )
            end


            col = col + 1


        -- Naechste Reihe.
        elseif row < DEPTH then

            face(
                rowChangeDirection()
            )


            local ok = false

            for attempt = 1, 20 do

                if forwardMining() then
                    ok = true
                    break
                end

                sleep(0.1)
            end


            if not ok then
                error(
                    "Kann nicht zur naechsten Reihe."
                )
            end


            row = row + 1
            col = 1


        -- Naechste Ebene.
        else

            if not upMining() then

                error(
                    "Kann nicht zur naechsten Ebene."
                )
            end


            layer = layer + 1
            row = 1
            col = 1
        end


        cellDone = false

        saveState()


        sleep(0.05)
    end
end


-- ============================================================
-- CTRL+T / SERVERABBRUCH
-- ============================================================

local function interruptWatcher()

    while true do

        local event =
            os.pullEventRaw()


        if event == "terminate" then

            saveState()


            print("")
            print(
                "Miner angehalten."
            )

            print(
                "Position wurde gespeichert."
            )

            error(
                "Abbruch",
                0
            )
        end
    end
end


-- ============================================================
-- START
-- ============================================================

print("")
print("==============================")
print("      MINER - START")
print("==============================")
print("")

local loaded =
    loadState()


if loaded then

    print("Gespeicherter Auftrag gefunden.")

    print(
        "Position: "
        .. tostring(x)
        .. ", "
        .. tostring(y)
        .. ", "
        .. tostring(z)
    )

    print(
        "Ebene: "
        .. tostring(layer)
        .. "/"
        .. tostring(HEIGHT)
    )

    print("")


    -- --------------------------------------------------------
    -- Nach Serverrestart waehrend Versorgung
    -- --------------------------------------------------------

    if phase == "returning"
        or phase == "at_chest" then

        print(
            "Versorgung wird fortgesetzt."
        )


        if x ~= -1 then
            goToChest()
        end


        unload()
        refillFuel()
        refillTorches()
        refillBuckets()

        leaveChest()


        phase =
            "returning_to_work"

        saveState()


        returnToTarget()


        x = target.x
        y = target.y
        z = target.z
        dir = target.dir

        layer = target.layer
        row = target.row
        col = target.col

        cellDone =
            target.cellDone

        torchCounter =
            target.torchCounter

        target = nil

        phase = "mining"

        saveState()


    elseif phase == "returning_to_work" then

        print(
            "Rueckkehr zur Arbeitsposition wird "
            .. "fortgesetzt."
        )


        returnToTarget()


        x = target.x
        y = target.y
        z = target.z
        dir = target.dir

        layer = target.layer
        row = target.row
        col = target.col

        cellDone =
            target.cellDone

        torchCounter =
            target.torchCounter

        target = nil

        phase = "mining"

        saveState()


    elseif phase == "finished" then

        print(
            "Der Auftrag wurde bereits beendet."
        )

        print(
            "Fuer einen neuen Auftrag:"
        )

        print(
            "miner new <breite> <tiefe> <hoehe>"
        )

        return
    end


else

    -- Neuer Auftrag.
    x = 0
    y = 0
    z = 0
    dir = 0

    layer = 1
    row = 1
    col = 1

    cellDone = false

    torchCounter = 0

    phase = "mining"

    target = nil

    saveState()

    print("Neuer Mining-Auftrag.")
    print("")
end


-- ============================================================
-- PARALLEL STARTEN
-- ============================================================

local ok, err =
    pcall(
        function()

            parallel.waitForAny(
                mine,
                interruptWatcher
            )
        end
    )


if not ok then

    pcall(saveState)


    print("")
    print("==============================")
    print("          FEHLER")
    print("==============================")
    print("")
    print(tostring(err))
    print("")
    print("Position wurde gespeichert.")
    print("Beim naechsten Start wird fortgesetzt.")
    print("")
end

