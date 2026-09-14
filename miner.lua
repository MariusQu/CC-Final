-- ============================================================
-- MINER V6
-- CC:Tweaked 1.113.1
-- Minecraft 1.20.x
--
-- AUFBAU:
--
-- [KISTE] [TURTLE] ---> ABBAUBEREICH
--
-- Die Turtle schaut beim Start von der Kiste weg.
--
-- ============================================================
--
-- V6 AENDERUNGEN:
--
-- 1. Abbau erfolgt in 2 Bloecke hohen Ebenen.
--
-- 2. Nach einer 2-Block-Ebene geht die Turtle 2 Bloecke hoch.
--
-- 3. Fackeln werden hinter der Turtle an der Wand platziert.
--
-- 4. Fackeln werden NICHT bei jedem Kistenbesuch entladen.
--
-- 5. Es wird nur nachgefuellt, wenn weniger als MIN_TORCHES
--    Fackeln vorhanden sind.
--
-- 6. Die Turtle muss nicht 64 Fackeln tragen.
--
-- 7. Fortschritt wird dauerhaft gespeichert.
--
-- ============================================================


local STATE_FILE = "miner_state"
local VERSION = 6


-- ============================================================
-- KONFIGURATION
-- ============================================================

local MIN_FUEL = 1000
local FUEL_MARGIN = 50

-- Ab dieser Anzahl werden Fackeln nachgefuellt.
local MIN_TORCHES = 8

-- So viele werden maximal nachgeholt.
local REFILL_TORCHES = 16

-- Abstand zwischen Fackeln.
local DEFAULT_TORCH_DISTANCE = 6

-- Leere Eimer.
local MIN_BUCKETS = 2
local REFILL_BUCKETS = 4

-- Mindestens freie Inventarslots.
local MIN_FREE_SLOTS = 2


-- ============================================================
-- ARGUMENTE
-- ============================================================

local args = {...}
local command = args[1]


-- ============================================================
-- FEHLER
-- ============================================================

local function die(message)
    error(message, 0)
end


-- ============================================================
-- HILFE
-- ============================================================

local function usage()

    print("")
    print("==============================")
    print("          MINER V6")
    print("==============================")
    print("")

    print("Neuer Auftrag:")
    print(
        "miner new <breite> <tiefe> <hoehe> [fackelabstand]"
    )

    print("")
    print("Beispiel:")
    print("miner new 5 5 10 6")

    print("")
    print("Status:")
    print("miner status")

    print("")
    print("Reset:")
    print("miner reset")

    print("")
end


-- ============================================================
-- STATE
-- ============================================================

local state


local function save()

    local file, err =
        fs.open(STATE_FILE, "w")


    if not file then

        die(
            "Kann miner_state nicht speichern: " ..
            tostring(err)
        )
    end


    file.write(
        textutils.serialize(state)
    )

    file.close()
end


local function loadState()

    if not fs.exists(STATE_FILE) then
        return nil
    end


    local file, err =
        fs.open(STATE_FILE, "r")


    if not file then

        die(
            "Kann miner_state nicht lesen: " ..
            tostring(err)
        )
    end


    local data =
        textutils.unserialize(
            file.readAll()
        )


    file.close()


    if not data then
        die("miner_state ist beschaedigt.")
    end


    if data.version ~= VERSION then

        die(
            "Alter miner_state gefunden.\n" ..
            "Bitte 'miner reset' ausfuehren."
        )
    end


    return data
end


-- ============================================================
-- STATUS
-- ============================================================

if command == "status" then

    state = loadState()


    if not state then

        print("")
        print("Kein gespeicherter Auftrag.")
        print("")

        return
    end


    local total =
        state.width *
        state.depth *
        state.layers


    print("")
    print("==============================")
    print("         MINER STATUS")
    print("==============================")
    print("")


    print(
        "Raum: " ..
        state.width ..
        " x " ..
        state.depth ..
        " x " ..
        state.height
    )


    print(
        "Position: " ..
        state.x ..
        ", " ..
        state.y ..
        ", " ..
        state.z
    )


    print(
        "Ebene: " ..
        state.layer ..
        "/" ..
        state.layers
    )


    print(
        "Reihe: " ..
        state.row ..
        "/" ..
        state.depth
    )


    print(
        "Spalte: " ..
        state.col ..
        "/" ..
        state.width
    )


    print(
        "Fortschritt: " ..
        state.nextCell ..
        "/" ..
        total
    )


    print(
        "Phase: " ..
        tostring(state.phase)
    )


    print(
        "Fuel: " ..
        tostring(turtle.getFuelLevel())
    )


    print(
        "Fackeln: " ..
        tostring(
            state.torchCount or 0
        )
    )


    print("")
    print("==============================")
    print("")

    return
end


-- ============================================================
-- RESET
-- ============================================================

if command == "reset" then

    if fs.exists(STATE_FILE) then

        fs.delete(STATE_FILE)

        print(
            "miner_state wurde geloescht."
        )

    else

        print(
            "Kein miner_state vorhanden."
        )
    end


    return
end


-- ============================================================
-- NEUER AUFTRAG
-- ============================================================

if command == "new" then

    local width =
        tonumber(args[2])

    local depth =
        tonumber(args[3])

    local height =
        tonumber(args[4])

    local torchDistance =
        tonumber(args[5])
        or DEFAULT_TORCH_DISTANCE


    if not width
    or not depth
    or not height then

        usage()
        return
    end


    if width < 1
    or depth < 1
    or height < 1 then

        die(
            "Breite, Tiefe und Hoehe muessen mindestens 1 sein."
        )
    end


    if torchDistance < 0 then
        torchDistance = 0
    end


    -- ========================================================
    -- 2-BLOCK-EBENEN
    --
    -- Beispiel Hoehe 10:
    --
    -- Ebene 1 = Y 0-1
    -- Ebene 2 = Y 2-3
    -- Ebene 3 = Y 4-5
    -- Ebene 4 = Y 6-7
    -- Ebene 5 = Y 8-9
    --
    -- Bei ungerader Hoehe:
    --
    -- Hoehe 5:
    -- Ebene 1 = 0-1
    -- Ebene 2 = 2-3
    -- Ebene 3 = 4
    --
    -- ========================================================

    local layers =
        math.ceil(height / 2)


    if fs.exists(STATE_FILE) then
        fs.delete(STATE_FILE)
    end


    state = {

        version = VERSION,

        width = width,
        depth = depth,
        height = height,

        layers = layers,

        torchDistance =
            torchDistance,

        x = 0,
        y = 0,
        z = 0,

        -- 0 = +X
        -- 1 = +Z
        -- 2 = -X
        -- 3 = -Z
        dir = 0,

        layer = 1,

        row = 1,

        col = 1,

        nextCell = 1,

        torchCounter = 0,

        -- Wird NICHT mehr fuer die eigentliche
        -- Inventarzahl verwendet, sondern nur
        -- fuer Status.
        torchCount = 0,

        phase = "mining",

        returnTarget = nil
    }


    save()


    print("")
    print("==============================")
    print("       NEUER MINER V6")
    print("==============================")
    print("")


    print(
        "Raum: " ..
        width ..
        " x " ..
        depth ..
        " x " ..
        height
    )


    print(
        "Arbeitsebenen: " ..
        layers
    )


    print(
        "Fackelabstand: " ..
        torchDistance
    )


    print("")
    print("Aufbau:")
    print("")
    print("[KISTE] [TURTLE] ---> ABBAUBEREICH")
    print("")
    print("Die Turtle muss von der Kiste wegschauen.")
    print("")
end


-- ============================================================
-- AUFTRAG LADEN
-- ============================================================

if not state then

    state = loadState()


    if not state then

        usage()

        return
    end
end


-- ============================================================
-- INVENTAR
-- ============================================================

local function freeSlots()

    local free = 0


    for slot = 1, 16 do

        if turtle.getItemCount(slot) == 0 then

            free = free + 1
        end
    end


    return free
end


local function countItem(name)

    local total = 0


    for slot = 1, 16 do

        local item =
            turtle.getItemDetail(slot)


        if item
        and item.name == name then

            total =
                total + item.count
        end
    end


    return total
end


local function findItem(name)

    for slot = 1, 16 do

        local item =
            turtle.getItemDetail(slot)


        if item
        and item.name == name then

            return slot
        end
    end


    return nil
end


-- ============================================================
-- RICHTUNG
-- ============================================================

local function turnRight()

    turtle.turnRight()

    state.dir =
        (state.dir + 1) % 4

    save()
end


local function turnLeft()

    turtle.turnLeft()

    state.dir =
        (state.dir + 3) % 4

    save()
end


local function face(direction)

    local diff =
        (direction - state.dir) % 4


    if diff == 1 then

        turnRight()

    elseif diff == 2 then

        turnRight()
        turnRight()

    elseif diff == 3 then

        turnLeft()
    end
end


-- ============================================================
-- POSITION
-- ============================================================

local function updateForward()

    if state.dir == 0 then

        state.x =
            state.x + 1

    elseif state.dir == 1 then

        state.z =
            state.z + 1

    elseif state.dir == 2 then

        state.x =
            state.x - 1

    elseif state.dir == 3 then

        state.z =
            state.z - 1
    end
end


-- ============================================================
-- FUEL
-- ============================================================

local function fuel()

    return turtle.getFuelLevel()
end


local function distanceHome()

    return
        math.abs(state.x) +
        math.abs(state.y) +
        math.abs(state.z)
end


local service


local function ensureFuel()

    local current =
        fuel()


    if current == "unlimited" then
        return
    end


    local needed =
        distanceHome()
        + MIN_FUEL
        + FUEL_MARGIN


    if current < needed then

        service()
    end
end


-- ============================================================
-- FLUESSIGKEIT
-- ============================================================

local function isFluid(data)

    if not data
    or not data.name then

        return false
    end


    local name =
        string.lower(data.name)


    return
        name == "minecraft:water"
        or
        name == "minecraft:lava"
end


local function collectFront()

    local slot =
        findItem("minecraft:bucket")


    if not slot then

        service()


        slot =
            findItem("minecraft:bucket")
    end


    if not slot then

        die(
            "Kein leerer Eimer vorhanden."
        )
    end


    local old =
        turtle.getSelectedSlot()


    turtle.select(slot)


    local result =
        turtle.place()


    turtle.select(old)


    return result
end


local function collectUp()

    local slot =
        findItem("minecraft:bucket")


    if not slot then

        service()


        slot =
            findItem("minecraft:bucket")
    end


    if not slot then

        die(
            "Kein leerer Eimer vorhanden."
        )
    end


    local old =
        turtle.getSelectedSlot()


    turtle.select(slot)


    local result =
        turtle.placeUp()


    turtle.select(old)


    return result
end


local function collectDown()

    local slot =
        findItem("minecraft:bucket")


    if not slot then

        service()


        slot =
            findItem("minecraft:bucket")
    end


    if not slot then

        die(
            "Kein leerer Eimer vorhanden."
        )
    end


    local old =
        turtle.getSelectedSlot()


    turtle.select(slot)


    local result =
        turtle.placeDown()


    turtle.select(old)


    return result
end


-- ============================================================
-- VORWAERTS
-- ============================================================

local function forward()

    ensureFuel()


    while true do

        if turtle.forward() then

            updateForward()

            save()

            return
        end


        local ok, data =
            turtle.inspect()


        if ok and isFluid(data) then

            collectFront()

        else

            if freeSlots()
                < MIN_FREE_SLOTS then

                service()
            end


            if not turtle.dig() then

                turtle.attack()

                sleep(0.1)
            end
        end


        sleep(0.05)
    end
end


-- ============================================================
-- HOCH
-- ============================================================

local function up()

    ensureFuel()


    while true do

        if turtle.up() then

            state.y =
                state.y + 1

            save()

            return
        end


        local ok, data =
            turtle.inspectUp()


        if ok and isFluid(data) then

            collectUp()

        else

            if freeSlots()
                < MIN_FREE_SLOTS then

                service()
            end


            if not turtle.digUp() then

                turtle.attackUp()

                sleep(0.1)
            end
        end


        sleep(0.05)
    end
end


-- ============================================================
-- RUNTER
-- ============================================================

local function down()

    ensureFuel()


    while true do

        if turtle.down() then

            state.y =
                state.y - 1

            save()

            return
        end


        local ok, data =
            turtle.inspectDown()


        if ok and isFluid(data) then

            collectDown()

        else

            if freeSlots()
                < MIN_FREE_SLOTS then

                service()
            end


            if not turtle.digDown() then

                turtle.attackDown()

                sleep(0.1)
            end
        end


        sleep(0.05)
    end
end


-- ============================================================
-- ZU POSITION
-- ============================================================

local function goTo(targetX, targetY, targetZ)

    -- Y.
    while state.y < targetY do
        up()
    end


    while state.y > targetY do
        down()
    end


    -- X.
    while state.x < targetX do

        face(0)

        forward()
    end


    while state.x > targetX do

        face(2)

        forward()
    end


    -- Z.
    while state.z < targetZ do

        face(1)

        forward()
    end


    while state.z > targetZ do

        face(3)

        forward()
    end
end


-- ============================================================
-- KISTE
-- ============================================================

local function checkChest()

    local ok, data =
        turtle.inspect()


    if not ok then

        die(
            "Keine Kiste hinter der Turtle gefunden.\n\n" ..
            "Aufbau:\n" ..
            "[KISTE] [TURTLE] ---> MINING"
        )
    end


    local name =
        string.lower(
            data.name or ""
        )


    if not string.find(
        name,
        "chest",
        1,
        true
    ) then

        die(
            "Hinter der Turtle steht keine Kiste."
        )
    end
end


local function getChest()

    local chest =
        peripheral.wrap("front")


    if not chest then

        die(
            "Die Kiste konnte nicht als Inventar erkannt werden.\n\n" ..
            "Falls dies auf einem Server passiert, ist vermutlich " ..
            "der Generic-Peripheral-Zugriff eingeschraenkt."
        )
    end


    if not chest.list
    or not chest.size
    or not chest.pushItems then

        die(
            "Die Kiste stellt keine Inventar-Funktionen bereit."
        )
    end


    return chest
end


-- ============================================================
-- ENTLADEN
--
-- WICHTIG:
--
-- Fackeln bleiben in der Turtle.
-- Leere Eimer bleiben in der Turtle.
--
-- Alles andere wird ausgeladen.
-- ============================================================

local function unload(chest)

    print("Inventar wird entladen...")


    for slot = 1, 16 do

        local item =
            turtle.getItemDetail(slot)


        if item then

            local keep = false


            -- Fackeln NICHT ausladen.
            if item.name ==
                "minecraft:torch" then

                keep = true
            end


            -- Leere Eimer NICHT ausladen.
            if item.name ==
                "minecraft:bucket" then

                keep = true
            end


            if not keep then

                turtle.select(slot)


                local ok =
                    turtle.drop()


                if not ok
                and turtle.getItemCount(slot) > 0 then

                    die(
                        "Kiste ist voll oder konnte Slot " ..
                        slot ..
                        " nicht aufnehmen."
                    )
                end
            end
        end
    end


    turtle.select(1)


    state.torchCount =
        countItem("minecraft:torch")


    save()
end


-- ============================================================
-- ITEM AUS KISTE HOLEN
-- ============================================================

local function chestFind(chest, wanted)

    local items =
        chest.list()


    for slot, item in pairs(items) do

        for _, name in ipairs(wanted) do

            if item.name == name then

                return slot
            end
        end
    end


    return nil
end


local function take(chest, wanted, amount)

    local source =
        chestFind(
            chest,
            wanted
        )


    if not source then
        return false
    end


    local target = nil


    for slot = 1, 16 do

        local item =
            turtle.getItemDetail(slot)


        if not item then

            target = slot
            break
        end


        if item.name == wanted[1]
        and turtle.getItemSpace(slot) > 0 then

            target = slot
            break
        end
    end


    if not target then
        return false
    end


    local old =
        turtle.getSelectedSlot()


    turtle.select(target)


    local result =
        turtle.suck(amount)


    turtle.select(old)


    return result
end


-- ============================================================
-- FUEL
-- ============================================================

local function refuel()

    if fuel() == "unlimited" then
        return
    end


    if fuel() >= MIN_FUEL then
        return
    end


    print("Fuel wird aufgefuellt...")


    -- Bereits vorhandenes Fuel verwenden.
    for slot = 1, 16 do

        local item =
            turtle.getItemDetail(slot)


        if item then

            local name =
                item.name


            if name == "minecraft:coal"
            or name == "minecraft:charcoal"
            or name == "minecraft:coal_block" then

                turtle.select(slot)


                while turtle.refuel(1) do
                end
            end
        end
    end


    turtle.select(1)


    if fuel() >= MIN_FUEL then
        return
    end


    local chest =
        getChest()


    while fuel() < MIN_FUEL do

        local got =
            take(
                chest,
                {
                    "minecraft:coal",
                    "minecraft:charcoal",
                    "minecraft:coal_block"
                },
                64
            )


        if not got then
            break
        end


        for slot = 1, 16 do

            local item =
                turtle.getItemDetail(slot)


            if item
            and (
                item.name ==
                    "minecraft:coal"
                or
                item.name ==
                    "minecraft:charcoal"
                or
                item.name ==
                    "minecraft:coal_block"
            ) then

                turtle.select(slot)


                while turtle.refuel(1) do
                end
            end
        end
    end


    turtle.select(1)


    if fuel() < MIN_FUEL then

        die(
            "Nicht genug Fuel in der Kiste."
        )
    end
end


-- ============================================================
-- FACKELN NACHFUELLEN
-- ============================================================

local function refillTorches(chest)

    if state.torchDistance <= 0 then
        return
    end


    local current =
        countItem("minecraft:torch")


    state.torchCount =
        current


    -- Noch genug vorhanden.
    if current >= MIN_TORCHES then

        save()

        return
    end


    print(
        "Nur " ..
        current ..
        " Fackeln vorhanden."
    )


    print("Fackeln werden nachgefuellt...")


    local needed =
        REFILL_TORCHES - current


    if needed < 1 then
        return
    end


    local got =
        take(
            chest,
            {
                "minecraft:torch"
            },
            needed
        )


    if not got then

        die(
            "Keine Fackeln in der Kiste."
        )
    end


    state.torchCount =
        countItem("minecraft:torch")


    save()


    if state.torchCount
        < MIN_TORCHES then

        die(
            "Zu wenige Fackeln vorhanden."
        )
    end
end


-- ============================================================
-- EIMER
-- ============================================================

local function refillBuckets(chest)

    local current =
        countItem("minecraft:bucket")


    if current >= MIN_BUCKETS then
        return
    end


    print("Leere Eimer werden nachgefuellt...")


    local needed =
        REFILL_BUCKETS - current


    local got =
        take(
            chest,
            {
                "minecraft:bucket"
            },
            needed
        )


    if not got then

        die(
            "Keine leeren Eimer in der Kiste."
        )
    end


    if countItem("minecraft:bucket")
        < MIN_BUCKETS then

        die(
            "Zu wenige leere Eimer vorhanden."
        )
    end
end


-- ============================================================
-- SERVICE
-- ============================================================

service = function()

    if state.phase == "mining" then

        state.returnTarget = {

            x = state.x,
            y = state.y,
            z = state.z,
            dir = state.dir
        }


        state.phase = "service"

        save()
    end


    local target =
        state.returnTarget


    if not target then

        die(
            "Kein Rueckkehrziel gespeichert."
        )
    end


    print("")
    print("==============================")
    print("         ZUR KISTE")
    print("==============================")


    -- Zum Startpunkt.
    goTo(0, 0, 0)


    -- Kiste liegt hinter der Turtle.
    face(2)


    checkChest()


    local chest =
        getChest()


    -- Beute ausladen.
    -- Fackeln und Eimer bleiben drin.
    unload(chest)


    -- Fuel.
    refuel()


    -- Fackeln nur bei Bedarf.
    refillTorches(chest)


    -- Eimer nur bei Bedarf.
    refillBuckets(chest)


    -- Wieder Richtung Mining.
    face(0)


    -- Zum alten Arbeitsplatz.
    goTo(
        target.x,
        target.y,
        target.z
    )


    face(target.dir)


    state.returnTarget = nil

    state.phase = "mining"


    save()


    print("Zurueck am Arbeitsplatz.")
    print("")
end


-- ============================================================
-- FACKEL HINTER DER TURTLE
-- ============================================================

local function placeTorch()

    if state.torchDistance <= 0 then
        return
    end


    state.torchCounter =
        state.torchCounter + 1


    if state.torchCounter
        < state.torchDistance then

        save()

        return
    end


    local slot =
        findItem("minecraft:torch")


    if not slot then

        service()


        slot =
            findItem("minecraft:torch")
    end


    if not slot then

        die(
            "Keine Fackeln vorhanden."
        )
    end


    local old =
        turtle.getSelectedSlot()


    turtle.select(slot)


    -- ========================================================
    -- WICHTIG:
    --
    -- Fackel wird HINTER der Turtle platziert.
    --
    -- Dazu dreht sich die Turtle kurz um 180 Grad.
    --
    -- Dadurch wird turtle.place() verwendet und
    -- nicht placeDown().
    -- ========================================================

    local oldDir =
        state.dir


    face(
        (oldDir + 2) % 4
    )


    local placed =
        turtle.place()


    face(oldDir)


    turtle.select(old)


    if placed then

        state.torchCounter = 0

    else

        -- Stelle war ungeeignet.
        -- Zaehler nicht zuruecksetzen, damit
        -- spaeter erneut versucht wird.
        print(
            "Fackel konnte nicht gesetzt werden."
        )
    end


    state.torchCount =
        countItem("minecraft:torch")


    save()
end


-- ============================================================
-- ZELLE ABBauen
-- ============================================================

local function mineCell()

    -- --------------------------------------------------------
    -- UNTERE HAELFTE
    -- --------------------------------------------------------

    -- Wasser/Lava vor der Turtle.
    local ok, data =
        turtle.inspect()


    if ok and isFluid(data) then

        collectFront()

    end


    -- --------------------------------------------------------
    -- OBERE HAELFTE
    --
    -- Wenn wir in einer normalen 2er-Ebene sind,
    -- befindet sich ein Block ueber uns.
    --
    -- Diesen bauen wir ab.
    -- --------------------------------------------------------

    local layerBottom =
        (state.layer - 1) * 2


    local layerTop =
        layerBottom + 1


    if layerTop < state.height then

        local upOk, upData =
            turtle.inspectUp()


        if upOk then

            if isFluid(upData) then

                collectUp()

            else

                if freeSlots()
                    < MIN_FREE_SLOTS then

                    service()
                end


                turtle.digUp()
            end
        end
    end


    -- Fackel setzen.
    placeTorch()


    save()
end


-- ============================================================
-- ZIELPOSITION
-- ============================================================

local function cellPosition(index)

    local width =
        state.width

    local depth =
        state.depth


    local perLayer =
        width * depth


    local layer =
        math.floor(
            (index - 1) / perLayer
        ) + 1


    local inside =
        (index - 1) % perLayer


    local row =
        math.floor(
            inside / width
        ) + 1


    local col =
        (inside % width) + 1


    local x


    -- Zickzack.
    if row % 2 == 1 then

        x = col - 1

    else

        x =
            width - col
    end


    local z =
        row - 1


    local y =
        (layer - 1) * 2


    return x, y, z
end


-- ============================================================
-- FERTIG
-- ============================================================

local function finish()

    state.phase = "final"

    save()


    print("")
    print("==============================")
    print("        MINING FERTIG")
    print("==============================")
    print("")


    -- Zur Startposition.
    goTo(0, 0, 0)


    -- Kiste hinter uns.
    face(2)


    checkChest()


    local chest =
        getChest()


    -- Fackeln und Eimer bleiben.
    unload(chest)


    face(0)


    state.phase = "finished"

    save()


    print("")
    print("==============================")
    print("           FERTIG")
    print("==============================")
    print("")

    print(
        "Fackeln behalten: " ..
        countItem("minecraft:torch")
    )

    print(
        "Eimer behalten: " ..
        countItem("minecraft:bucket")
    )

    print("")
end


-- ============================================================
-- WIEDERHERSTELLUNG
-- ============================================================

local function resumeService()

    print("")
    print("Unterbrochener Service gefunden.")
    print("")

    service()
end


local function resumeFinal()

    print("")
    print("Unterbrochene Rueckkehr gefunden.")
    print("")


    goTo(0, 0, 0)


    face(2)


    checkChest()


    local chest =
        getChest()


    unload(chest)


    face(0)


    state.phase = "finished"

    save()


    print("")
    print("Auftrag abgeschlossen.")
    print("")
end


-- ============================================================
-- HAUPTPROGRAMM
-- ============================================================

print("")
print("==============================")
print("          MINER V6")
print("==============================")
print("")


-- ------------------------------------------------------------
-- FERTIG
-- ------------------------------------------------------------

if state.phase == "finished" then

    print(
        "Dieser Auftrag ist bereits fertig."
    )

    print("")
    print(
        "Fuer einen neuen Auftrag:"
    )

    print(
        "miner new <breite> <tiefe> <hoehe> [fackelabstand]"
    )

    return
end


-- ------------------------------------------------------------
-- SERVICE FORTSETZEN
-- ------------------------------------------------------------

if state.phase == "service" then

    resumeService()

    return
end


-- ------------------------------------------------------------
-- FINALISIERUNG FORTSETZEN
-- ------------------------------------------------------------

if state.phase == "final" then

    resumeFinal()

    return
end


-- ============================================================
-- MINING
-- ============================================================

local total =
    state.width *
    state.depth *
    state.layers


while state.nextCell <= total do

    local index =
        state.nextCell


    local x, y, z =
        cellPosition(index)


    -- Aktuelle Ebene speichern.
    state.layer =
        math.floor(y / 2) + 1


    state.row =
        z + 1


    state.col =
        x + 1


    save()


    print(
        "Zelle " ..
        index ..
        "/" ..
        total ..
        "  " ..
        x ..
        "," ..
        y ..
        "," ..
        z
    )


    -- Zur Zielposition.
    goTo(
        x,
        y,
        z
    )


    -- Zelle abbauen.
    mineCell()


    -- Zelle erst danach als erledigt markieren.
    state.nextCell =
        state.nextCell + 1


    save()


    sleep(0.05)
end


-- ============================================================
-- FERTIG
-- ============================================================

finish()

