-- ============================================================
--                       MINER V10.2
-- ============================================================
--
-- CC:Tweaked Mining Turtle
--
-- Aufbau:
--
--       KISTE
--         |
--       TURTLE  --->  MINING
--
-- Die Turtle steht direkt vor der Kiste und schaut
-- in Richtung des Abbaugebietes.
--
-- Befehle:
--
--   miner new <breite> <tiefe> <hoehe> [fackelabstand]
--   miner resume
--   miner status
--   miner reset
--
-- Beispiel:
--
--   miner new 10 20 6 6
--
-- ============================================================


local VERSION = 102
local STATE_FILE = "miner_state_v102"


local args = {...}
local command = args[1]


-- ============================================================
-- KONFIGURATION
-- ============================================================

local START_DIR = 0
local CHEST_DIR = 2

local MIN_FUEL = 200
local MIN_FREE_SLOTS = 2

local TORCH_NAME = "minecraft:torch"
local BUCKET_NAME = "minecraft:bucket"


-- ============================================================
-- STATE
-- ============================================================

local state = nil
local servicing = false


-- ============================================================
-- HILFE
-- ============================================================

local function usage()

    print("")
    print("==============================")
    print("         MINER V10.2")
    print("==============================")
    print("")

    print("Neuer Auftrag:")
    print("miner new <breite> <tiefe> <hoehe> [fackeln]")
    print("")

    print("Beispiel:")
    print("miner new 4 4 2 2")
    print("")

    print("Fortsetzen:")
    print("miner resume")
    print("")

    print("Status:")
    print("miner status")
    print("")

    print("Reset:")
    print("miner reset")
    print("")

end


-- ============================================================
-- STATE SPEICHERN
-- ============================================================

local function save()

    if state == nil then
        return
    end

    local file, err = fs.open(
        STATE_FILE,
        "w"
    )

    if file == nil then

        error(
            "State konnte nicht gespeichert werden: "
            .. tostring(err)
        )

    end

    file.write(
        textutils.serialize(state)
    )

    file.close()

end


-- ============================================================
-- STATE LADEN
-- ============================================================

local function loadState()

    if not fs.exists(STATE_FILE) then
        return nil
    end

    local file, err = fs.open(
        STATE_FILE,
        "r"
    )

    if file == nil then

        error(
            "State konnte nicht gelesen werden: "
            .. tostring(err)
        )

    end

    local content = file.readAll()

    file.close()

    local data =
        textutils.unserialize(content)


    if data == nil then

        error(
            "Der V10.2 State ist beschaedigt."
        )

    end


    if data.version ~= VERSION then

        print("")
        print("Alter State gefunden.")
        print("")
        print("Bitte ausfuehren:")
        print("")
        print("miner reset")
        print("")

        return nil

    end


    return data

end


-- ============================================================
-- INVENTAR
-- ============================================================

local function countItem(name)

    local total = 0

    for slot = 1, 16 do

        local item =
            turtle.getItemDetail(slot)

        if item ~= nil then

            if item.name == name then

                total =
                    total + item.count

            end

        end

    end

    return total

end


local function findItem(name)

    for slot = 1, 16 do

        local item =
            turtle.getItemDetail(slot)

        if item ~= nil then

            if item.name == name then
                return slot
            end

        end

    end

    return nil

end


local function freeSlots()

    local total = 0

    for slot = 1, 16 do

        if turtle.getItemCount(slot) == 0 then
            total = total + 1
        end

    end

    return total

end


local function keepItem(name)

    if name == TORCH_NAME then
        return true
    end

    if name == BUCKET_NAME then
        return true
    end

    if name == "minecraft:coal" then
        return true
    end

    if name == "minecraft:charcoal" then
        return true
    end

    return false

end


-- ============================================================
-- RICHTUNG
--
-- 0 = +X
-- 1 = +Z
-- 2 = -X
-- 3 = -Z
-- ============================================================

local function turnRight()

    local ok, err =
        turtle.turnRight()

    if not ok then

        error(
            "Rechts drehen fehlgeschlagen: "
            .. tostring(err)
        )

    end

    state.dir =
        (state.dir + 1) % 4

    save()

end


local function turnLeft()

    local ok, err =
        turtle.turnLeft()

    if not ok then

        error(
            "Links drehen fehlgeschlagen: "
            .. tostring(err)
        )

    end

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
-- FUEL
-- ============================================================

local function refuel()

    if turtle.getFuelLevel() == "unlimited" then
        return true
    end


    local oldSlot =
        turtle.getSelectedSlot()


    for slot = 1, 16 do

        local item =
            turtle.getItemDetail(slot)

        if item ~= nil then

            if item.name == "minecraft:coal"
            or item.name == "minecraft:charcoal" then

                turtle.select(slot)

                turtle.refuel()

            end

        end

    end


    turtle.select(oldSlot)


    if turtle.getFuelLevel() == "unlimited" then
        return true
    end


    return turtle.getFuelLevel() >= MIN_FUEL

end


local function fuelCheck()

    if turtle.getFuelLevel() == "unlimited" then
        return
    end


    if turtle.getFuelLevel() >= MIN_FUEL then
        return
    end


    refuel()


    if turtle.getFuelLevel() < MIN_FUEL then

        error(
            "Zu wenig Fuel. Bitte Kohle oder "
            .. "Charcoal in die Turtle legen."
        )

    end

end


-- ============================================================
-- FLUESSIGKEITEN
-- ============================================================

local function isFluid(data)

    if data == nil then
        return false
    end

    if data.name == nil then
        return false
    end

    if data.name == "minecraft:water" then
        return true
    end

    if data.name == "minecraft:lava" then
        return true
    end

    return false

end


local function getBucket()

    return findItem(BUCKET_NAME)

end


local function collectFront()

    local slot =
        getBucket()


    if slot == nil then

        error(
            "Fluessigkeit vorne, aber kein Eimer vorhanden."
        )

    end


    local oldSlot =
        turtle.getSelectedSlot()


    turtle.select(slot)

    local ok, err =
        turtle.place()


    turtle.select(oldSlot)


    if not ok then

        error(
            "Fluessigkeit vorne konnte nicht "
            .. "aufgenommen werden: "
            .. tostring(err)
        )

    end


    return true

end


local function collectUp()

    local slot =
        getBucket()


    if slot == nil then

        error(
            "Fluessigkeit oben, aber kein Eimer vorhanden."
        )

    end


    local oldSlot =
        turtle.getSelectedSlot()


    turtle.select(slot)

    local ok, err =
        turtle.placeUp()


    turtle.select(oldSlot)


    if not ok then

        error(
            "Fluessigkeit oben konnte nicht "
            .. "aufgenommen werden: "
            .. tostring(err)
        )

    end


    return true

end


local function collectDown()

    local slot =
        getBucket()


    if slot == nil then

        error(
            "Fluessigkeit unten, aber kein Eimer vorhanden."
        )

    end


    local oldSlot =
        turtle.getSelectedSlot()


    turtle.select(slot)

    local ok, err =
        turtle.placeDown()


    turtle.select(oldSlot)


    if not ok then

        error(
            "Fluessigkeit unten konnte nicht "
            .. "aufgenommen werden: "
            .. tostring(err)
        )

    end


    return true

end


-- ============================================================
-- VORWAERTS BEWEGEN
--
-- Wenn ein Block im Weg ist, wird er entfernt.
-- ============================================================

local function moveForward()

    while true do

        fuelCheck()


        local ok, err =
            turtle.forward()


        if ok then

            if state.dir == 0 then
                state.x = state.x + 1

            elseif state.dir == 1 then
                state.z = state.z + 1

            elseif state.dir == 2 then
                state.x = state.x - 1

            elseif state.dir == 3 then
                state.z = state.z - 1
            end


            save()

            return true

        end


        local blocked, data =
            turtle.inspect()


        if blocked then

            if isFluid(data) then

                collectFront()

            else

                local dug, digErr =
                    turtle.dig()


                if not dug then

                    error(
                        "Block vorne kann nicht entfernt werden: "
                        .. tostring(digErr)
                    )

                end

            end

        else

            sleep(0.2)

        end

    end

end


-- ============================================================
-- HOCH
-- ============================================================

local function moveUp()

    while true do

        fuelCheck()


        local ok, err =
            turtle.up()


        if ok then

            state.y =
                state.y + 1

            save()

            return true

        end


        local blocked, data =
            turtle.inspectUp()


        if blocked then

            if isFluid(data) then

                collectUp()

            else

                local dug, digErr =
                    turtle.digUp()


                if not dug then

                    error(
                        "Block oben kann nicht entfernt werden: "
                        .. tostring(digErr)
                    )

                end

            end

        else

            sleep(0.2)

        end

    end

end


-- ============================================================
-- RUNTER
-- ============================================================

local function moveDown()

    while true do

        fuelCheck()


        local ok, err =
            turtle.down()


        if ok then

            state.y =
                state.y - 1

            save()

            return true

        end


        local blocked, data =
            turtle.inspectDown()


        if blocked then

            if isFluid(data) then

                collectDown()

            else

                local dug, digErr =
                    turtle.digDown()


                if not dug then

                    error(
                        "Block unten kann nicht entfernt werden: "
                        .. tostring(digErr)
                    )

                end

            end

        else

            sleep(0.2)

        end

    end

end


-- ============================================================
-- FRONTBLOCK ABBauen
-- ============================================================

local function digFront()

    local blocked, data =
        turtle.inspect()


    if not blocked then
        return true
    end


    if isFluid(data) then

        collectFront()

        return true

    end


    local ok, err =
        turtle.dig()


    if not ok then

        error(
            "Frontblock konnte nicht abgebaut werden: "
            .. tostring(err)
        )

    end


    return true

end


-- ============================================================
-- BLOCK OBEN ABBauen
-- ============================================================

local function digUp()

    local blocked, data =
        turtle.inspectUp()


    if not blocked then
        return true
    end


    if isFluid(data) then

        collectUp()

        return true

    end


    local ok, err =
        turtle.digUp()


    if not ok then

        error(
            "Oberer Block konnte nicht abgebaut werden: "
            .. tostring(err)
        )

    end


    return true

end


-- ============================================================
-- ZU KOORDINATE
-- ============================================================

local function goTo(
    targetX,
    targetY,
    targetZ
)

    -- Y.
    while state.y < targetY do
        moveUp()
    end


    while state.y > targetY do
        moveDown()
    end


    -- X.
    if state.x < targetX then

        face(0)

        while state.x < targetX do
            moveForward()
        end

    elseif state.x > targetX then

        face(2)

        while state.x > targetX do
            moveForward()
        end

    end


    -- Z.
    if state.z < targetZ then

        face(1)

        while state.z < targetZ do
            moveForward()
        end

    elseif state.z > targetZ then

        face(3)

        while state.z > targetZ do
            moveForward()
        end

    end

end


-- ============================================================
-- HOME
-- ============================================================

local function goHome()

    goTo(
        0,
        0,
        0
    )


    face(
        START_DIR
    )

end


-- ============================================================
-- KISTE PRUEFEN
--
-- KISTE IST HINTER DER TURTLE.
-- ============================================================

local function checkChest()

    local oldDir =
        state.dir


    face(
        CHEST_DIR
    )


    local ok, data =
        turtle.inspect()


    face(oldDir)


    if not ok then

        error(
            "Hinter der Turtle wurde keine Kiste gefunden."
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

        error(
            "Hinter der Turtle steht keine Kiste."
        )

    end


    return true

end


-- ============================================================
-- INVENTAR ABLADEN
-- ============================================================

local function unload()

    local oldSlot =
        turtle.getSelectedSlot()


    for slot = 1, 16 do

        local item =
            turtle.getItemDetail(slot)


        if item ~= nil then

            if not keepItem(item.name) then

                turtle.select(slot)

                local ok, err =
                    turtle.drop()


                if not ok then

                    error(
                        "Slot "
                        .. tostring(slot)
                        .. " konnte nicht in die Kiste "
                        .. "geleert werden: "
                        .. tostring(err)
                    )

                end

            end

        end

    end


    turtle.select(oldSlot)

end


-- ============================================================
-- SERVICE
--
-- Turtle faehrt zur Kiste, leert das Inventar und
-- kehrt danach exakt zur vorherigen Position zurueck.
-- ============================================================

local function service()

    if servicing then
        return
    end


    servicing = true


    local oldX =
        state.x

    local oldY =
        state.y

    local oldZ =
        state.z

    local oldDir =
        state.dir


    -- Nach Hause.
    goHome()


    -- Zur Kiste.
    face(
        CHEST_DIR
    )


    checkChest()


    unload()


    -- Wieder in die alte Richtung.
    face(
        START_DIR
    )


    -- Alte Position wiederherstellen.
    goTo(
        oldX,
        oldY,
        oldZ
    )


    face(
        oldDir
    )


    servicing = false


    save()

end


-- ============================================================
-- INVENTAR CHECK
-- ============================================================

local function inventoryCheck()

    if freeSlots() >= MIN_FREE_SLOTS then
        return
    end


    service()


    if freeSlots() < MIN_FREE_SLOTS then

        error(
            "Inventar ist voll und konnte nicht "
            .. "ausreichend geleert werden."
        )

    end

end


-- ============================================================
-- FACKEL
--
-- NUR IN LAYER 1.
--
-- Die Fackel wird direkt unter der Turtle platziert.
--
-- KEINE DREHUNG.
-- KEIN BACK().
-- KEIN ZURUECKFAHREN.
--
-- Dadurch kann die Fackellogik den Reihenwechsel
-- nicht mehr kaputtmachen.
-- ============================================================

local function placeTorch()

    if state.layer ~= 1 then
        return
    end


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
        findItem(TORCH_NAME)


    if slot == nil then

        error(
            "Keine Fackeln mehr vorhanden."
        )

    end


    local oldSlot =
        turtle.getSelectedSlot()


    turtle.select(slot)


    -- Pruefen, ob dort unten bereits eine Fackel steht.
    local blocked, data =
        turtle.inspectDown()


    if blocked
    and data ~= nil
    and data.name == TORCH_NAME then

        turtle.select(oldSlot)

        state.torchCounter = 0

        save()

        return

    end


    local placed, err =
        turtle.placeDown()


    turtle.select(oldSlot)


    if not placed then

        error(
            "Fackel konnte nicht gesetzt werden: "
            .. tostring(err)
        )

    end


    state.torchCounter = 0

    save()

end


-- ============================================================
-- EINEN BLOCK / EINE POSITION MINEN
--
-- Reihenfolge:
--
-- 1. Frontblock abbauen
-- 2. oberen Block abbauen
-- 3. in den Block fahren
-- 4. Fackel setzen
--
-- Damit wird auch der LETZTE Block einer Reihe
-- komplett bearbeitet.
-- ============================================================

local function minePosition()

    inventoryCheck()
    fuelCheck()


    -- ========================================================
    -- FRONTBLOCK
    -- ========================================================

    digFront()


    -- ========================================================
    -- OBERER BLOCK
    --
    -- Nur wenn innerhalb der gewuenschten Hoehe.
    -- ========================================================

    if state.y + 1 < state.height then

        digUp()

    end


    -- ========================================================
    -- IN DEN BLOCK FAHREN
    -- ========================================================

    moveForward()


    -- ========================================================
    -- FACKEL
    -- ========================================================

    placeTorch()


    save()

end


-- ============================================================
-- ERSTEN BLOCK DER NEUEN REIHE
--
-- Das ist der entscheidende Teil fuer den alten Fehler.
--
-- Beim Reihenwechsel wird die Turtle seitlich direkt
-- in den ersten Block der neuen Reihe bewegt.
--
-- Danach wird SOFORT der obere Block abgebaut.
--
-- Der erste Block wird ebenfalls als komplette
-- Mining-Position behandelt.
-- ============================================================

local function enterNextRow(row)

    if row % 2 == 1 then

        -- Wir waren in einer ungeraden Reihe
        -- und haben nach +X geschaut.
        --
        -- Neue Reihe liegt +Z.
        turnRight()

        -- Direkt in den ersten Block der neuen Reihe.
        moveForward()

        -- Jetzt schaut die Turtle noch +Z.
        -- Die neue Reihe geht nach -X.
        turnRight()

    else

        -- Wir waren in einer geraden Reihe
        -- und haben nach -X geschaut.
        --
        -- Neue Reihe liegt +Z.
        turnLeft()

        -- Direkt in den ersten Block der neuen Reihe.
        moveForward()

        -- Neue Reihe geht nach +X.
        turnLeft()

    end


    -- ========================================================
    -- WICHTIG:
    --
    -- Die Turtle steht jetzt bereits im ersten Block
    -- der neuen Reihe.
    --
    -- Der obere Block wird HIER explizit abgebaut.
    -- ========================================================

    if state.y + 1 < state.height then

        digUp()

    end


    -- Fackel auf der ersten Position der Reihe.
    placeTorch()


    save()

end


-- ============================================================
-- EINE REIHE
-- ============================================================

local function mineRow(row)

    -- Die Turtle steht vor dem ersten Block,
    -- wenn row == 1.
    --
    -- Bei row > 1 wurde der erste Block bereits durch
    -- enterNextRow() betreten.


    if row == 1 then

        state.col = 1

        save()


        while state.col <= state.width do

            minePosition()


            state.col =
                state.col + 1


            save()


        end

    else

        -- Der erste Block wurde beim Reihenwechsel bereits
        -- betreten und oben bearbeitet.
        --
        -- Deshalb beginnt col bei 2.

        state.col = 2

        save()


        while state.col <= state.width do

            minePosition()


            state.col =
                state.col + 1


            save()

        end

    end

end


-- ============================================================
-- LAYER
--
-- Ein Layer besteht aus maximal 2 Hoehen:
--
-- Layer 1:
--   Y 0 + Y 1
--
-- Layer 2:
--   Y 2 + Y 3
--
-- usw.
-- ============================================================

local function mineLayer(layer)

    state.layer =
        layer


    local targetY =
        (layer - 1) * 2


    -- ========================================================
    -- Zum Start des Layers.
    -- ========================================================

    goHome()


    while state.y < targetY do
        moveUp()
    end


    while state.y > targetY do
        moveDown()
    end


    goTo(
        0,
        targetY,
        0
    )


    face(
        START_DIR
    )


    -- ========================================================
    -- Reihen.
    -- ========================================================

    local row = 1


    while row <= state.depth do

        state.row =
            row


        -- ====================================================
        -- Richtige Richtung der Reihe.
        -- ====================================================

        if row % 2 == 1 then

            face(0)

        else

            face(2)

        end


        -- ====================================================
        -- Reihe abbauen.
        -- ====================================================

        mineRow(row)


        -- ====================================================
        -- Letzte Reihe?
        -- ====================================================

        if row >= state.depth then
            break
        end


        -- ====================================================
        -- Reihenwechsel.
        --
        -- HIER wird der erste Block der neuen Reihe
        -- direkt betreten UND der obere Block abgebaut.
        -- ====================================================

        enterNextRow(row)


        row =
            row + 1


        state.row =
            row


        save()

    end


    -- ========================================================
    -- Layer fertig.
    -- ========================================================

    state.currentLayer =
        layer + 1

    state.row = 1
    state.col = 1

    state.torchCounter = 0


    save()

end


-- ============================================================
-- GESAMTEN AUFTRAG AUSFUEHREN
-- ============================================================

local function runMining()

    local layers =
        math.ceil(
            state.height / 2
        )


    while state.currentLayer <= layers do

        mineLayer(
            state.currentLayer
        )

    end


    -- ========================================================
    -- Fertig -> nach Hause.
    -- ========================================================

    goHome()


    -- Zur Kiste schauen.
    face(
        CHEST_DIR
    )


    checkChest()


    unload()


    -- Wieder normal nach vorne.
    face(
        START_DIR
    )


    print("")
    print("==============================")
    print("       MINING FERTIG")
    print("==============================")
    print("")

end


-- ============================================================
-- STATUS
-- ============================================================

local function showStatus()

    if state == nil then

        print("")
        print("Kein Auftrag vorhanden.")
        print("")

        return

    end


    print("")
    print("==============================")
    print("         MINER V10.2")
    print("==============================")
    print("")

    print(
        "Groesse: "
        .. state.width
        .. " x "
        .. state.depth
        .. " x "
        .. state.height
    )

    print(
        "Layer: "
        .. tostring(state.currentLayer)
    )

    print(
        "Reihe: "
        .. tostring(state.row)
    )

    print(
        "Spalte: "
        .. tostring(state.col)
    )

    print(
        "Position: "
        .. tostring(state.x)
        .. ", "
        .. tostring(state.y)
        .. ", "
        .. tostring(state.z)
    )

    print(
        "Richtung: "
        .. tostring(state.dir)
    )

    print(
        "Fuel: "
        .. tostring(turtle.getFuelLevel())
    )

    print(
        "Fackeln: "
        .. tostring(
            countItem(TORCH_NAME)
        )
    )

    print(
        "Freie Slots: "
        .. tostring(
            freeSlots()
        )
    )

    print("")

end


-- ============================================================
-- RESET
-- ============================================================

local function reset()

    if fs.exists(STATE_FILE) then

        fs.delete(STATE_FILE)

    end


    print("")
    print("V10.2 State geloescht.")
    print("")

end


-- ============================================================
-- NEUER AUFTRAG
-- ============================================================

local function newJob()

    local width =
        tonumber(args[2])

    local depth =
        tonumber(args[3])

    local height =
        tonumber(args[4])

    local torchDistance =
        tonumber(args[5])


    if width == nil
    or depth == nil
    or height == nil then

        usage()

        return

    end


    if width < 1
    or depth < 1
    or height < 1 then

        error(
            "Breite, Tiefe und Hoehe "
            .. "muessen mindestens 1 sein."
        )

    end


    if torchDistance == nil then

        torchDistance = 6

    end


    if torchDistance < 0 then
        torchDistance = 0
    end


    -- ========================================================
    -- Neuer State.
    -- ========================================================

    state = {

        version = VERSION,

        width = width,
        depth = depth,
        height = height,

        torchDistance =
            torchDistance,

        torchCounter = 0,

        x = 0,
        y = 0,
        z = 0,

        dir = START_DIR,

        currentLayer = 1,

        row = 1,
        col = 1

    }


    save()


    print("")
    print("==============================")
    print("        MINER V10.2")
    print("==============================")
    print("")

    print(
        "Groesse: "
        .. width
        .. " x "
        .. depth
        .. " x "
        .. height
    )

    print(
        "Fackelabstand: "
        .. torchDistance
    )

    print("")


    -- ========================================================
    -- Kiste pruefen.
    -- ========================================================

    checkChest()


    -- ========================================================
    -- Fuel.
    -- ========================================================

    fuelCheck()


    -- ========================================================
    -- Fackeln.
    -- ========================================================

    if torchDistance > 0 then

        if countItem(TORCH_NAME) <= 0 then

            error(
                "Fackelabstand ist aktiviert, "
                .. "aber keine Fackeln vorhanden."
            )

        end

    end


    -- ========================================================
    -- Mining starten.
    -- ========================================================

    runMining()

end


-- ============================================================
-- RESUME
-- ============================================================

local function resume()

    state =
        loadState()


    if state == nil then

        print("")
        print("Kein V10.2 Auftrag vorhanden.")
        print("")

        return

    end


    print("")
    print("==============================")
    print("        MINER RESUME")
    print("==============================")
    print("")

    print(
        "Layer: "
        .. tostring(state.currentLayer)
    )

    print(
        "Reihe: "
        .. tostring(state.row)
    )

    print(
        "Spalte: "
        .. tostring(state.col)
    )

    print("")


    fuelCheck()

    runMining()

end


-- ============================================================
-- START
-- ============================================================

if command == "new" then

    newJob()

elseif command == "resume" then

    resume()

elseif command == "status" then

    state =
        loadState()

    showStatus()

elseif command == "reset" then

    reset()

elseif command == nil then

    usage()

else

    usage()

end