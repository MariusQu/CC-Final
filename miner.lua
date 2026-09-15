-- ============================================================
--                       MINER V10.1
-- ============================================================
--
-- CC:Tweaked
--
-- Aufbau:
--
--       KISTE
--        ↑
--        │
--      TURTLE  --->  MINING
--
-- Die Kiste steht HINTER der Turtle.
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


local VERSION = 101
local STATE_FILE = "miner_state_v101"


local args = {...}
local command = args[1]


-- ============================================================
-- KONFIGURATION
-- ============================================================

local MIN_FUEL = 200
local MIN_FREE_SLOTS = 2

local MAX_TORCHES = 32
local MAX_BUCKETS = 4

local CHEST_DIRECTION = 2
local START_DIRECTION = 0


-- ============================================================
-- RICHTUNGEN
--
-- 0 = +X
-- 1 = +Z
-- 2 = -X
-- 3 = -Z
-- ============================================================

local state = nil
local servicing = false


-- ============================================================
-- AUSGABE
-- ============================================================

local function usage()

    print("")
    print("==============================")
    print("         MINER V10.1")
    print("==============================")
    print("")

    print("Neuer Auftrag:")
    print("")
    print(" miner new <breite> <tiefe> <hoehe> [fackeln]")
    print("")

    print("Beispiel:")
    print("")
    print(" miner new 10 20 6 6")
    print("")

    print("Fortsetzen:")
    print("")
    print(" miner resume")
    print("")

    print("Status:")
    print("")
    print(" miner status")
    print("")

    print("Reset:")
    print("")
    print(" miner reset")
    print("")

end


-- ============================================================
-- STATE SPEICHERN
-- ============================================================

local function save()

    if not state then
        return
    end

    local file, err =
        fs.open(
            STATE_FILE,
            "w"
        )

    if not file then

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

    local file, err =
        fs.open(
            STATE_FILE,
            "r"
        )

    if not file then

        error(
            "State konnte nicht gelesen werden: "
            .. tostring(err)
        )

    end

    local data =
        textutils.unserialize(
            file.readAll()
        )

    file.close()


    if not data then

        error(
            "miner_state_v101 ist beschaedigt."
        )

    end


    if data.version ~= VERSION then

        print("")
        print(
            "Alter State gefunden."
        )
        print("")
        print(
            "Bitte zuerst:"
        )
        print("")
        print(
            " miner reset"
        )
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


local function findEmptySlot()

    for slot = 1, 16 do

        if turtle.getItemCount(slot) == 0 then
            return slot
        end

    end

    return nil

end


local function freeSlots()

    local total = 0

    for slot = 1, 16 do

        if turtle.getItemCount(slot) == 0 then

            total =
                total + 1

        end

    end

    return total

end


local function isKeepItem(name)

    if name == "minecraft:torch" then
        return true
    end

    if name == "minecraft:bucket" then
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
-- ============================================================

local function turnRight()

    local ok, err =
        turtle.turnRight()

    if not ok then
        error(
            "Drehen nach rechts fehlgeschlagen: "
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
            "Drehen nach links fehlgeschlagen: "
            .. tostring(err)
        )
    end

    state.dir =
        (state.dir + 3) % 4

    save()

end


local function face(direction)

    local difference =
        (direction - state.dir) % 4


    if difference == 1 then

        turnRight()

    elseif difference == 2 then

        turnRight()
        turnRight()

    elseif difference == 3 then

        turnLeft()

    end

end


-- ============================================================
-- FUEL
-- ============================================================

local function refuelInventory()

    if turtle.getFuelLevel() == "unlimited" then
        return true
    end


    local oldSlot =
        turtle.getSelectedSlot()


    for slot = 1, 16 do

        local item =
            turtle.getItemDetail(slot)

        if item then

            if item.name == "minecraft:coal"
            or item.name == "minecraft:charcoal" then

                turtle.select(slot)

                turtle.refuel()

            end

        end

    end


    turtle.select(oldSlot)


    return
        turtle.getFuelLevel()
        >= MIN_FUEL

end


local function fuelCheck()

    if turtle.getFuelLevel()
        == "unlimited" then

        return

    end


    if turtle.getFuelLevel()
        >= MIN_FUEL then

        return

    end


    refuelInventory()


    if turtle.getFuelLevel()
        < MIN_FUEL then

        error(
            "Zu wenig Fuel. "
            .. "Bitte Kohle/Charcoal nachfuellen."
        )

    end

end


-- ============================================================
-- FLUESSIGKEIT
-- ============================================================

local function isFluid(data)

    if not data then
        return false
    end

    if not data.name then
        return false
    end

    return
        data.name == "minecraft:water"
        or
        data.name == "minecraft:lava"

end


local function collectFront()

    local slot =
        findItem(
            "minecraft:bucket"
        )

    if not slot then
        return false
    end


    local oldSlot =
        turtle.getSelectedSlot()


    turtle.select(slot)

    local ok =
        turtle.place()


    turtle.select(oldSlot)


    return ok

end


local function collectUp()

    local slot =
        findItem(
            "minecraft:bucket"
        )

    if not slot then
        return false
    end


    local oldSlot =
        turtle.getSelectedSlot()


    turtle.select(slot)

    local ok =
        turtle.placeUp()


    turtle.select(oldSlot)


    return ok

end


local function collectDown()

    local slot =
        findItem(
            "minecraft:bucket"
        )

    if not slot then
        return false
    end


    local oldSlot =
        turtle.getSelectedSlot()


    turtle.select(slot)

    local ok =
        turtle.placeDown()


    turtle.select(oldSlot)


    return ok

end


-- ============================================================
-- VORWAERTS
-- ============================================================

local function moveForwardRaw()

    while true do

        fuelCheck()


        local ok =
            turtle.forward()


        if ok then

            if state.dir == 0 then

                state.x =
                    state.x + 1

            elseif state.dir == 1 then

                state.z =
                    state.z + 1

            elseif state.dir == 2 then

                state.x =
                    state.x - 1

            else

                state.z =
                    state.z - 1

            end


            save()

            return true

        end


        local blocked, data =
            turtle.inspect()


        if blocked
        and isFluid(data) then

            local collected =
                collectFront()

            if not collected then

                error(
                    "Fluessigkeit vorne, "
                    .. "aber kein leerer Eimer vorhanden."
                )

            end

        elseif blocked then

            local dug, err =
                turtle.dig()


            if not dug then

                error(
                    "Block vorne kann nicht abgebaut werden: "
                    .. tostring(err)
                )

            end

        else

            sleep(0.2)

        end

    end

end


-- ============================================================
-- RUECKWAERTS
-- ============================================================

local function moveBackRaw()

    fuelCheck()


    local ok, err =
        turtle.back()


    if not ok then

        error(
            "Rueckwaertsbewegung fehlgeschlagen: "
            .. tostring(err)
        )

    end


    if state.dir == 0 then

        state.x =
            state.x - 1

    elseif state.dir == 1 then

        state.z =
            state.z - 1

    elseif state.dir == 2 then

        state.x =
            state.x + 1

    else

        state.z =
            state.z + 1

    end


    save()


    return true

end


-- ============================================================
-- HOCH
-- ============================================================

local function moveUpRaw()

    while true do

        fuelCheck()


        local ok =
            turtle.up()


        if ok then

            state.y =
                state.y + 1

            save()

            return true

        end


        local blocked, data =
            turtle.inspectUp()


        if blocked
        and isFluid(data) then

            if not collectUp() then

                error(
                    "Fluessigkeit ueber der Turtle."
                )

            end

        elseif blocked then

            local dug, err =
                turtle.digUp()


            if not dug then

                error(
                    "Block ueber der Turtle kann "
                    .. "nicht abgebaut werden: "
                    .. tostring(err)
                )

            end

        else

            sleep(0.2)

        end

    end

end


-- ============================================================
-- RUNTER
-- ============================================================

local function moveDownRaw()

    while true do

        fuelCheck()


        local ok =
            turtle.down()


        if ok then

            state.y =
                state.y - 1

            save()

            return true

        end


        local blocked, data =
            turtle.inspectDown()


        if blocked
        and isFluid(data) then

            if not collectDown() then

                error(
                    "Fluessigkeit unter der Turtle."
                )

            end

        elseif blocked then

            local dug, err =
                turtle.digDown()


            if not dug then

                error(
                    "Block unter der Turtle kann "
                    .. "nicht abgebaut werden: "
                    .. tostring(err)
                )

            end

        else

            sleep(0.2)

        end

    end

end


-- ============================================================
-- BLOCK VORNE
-- ============================================================

local function digFront()

    local blocked, data =
        turtle.inspect()


    if not blocked then
        return true
    end


    if isFluid(data) then

        if not collectFront() then

            error(
                "Fluessigkeit vorne und kein Eimer."
            )

        end

        return true

    end


    local ok, err =
        turtle.dig()


    if not ok then

        error(
            "Block vorne kann nicht abgebaut werden: "
            .. tostring(err)
        )

    end


    return true

end


-- ============================================================
-- BLOCK OBEN
-- ============================================================

local function digAbove()

    local blocked, data =
        turtle.inspectUp()


    if not blocked then
        return true
    end


    if isFluid(data) then

        if not collectUp() then

            error(
                "Fluessigkeit ueber der Turtle "
                .. "und kein Eimer."
            )

        end

        return true

    end


    local ok, err =
        turtle.digUp()


    if not ok then

        error(
            "Block ueber der Turtle kann "
            .. "nicht abgebaut werden: "
            .. tostring(err)
        )

    end


    return true

end


-- ============================================================
-- ZIELPOSITION
-- ============================================================

local function goTo(
    targetX,
    targetY,
    targetZ
)

    -- Hoehe zuerst.
    while state.y < targetY do
        moveUpRaw()
    end

    while state.y > targetY do
        moveDownRaw()
    end


    -- X.
    if state.x < targetX then

        face(0)

        while state.x < targetX do
            moveForwardRaw()
        end

    elseif state.x > targetX then

        face(2)

        while state.x > targetX do
            moveForwardRaw()
        end

    end


    -- Z.
    if state.z < targetZ then

        face(1)

        while state.z < targetZ do
            moveForwardRaw()
        end

    elseif state.z > targetZ then

        face(3)

        while state.z > targetZ do
            moveForwardRaw()
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
        START_DIRECTION
    )

end


-- ============================================================
-- KISTE PRUEFEN
--
-- Die Kiste steht HINTER der Turtle.
-- ============================================================

local function checkChest()

    local oldDir =
        state.dir


    face(
        CHEST_DIRECTION
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
--
-- Turtle MUSS dabei zur Kiste schauen.
-- ============================================================

local function unload()

    local oldSlot =
        turtle.getSelectedSlot()


    for slot = 1, 16 do

        local item =
            turtle.getItemDetail(slot)


        if item
        and not isKeepItem(item.name) then

            turtle.select(slot)


            local ok =
                turtle.drop()


            if not ok then

                error(
                    "Item konnte nicht in die Kiste "
                    .. "gelegt werden. Slot "
                    .. tostring(slot)
                )

            end

        end

    end


    turtle.select(oldSlot)

end


-- ============================================================
-- SERVICE
--
-- Der Service leert das Inventar.
-- Fuel/Fackeln/Eimer werden NICHT blind aus der Kiste
-- gezogen, weil turtle.suck keinen bestimmten Kisten-Slot
-- angeben kann.
-- ============================================================

local function performService()

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


    -- Zur Startposition.
    goHome()


    -- Zur Kiste schauen.
    face(
        CHEST_DIRECTION
    )


    checkChest()


    unload()


    -- Wieder zur Miningposition.
    goTo(
        oldX,
        oldY,
        oldZ
    )


    face(oldDir)


    servicing = false


    save()

end


-- ============================================================
-- INVENTAR CHECK
-- ============================================================

local function inventoryCheck()

    if freeSlots()
        >= MIN_FREE_SLOTS then

        return

    end


    performService()


    if freeSlots()
        < MIN_FREE_SLOTS then

        error(
            "Inventar ist voll. "
            .. "Service konnte keinen Platz schaffen."
        )

    end

end


-- ============================================================
-- FACKELN
--
-- NUR LAYER 1.
--
-- Die Fackel wird wirklich HINTER der Turtle gesetzt.
--
-- Ablauf:
--
--   aktuelle Position
--        ↓
--   turtle.back()
--        ↓
--   placeDown()
--        ↓
--   turtle.forward()
--
-- Keine Drehung notwendig.
--
-- Dadurch kann die Richtungs-/Reihenlogik nicht mehr
-- durch die Fackelfunktion kaputtgehen.
-- ============================================================

local function torchBehind(
    firstPositionOfRow
)

    -- Keine Fackeln in Layer 2+.
    if state.layer ~= 1 then
        return
    end


    if state.torchDistance <= 0 then
        return
    end


    state.torchCounter =
        state.torchCounter + 1


    -- Hinter der ersten Position einer Reihe
    -- befindet sich ausserhalb des Abbaubereichs.
    if firstPositionOfRow then

        state.torchCounter = 0

        save()

        return

    end


    if state.torchCounter
        < state.torchDistance then

        save()

        return

    end


    local slot =
        findItem(
            "minecraft:torch"
        )


    if not slot then

        error(
            "Keine Fackeln vorhanden. "
            .. "Bitte Fackeln in die Turtle legen."
        )

    end


    local oldSlot =
        turtle.getSelectedSlot()


    -- Einen Block zurueck.
    moveBackRaw()


    turtle.select(slot)


    local placed, err =
        turtle.placeDown()


    -- Sofort wieder zur aktuellen Arbeitsposition.
    local returned, returnErr =
        turtle.forward()


    turtle.select(oldSlot)


    if not returned then

        error(
            "Nach dem Fackelsetzen konnte die "
            .. "Arbeitsposition nicht wieder erreicht werden: "
            .. tostring(returnErr)
        )

    end


    if not placed then

        error(
            "Fackel konnte nicht gesetzt werden: "
            .. tostring(err)
        )

   