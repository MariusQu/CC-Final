-- ============================================================
-- MINER V5
-- CC:Tweaked 1.113.1
-- Minecraft 1.20.x
--
-- AUFBAU:
--
-- [KISTE] [TURTLE] ---> ABBAUBEREICH
--
-- Die Turtle schaut beim Start VON der Kiste WEG.
-- Kiste und Turtle befinden sich auf einer geraden Linie.
--
-- Funktionen:
--   * Raum abbauen
--   * Zickzack-Muster
--   * Fackeln setzen
--   * Wasser/Lava aufnehmen
--   * Inventar entladen
--   * Fuel nachfuellen
--   * Fackeln nachfuellen
--   * leere Eimer nachfuellen
--   * Position speichern
--   * nach Neustart fortsetzen
--   * bei vollem Inventar zur Kiste
--   * danach zum Mining zurueck
--
-- Befehle:
--
--   miner new <breite> <tiefe> <hoehe> [fackelabstand]
--   miner status
--   miner reset
--
-- Beispiel:
--
--   miner new 5 5 2 4
--
-- ============================================================


local STATE_FILE = "miner_state"
local VERSION = 5


-- ============================================================
-- KONFIGURATION
-- ============================================================

local MIN_FUEL = 1000

local MIN_TORCHES = 8
local REFILL_TORCHES = 32

local MIN_BUCKETS = 2
local REFILL_BUCKETS = 4

local DEFAULT_TORCH_DISTANCE = 6

local FUEL_MARGIN = 50

local MIN_FREE_SLOTS = 2


-- ============================================================
-- ARGUMENTE
-- ============================================================

local args = {...}

local command = args[1]


-- ============================================================
-- HILFSFUNKTION
-- ============================================================

local function die(message)
    error(message, 0)
end


local function usage()

    print("")
    print("==============================")
    print("          MINER V5")
    print("==============================")
    print("")
    print("Neuer Auftrag:")
    print("")
    print("miner new <breite> <tiefe> <hoehe> [fackeln]")
    print("")
    print("Beispiel:")
    print("miner new 5 5 2 4")
    print("")
    print("Status:")
    print("miner status")
    print("")
    print("Reset:")
    print("miner reset")
    print("")
end


-- ============================================================
-- SPEICHERN
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


-- ============================================================
-- LADEN
-- ============================================================

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

        die(
            "miner_state ist beschaedigt."
        )
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
        print("Kein Auftrag gespeichert.")
        print("")

        return
    end


    local total =
        state.width *
        state.depth *
        state.height


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
        "Zelle: " ..
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


    print("")


    if state.returnTarget then

        print(
            "Rueckkehrziel: " ..
            state.returnTarget.x ..
            ", " ..
            state.returnTarget.y ..
            ", " ..
            state.returnTarget.z
        )
    end


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


    if fs.exists(STATE_FILE) then
        fs.delete(STATE_FILE)
    end


    -- ========================================================
    -- KOORDINATENSYSTEM
    --
    -- Start:
    --
    -- KISTE = x = -1
    -- TURTLE = x = 0
    -- ABBAUBEREICH = x >= 0
    --
    -- Turtle schaut nach +X.
    -- ========================================================

    state = {

        version = VERSION,

        width = width,
        depth = depth,
        height = height,

        torchDistance = torchDistance,

        x = 0,
        y = 0,
        z = 0,

        -- 0 = +X
        -- 1 = +Z
        -- 2 = -X
        -- 3 = -Z
        dir = 0,

        nextCell = 1,

        torchCounter = 0,

        phase = "mining",

        returnTarget = nil
    }


    save()


    print("")
    print("==============================")
    print("       NEUER MINER")
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

        print(
            "Noch kein Auftrag vorhanden."
        )

        return
    end
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
        distanceHome() +
        MIN_FUEL +
        FUEL_MARGIN


    if current < needed then

        if state.phase == "service" then

            die(
                "Fuel reicht fuer Rueckkehr nicht aus."
            )
        end


        service()
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

    -- Hoehe.
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
-- KISTE PRUEFEN
-- ============================================================

local function checkChest()

    local ok, data =
        turtle.inspect()


    if not ok then

        die(
            "Keine Kiste gefunden.\n\n" ..
            "Erwarteter Aufbau:\n" ..
            "[KISTE] [TURTLE] ---> MINING\n\n" ..
            "Die Turtle muss beim Start von der Kiste wegschauen."
        )
    end


    local name =
        string.lower(data.name or "")


    if not string.find(
        name,
        "chest",
        1,
        true
    ) then

        die(
            "Das Objekt hinter der Turtle ist keine Kiste.\n\n" ..
            "Erwarteter Aufbau:\n" ..
            "[KISTE] [TURTLE] ---> MINING"
        )
    end
end


-- ============================================================
-- KISTEN-PERIPHERAL
-- ============================================================

local function getChest()

    local chest =
        peripheral.wrap("front")


    if not chest then

        die(
            "Die Kiste konnte nicht als Inventar erkannt werden.\n\n" ..
            "Falls das ein Server ist, kann Generic-Peripheral-" ..
            "Zugriff deaktiviert sein."
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
-- KISTE ENTLADEN
-- ============================================================

local function unload(chest)

    print("Inventar wird entladen...")


    for slot = 1, 16 do

        if turtle.getItemCount(slot) > 0 then

            turtle.select(slot)


            local ok =
                turtle.drop()


            if not ok
            and turtle.getItemCount(slot) > 0 then

                die(
                    "Kiste ist voll oder konnte Gegenstand " ..
                    "aus Slot " .. slot ..
                    "nicht aufnehmen."
                )
            end
        end
    end


    turtle.select(1)
end


-- ============================================================
-- KISTE NACH ITEM DURCHSUCHEN
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


-- ============================================================
-- ITEM AUS KISTE HOLEN
-- ============================================================

local function take(chest, wanted, amount)

    local slot =
        chestFind(chest, wanted)


    if not slot then
        return false
    end


    local old =
        turtle.getSelectedSlot()


    -- Freien Turtle-Slot suchen.
    local targetSlot = nil


    for i = 1, 16 do

        local item =
            turtle.getItemDetail(i)


        if not item then

            targetSlot = i
            break
        end


        if item.name == wanted[1]
        and turtle.getItemSpace(i) > 0 then

            targetSlot = i
            break
        end
    end


    if not targetSlot then

        turtle.select(old)

        return false
    end


    turtle.select(targetSlot)


    local result =
        turtle.suck(amount)


    turtle.select(old)


    return result
end


-- ============================================================
-- FUEL NACHFUELLEN
-- ============================================================

local function refuel()

    if fuel() == "unlimited" then
        return
    end


    print("Fuel wird aufgefuellt...")


    -- Vorhandenes Fuel verbrennen.
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


    -- Neue Kohle holen.
    while fuel() < MIN_FUEL do

        if not take(
            getChest(),
            {"minecraft:coal"},
            64
        ) then

            break
        end


        for slot = 1, 16 do

            local item =
                turtle.getItemDetail(slot)


            if item
            and item.name == "minecraft:coal" then

                turtle.select(slot)

                while turtle.refuel(1) do
                end
            end
        end
    end


    -- Holzkohle.
    while fuel() < MIN_FUEL do

        if not take(
            getChest(),
            {"minecraft:charcoal"},
            64
        ) then

            break
        end


        for slot = 1, 16 do

            local item =
                turtle.getItemDetail(slot)


            if item
            and item.name == "minecraft:charcoal" then

                turtle.select(slot)

                while turtle.refuel(1) do
                end
            end
        end
    end


    turtle.select(1)


    if fuel() < MIN_FUEL then

        die(
            "Nicht genug Fuel in der Kiste.\n" ..
            "Bitte Kohle oder Holzkohle hineinlegen."
        )
    end
end


-- ============================================================
-- FACKELN
-- ============================================================

local function refillTorches(chest)

    if state.torchDistance <= 0 then
        return
    end


    if countItem("minecraft:torch")
        >= MIN_TORCHES then

        return
    end


    print("Fackeln werden aufgefuellt...")


    local got =
        take(
            chest,
            {"minecraft:torch"},
            REFILL_TORCHES
        )


    if not got then

        die(
            "Keine Fackeln in der Kiste."
        )
    end


    if countItem("minecraft:torch")
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

    if countItem("minecraft:bucket")
        >= MIN_BUCKETS then

        return
    end


    print("Eimer werden aufgefuellt...")


    local got =
        take(
            chest,
            {"minecraft:bucket"},
            REFILL_BUCKETS
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
    print("       ZUR KISTE")
    print("==============================")


    -- ========================================================
    -- ZUR STARTPOSITION
    -- ========================================================

    goTo(0, 0, 0)


    -- ========================================================
    -- WICHTIG:
    --
    -- Start:
    --
    -- [KISTE] [TURTLE] ---> Mining
    --
    -- Die Turtle schaut +X.
    --
    -- Kiste ist deshalb bei -X.
    --
    -- Wir drehen uns nach -X.
    -- ========================================================

    face(2)


    checkChest()


    local chest =
        getChest()


    -- Inventar abladen.
    unload(chest)


    -- Vorräte.
    refuel()

    refillTorches(chest)

    refillBuckets(chest)


    -- Wieder Richtung Mining.
    face(0)


    -- ========================================================
    -- ZUM GENAUEN ARBEITSPLATZ
    -- ========================================================

    goTo(
        target.x,
        target.y,
        target.z
    )


    face(target.dir)


    state.returnTarget = nil

    state.phase = "mining"

    save()


    print("Rueckkehr abgeschlossen.")
    print("")
end


-- ============================================================
-- FACKEL SETZEN
-- ============================================================

local function torch()

    if state.torchDistance <= 0 then
        return
    end


    -- Nur auf dem Boden.
    if state.y ~= 0 then
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


    if turtle.placeDown() then

        state.torchCounter = 0
    end


    turtle.select(old)


    save()
end


-- ============================================================
-- EINE ZELLE
-- ============================================================

local function mineCell()

    -- Block ueber der Turtle.
    --
    -- Die Turtle selbst befindet sich auf
    -- der Hoehe der jeweiligen Ebene.
    --
    -- Alles darueber wird ebenfalls abgebaut.
    if state.y <
        state.height - 1 then


        while true do

            local ok, data =
                turtle.inspectUp()


            if not ok then
                break
            end


            if isFluid(data) then

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


    torch()


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
        )


    local inside =
        (index - 1) % perLayer


    local row =
        math.floor(
            inside / width
        )


    local col =
        inside % width


    local x


    -- Zickzack.
    if row % 2 == 0 then

        x = col

    else

        x = width - 1 - col
    end


    local y =
        layer

    local z =
        row


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


    -- Zur Turtle-Startposition.
    goTo(0, 0, 0)


    -- Kiste befindet sich hinter der Turtle.
    face(2)


    checkChest()


    local chest =
        getChest()


    unload(chest)


    -- Wieder geradeaus schauen.
    face(0)


    state.phase = "finished"

    save()


    print("")
    print("==============================")
    print("           FERTIG")
    print("==============================")
    print("")
    print("Inventar wurde entladen.")
    print("Turtle steht neben der Kiste.")
    print("")
end


-- ============================================================
-- WIEDERHERSTELLUNG
-- ============================================================

local function resumeService()

    print("")
    print("Unterbrochener Versorgungsauftrag gefunden.")
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
print("          MINER V5")
print("==============================")
print("")


if state.phase == "finished" then

    print(
        "Dieser Auftrag ist bereits fertig."
    )


    print("")
    print(
        "Neuer Auftrag:"
    )


    print(
        "miner new <breite> <tiefe> <hoehe>"
    )


    return
end


if state.phase == "service" then

    resumeService()

elseif state.phase == "final" then

    resumeFinal()

else

    local total =
        state.width *
        state.depth *
        state.height


    while state.nextCell <= total do

        local index =
            state.nextCell


        local x, y, z =
            cellPosition(index)


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
        goTo(x, y, z)


        -- Zelle abbauen.
        mineCell()


        -- Erst jetzt als erledigt markieren.
        state.nextCell =
            state.nextCell + 1


        save()


        sleep(0.05)
    end


    finish()
end

