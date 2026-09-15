-- ============================================================
--                       MINER V10.3.1
-- ============================================================
--
-- CC:Tweaked Mining Turtle
--
-- Aufbau:
--
--     [ KISTE ][ TURTLE ] ---> MINING
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


local VERSION = 1031
local STATE_FILE = "miner_state_v1031"

local args = {...}
local command = args[1]


-- ============================================================
-- KONFIGURATION
-- ============================================================

-- 0 = +X
-- 1 = +Z
-- 2 = -X
-- 3 = -Z

local START_DIR = 0

-- Die Kiste befindet sich hinter der Turtle.
local CHEST_DIR = 2


local MIN_FUEL = 500
local FUEL_BUFFER = 150
local RETURN_RESERVE = 10

local MAX_TORCHES = 16
local MIN_TORCHES = 4

local MAX_BUCKETS = 4
local MIN_BUCKETS = 2

local MIN_FREE_SLOTS = 2


-- ============================================================
-- STATE
-- ============================================================

local state = nil
local servicing = false

local performService


-- ============================================================
-- HILFE
-- ============================================================

local function usage()

    print("")
    print("==============================")
    print("       MINER V10.3.1")
    print("==============================")
    print("")

    print("Neuer Auftrag:")
    print("")
    print(" miner new <breite> <tiefe> <hoehe> [fackeln]")
    print("")

    print("Beispiel:")
    print("")
    print(" miner new 4 4 2 2")
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
-- HILFSFUNKTIONEN
-- ============================================================

local function abs(n)

    if n < 0 then
        return -n
    end

    return n

end


local function homeDistance()

    if state == nil then
        return 0
    end

    return
        abs(state.x)
        + abs(state.y)
        + abs(state.z)

end


-- ============================================================
-- STATE SPEICHERN
-- ============================================================

local function save()

    if state == nil then
        return
    end


    local file, err =
        fs.open(
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


    local file, err =
        fs.open(
            STATE_FILE,
            "r"
        )


    if file == nil then

        error(
            "State konnte nicht gelesen werden: "
            .. tostring(err)
        )

    end


    local content =
        file.readAll()

    file.close()


    local data =
        textutils.unserialize(
            content
        )


    if data == nil then

        error(
            "miner_state_v1031 ist beschaedigt."
        )

    end


    if data.version ~= VERSION then

        print("")
        print("Ein alter Miner-State wurde gefunden.")
        print("")
        print("Bitte:")
        print("")
        print(" miner reset")
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


        if item ~= nil
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


        if item ~= nil
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


local function findReceivingSlot(name)

    local empty =
        findEmptySlot()


    if empty ~= nil then
        return empty
    end


    for slot = 1, 16 do

        local item =
            turtle.getItemDetail(slot)


        if item ~= nil
        and item.name == name
        and turtle.getItemSpace(slot) > 0 then

            return slot

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


-- ============================================================
-- ITEMS DIE BEHALTEN WERDEN
-- ============================================================

local function isKeepItem(name)

    if name == "minecraft:torch" then
        return true
    end

    if name == "minecraft:bucket" then
        return true
    end

    if name == "minecraft:water_bucket" then
        return true
    end

    if name == "minecraft:lava_bucket" then
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


local function turnAround()

    turnRight()
    turnRight()

end


-- ============================================================
-- FLUESSIGKEIT
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


-- ============================================================
-- EIMER VORNE
-- ============================================================

local function collectFront()

    local slot =
        findItem(
            "minecraft:bucket"
        )


    if slot == nil then
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


-- ============================================================
-- EIMER OBEN
-- ============================================================

local function collectUp()

    local slot =
        findItem(
            "minecraft:bucket"
        )


    if slot == nil then
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


-- ============================================================
-- EIMER UNTEN
-- ============================================================

local function collectDown()

    local slot =
        findItem(
            "minecraft:bucket"
        )


    if slot == nil then
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
-- FUEL
-- ============================================================

local function refuelInventory()

    if turtle.getFuelLevel()
        == "unlimited" then

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


    if turtle.getFuelLevel()
        == "unlimited" then

        return true

    end


    return
        turtle.getFuelLevel()
        >= MIN_FUEL

end


-- ============================================================
-- VORWAERTS
-- ============================================================

local function moveForwardRaw()

    while true do

        if not servicing then

            local fuel =
                turtle.getFuelLevel()


            if fuel ~= "unlimited" then

                local required =
                    homeDistance()
                    + RETURN_RESERVE


                if fuel < required then

                    performService()

                end

            end

        else

            if turtle.getFuelLevel()
                ~= "unlimited"
            and turtle.getFuelLevel() < 1 then

                error(
                    "Fuel waehrend des Service ausgegangen."
                )

            end

        end


        local ok, err =
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


        if blocked then

            if isFluid(data) then

                if not collectFront() then

                    error(
                        "Fluessigkeit vorne, "
                        .. "aber kein leerer Eimer."
                    )

                end


            else

                local dug, digErr =
                    turtle.dig()


                if not dug then

                    error(
                        "Block vorne kann nicht abgebaut werden: "
                        .. tostring(digErr)
                    )

                end

            end


        else

            turtle.attack()

            sleep(0.2)

        end

    end

end


-- ============================================================
-- HOCH
-- ============================================================

local function moveUpRaw()

    while true do

        if not servicing then

            local fuel =
                turtle.getFuelLevel()


            if fuel ~= "unlimited" then

                local required =
                    homeDistance()
                    + RETURN_RESERVE


                if fuel < required then

                    performService()

                end

            end

        else

            if turtle.getFuelLevel()
                ~= "unlimited"
            and turtle.getFuelLevel() < 1 then

                error(
                    "Fuel waehrend des Service ausgegangen."
                )

            end

        end


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


        if blocked then

            if isFluid(data) then

                if not collectUp() then

                    error(
                        "Fluessigkeit ueber der Turtle "
                        .. "und kein Eimer vorhanden."
                    )

                end


            else

                local dug, err =
                    turtle.digUp()


                if not dug then

                    error(
                        "Block ueber der Turtle "
                        .. "kann nicht abgebaut werden: "
                        .. tostring(err)
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

local function moveDownRaw()

    while true do

        if not servicing then

            local fuel =
                turtle.getFuelLevel()


            if fuel ~= "unlimited" then

                local required =
                    homeDistance()
                    + RETURN_RESERVE


                if fuel < required then

                    performService()

                end

            end

        else

            if turtle.getFuelLevel()
                ~= "unlimited"
            and turtle.getFuelLevel() < 1 then

                error(
                    "Fuel waehrend des Service ausgegangen."
                )

            end

        end


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


        if blocked then

            if isFluid(data) then

                if not collectDown() then

                    error(
                        "Fluessigkeit unter der Turtle "
                        .. "und kein Eimer vorhanden."
                    )

                end


            else

                local dug, err =
                    turtle.digDown()


                if not dug then

                    error(
                        "Block unter der Turtle "
                        .. "kann nicht abgebaut werden: "
                        .. tostring(err)
                    )

                end

            end


        else

            sleep(0.2)

        end

    end

end


-- ============================================================
-- BLOCK VORNE ABBauen
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
-- BLOCK OBEN ABBauen
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
            "Block oben kann nicht abgebaut werden: "
            .. tostring(err)
        )

    end


    return true

end


-- ============================================================
-- ZU POSITION
-- ============================================================

local function goTo(
    targetX,
    targetY,
    targetZ
)

    while state.y < targetY do

        moveUpRaw()

    end


    while state.y > targetY do

        moveDownRaw()

    end


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
        START_DIR
    )

end


-- ============================================================
-- KISTE PRUEFEN
--
-- Die Kiste steht hinter der Turtle.
-- ============================================================

local function checkChest()

    local oldDir =
        state.dir


    face(
        CHEST_DIR
    )


    local ok, data =
        turtle.inspect()


    if not ok then

        face(oldDir)


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

        face(oldDir)


        error(
            "Hinter der Turtle steht keine Kiste."
        )

    end


    face(oldDir)


    return true

end


-- ============================================================
-- KISTE VORNE
-- ============================================================

local function assertChestFront()

    local ok, data =
        turtle.inspect()


    if not ok then

        error(
            "Vor der Turtle wurde keine Kiste gefunden."
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
            "Vor der Turtle steht keine Kiste."
        )

    end

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


        if item ~= nil
        and not isKeepItem(item.name) then

            turtle.select(slot)


            local ok, err =
                turtle.drop()


            if not ok then

                error(
                    "Slot "
                    .. tostring(slot)
                    .. " konnte nicht in die Kiste gelegt werden: "
                    .. tostring(err)
                )

            end

        end

    end


    turtle.select(oldSlot)

end


-- ============================================================
-- KISTENINVENTAR
-- ============================================================

local function findChestEmptySlot(
    list,
    size
)

    for slot = 1, size do

        if list[slot] == nil then
            return slot
        end

    end


    return nil

end


local function findChestItem(
    list,
    name
)

    for slot, item in pairs(list) do

        if item ~= nil
        and item.name == name then

            return slot

        end

    end


    return nil

end


-- ============================================================
-- ITEM IM KISTENINVENTAR VERSCHIEBEN
-- ============================================================

local function moveChestStack(
    chest,
    chestName,
    fromSlot,
    toSlot,
    amount
)

    local ok, moved =
        pcall(
            function()

                return chest.pushItems(
                    chestName,
                    fromSlot,
                    amount,
                    toSlot
                )

            end
        )


    if not ok then
        return 0
    end


    if moved == nil then
        return 0
    end


    return moved

end


-- ============================================================
-- ITEM AUS KISTE HOLEN
--
-- Wenn die Kiste als Inventar-Peripherie erreichbar ist,
-- wird das gewuenschte Item in Kistenslot 1 verschoben.
--
-- Danach kann turtle.suck() gezielt dieses Item holen.
-- ============================================================

local function pullNamed(
    name,
    amount
)

    if amount <= 0 then
        return 0
    end


    local oldSlot =
        turtle.getSelectedSlot()


    local received = 0


    local chest =
        peripheral.wrap("front")


    -- ========================================================
    -- Methode 1:
    -- Kiste als Inventar.
    -- ========================================================

    if chest ~= nil
    and chest.list ~= nil
    and chest.size ~= nil
    and chest.pushItems ~= nil then

        local chestName =
            peripheral.getName(chest)


        if chestName ~= nil then

            local attempts = 0


            while received < amount
            and attempts < 128 do

                attempts =
                    attempts + 1


                local list =
                    chest.list()


                local targetSlot =
                    findChestItem(
                        list,
                        name
                    )


                if targetSlot == nil then
                    break
                end


                -- ------------------------------------------------
                -- Das Zielitem ist schon in Slot 1.
                -- ------------------------------------------------

                if targetSlot ~= 1 then

                    -- Slot 1 freimachen.
                    if list[1] ~= nil then

                        local emptySlot =
                            findChestEmptySlot(
                                list,
                                chest.size()
                            )


                        if emptySlot == nil then
                            break
                        end


                        local moved =
                            moveChestStack(
                                chest,
                                chestName,
                                1,
                                emptySlot,
                                list[1].count
                            )


                        if moved <= 0 then
                            break
                        end

                    end


                    -- Liste neu laden.
                    list =
                        chest.list()


                    targetSlot =
                        findChestItem(
                            list,
                            name
                        )


                    if targetSlot == nil then
                        break
                    end


                    local wanted =
                        math.min(
                            amount - received,
                            list[targetSlot].count
                        )


                    local moved =
                        moveChestStack(
                            chest,
                            chestName,
                            targetSlot,
                            1,
                            wanted
                        )


                    if moved <= 0 then
                        break
                    end

                end


                -- ------------------------------------------------
                -- Jetzt liegt das Item in Kistenslot 1.
                -- ------------------------------------------------

                local receiveSlot =
                    findReceivingSlot(name)


                if receiveSlot == nil then
                    break
                end


                turtle.select(
                    receiveSlot
                )


                local before =
                    countItem(name)


                local wanted =
                    math.min(
                        amount - received,
                        64
                    )


                local ok =
                    turtle.suck(
                        wanted
                    )


                if not ok then
                    break
                end


                local after =
                    countItem(name)


                local got =
                    after - before


                if got <= 0 then
                    break
                end


                received =
                    received + got

            end

        end

    end


    -- ========================================================
    -- Methode 2:
    -- Fallback turtle.suck().
    --
    -- Funktioniert auch ohne Inventar-Peripherie, wenn das
    -- gewuenschte Item an der erreichbaren Stelle liegt.
    -- ========================================================

    if received < amount then

        local attempts = 0


        while received < amount
        and attempts < 32 do

            attempts =
                attempts + 1


            local slot =
                findReceivingSlot(name)


            if slot == nil then
                break
            end


            turtle.select(slot)


            local before =
                countItem(name)


            local ok =
                turtle.suck(
                    math.min(
                        amount - received,
                        64
                    )
                )


            if not ok then
                break
            end


            local item =
                turtle.getItemDetail(slot)


            if item == nil then
                break
            end


            if item.name ~= name then

                turtle.drop()


                break

            end


            local after =
                countItem(name)


            local got =
                after - before


            if got <= 0 then
                break
            end


            received =
                received + got

        end

    end


    turtle.select(oldSlot)


    return received

end


-- ============================================================
-- VORRAETE AUS KISTE
-- ============================================================

local function refillSupplies()

    assertChestFront()


    -- ========================================================
    -- FACKELN
    -- ========================================================

    local torches =
        countItem(
            "minecraft:torch"
        )


    if torches < MAX_TORCHES then

        pullNamed(
            "minecraft:torch",
            MAX_TORCHES - torches
        )

    end


    -- ========================================================
    -- EIMER
    -- ========================================================

    local buckets =
        countItem(
            "minecraft:bucket"
        )


    if buckets < MAX_BUCKETS then

        pullNamed(
            "minecraft:bucket",
            MAX_BUCKETS - buckets
        )

    end


    -- ========================================================
    -- FUEL
    -- ========================================================

    if turtle.getFuelLevel()
        ~= "unlimited" then

        if turtle.getFuelLevel()
            < MIN_FUEL + FUEL_BUFFER then

            pullNamed(
                "minecraft:charcoal",
                16
            )


            if turtle.getFuelLevel()
                < MIN_FUEL + FUEL_BUFFER then

                pullNamed(
                    "minecraft:coal",
                    16
                )

            end


            refuelInventory()

        end

    end


    -- ========================================================
    -- PRUEFEN
    -- ========================================================

    if state.torchDistance > 0 then

        if countItem("minecraft:torch")
            < MIN_TORCHES then

            error(
                "Fackelabstand ist aktiviert, "
                .. "aber es sind nicht genug Fackeln vorhanden."
            )

        end

    end


    if countItem("minecraft:bucket")
        < MIN_BUCKETS then

        error(
            "Nicht genug leere Eimer in der Kiste."
        )

    end


    if turtle.getFuelLevel()
        ~= "unlimited" then

        if turtle.getFuelLevel()
            < MIN_FUEL then

            error(
                "Nicht genug Fuel in der Kiste."
            )

        end

    end


    save()

end


-- ============================================================
-- SERVICE
--
-- Turtle:
--
-- 1. nach Hause
-- 2. Kiste
-- 3. Items abladen
-- 4. Fuel/Fackeln/Eimer holen
-- 5. zur alten Position
-- ============================================================

performService = function()

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


    -- ========================================================
    -- HOME
    -- ========================================================

    goHome()


    -- ========================================================
    -- KISTE
    -- ========================================================

    face(
        CHEST_DIR
    )


    assertChestFront()


    -- Abgebautes Material ablegen.
    unload()


    -- Vorräte holen.
    refillSupplies()


    -- ========================================================
    -- GENUG FUEL FUER RUECKWEG?
    -- ========================================================

    if turtle.getFuelLevel()
        ~= "unlimited" then

        local returnDistance =
            abs(oldX)
            + abs(oldY)
            + abs(oldZ)


        if turtle.getFuelLevel()
            < returnDistance + RETURN_RESERVE then

            refuelInventory()

        end


        if turtle.getFuelLevel()
            < returnDistance then

            error(
                "Nicht genug Fuel, um zur "
                .. "Miningposition zurueckzukehren."
            )

        end

    end


    -- ========================================================
    -- ZURUECK
    -- ========================================================

    face(
        START_DIR
    )


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
-- FUEL PRUEFEN
-- ============================================================

local function fuelCheck()

    if turtle.getFuelLevel()
        == "unlimited" then

        return

    end


    local required =
        homeDistance()
        + RETURN_RESERVE


    if turtle.getFuelLevel()
        >= required then

        return

    end


    performService()


    if turtle.getFuelLevel()
        < MIN_FUEL then

        error(
            "Nach dem Service ist immer noch "
            .. "zu wenig Fuel vorhanden."
        )

    end

end


-- ============================================================
-- INVENTAR PRUEFEN
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
            "Inventar ist voll und konnte "
            .. "nicht geleert werden."
        )

    end

end


-- ============================================================
-- FACKEL HINTER DER TURTLE
--
-- WICHTIG:
--
-- Die Fackel wird NICHT mehr mit placeDown() gesetzt.
--
-- Ablauf:
--
--       TURTLE
--          ↓
--     Miningrichtung
--
-- Die Turtle dreht sich 180 Grad:
--
--     Miningrichtung
--          ↑
--       TURTLE
--
-- Danach ist turtle.place() genau auf dem Block,
-- der vorher DIREKT HINTER der Turtle lag.
--
-- Anschließend dreht sie sich wieder zurueck.
--
-- Fackeln werden NUR in Layer 1 gesetzt.
-- ============================================================

local function placeTorchBehind()

    if state.layer ~= 1 then
        return
    end


    if state.torchDistance <= 0 then
        return
    end


    -- --------------------------------------------------------
    -- Hinter der Turtle muss innerhalb des aktuellen
    -- Abbaubereichs liegen.
    -- --------------------------------------------------------

    if state.currentRow % 2 == 1 then

        -- Ungerade Reihe laeuft +X.
        -- Bei Spalte 1 gibt es hinter uns keinen
        -- vorher bearbeiteten Block innerhalb der Reihe.

        if state.currentCol <= 1 then

            state.torchCounter = 0

            save()

            return

        end

    else

        -- Gerade Reihe laeuft -X.
        -- Bei width gibt es hinter uns keinen vorher
        -- bearbeiteten Block innerhalb der Reihe.

        if state.currentCol >= state.width then

            state.torchCounter = 0

            save()

            return

        end

    end


    -- --------------------------------------------------------
    -- Fackel suchen.
    -- --------------------------------------------------------

    local torchSlot =
        findItem(
            "minecraft:torch"
        )


    if torchSlot == nil then

        performService()


        torchSlot =
            findItem(
                "minecraft:torch"
            )

    end


    if torchSlot == nil then

        -- Nicht mehr abstuerzen.
        print("")
        print(
            "WARNUNG: Keine Fackeln mehr vorhanden."
        )
        print("Mining wird fortgesetzt.")
        print("")

        state.torchCounter = 0

        save()

        return

    end


    local oldSlot =
        turtle.getSelectedSlot()


    -- --------------------------------------------------------
    -- 180 Grad drehen.
    -- --------------------------------------------------------

    turnAround()


    -- --------------------------------------------------------
    -- Block direkt hinter der urspruenglichen Position.
    -- --------------------------------------------------------

    local blocked, data =
        turtle.inspect()


    -- --------------------------------------------------------
    -- Wenn dort bereits eine Fackel ist:
    -- nichts tun.
    -- --------------------------------------------------------

    if blocked
    and data ~= nil
    and data.name == "minecraft:torch" then

        turnAround()

        turtle.select(oldSlot)

        state.torchCounter = 0

        save()

        return

    end


    -- --------------------------------------------------------
    -- Wenn dort ein anderer Block ist, keine Fackel erzwingen.
    -- --------------------------------------------------------

    if blocked then

        print(
            "WARNUNG: Hinter der Turtle ist bereits "
            .. "ein Block. Fackel wird dort nicht gesetzt."
        )


        turnAround()

        turtle.select(oldSlot)

        state.torchCounter = 0

        save()

        return

    end


    -- --------------------------------------------------------
    -- Fackel in den Block direkt hinter der Turtle setzen.
    -- NICHT placeDown().
    -- --------------------------------------------------------

    turtle.select(
        torchSlot
    )


    local placed, err =
        turtle.place()


    -- --------------------------------------------------------
    -- Sofort wieder zur normalen Richtung.
    -- --------------------------------------------------------

    turnAround()


    turtle.select(oldSlot)


    if not placed then

        print(
            "WARNUNG: Fackel konnte hinter der Turtle "
            .. "nicht gesetzt werden: "
            .. tostring(err)
        )

        print(
            "Mining wird fortgesetzt."
        )

    end


    state.torchCounter = 0


    save()

end


-- ============================================================
-- FACKEL HANDHABEN
-- ============================================================

local function handleTorch(
    countStep
)

    if state.layer ~= 1 then
        return
    end


    if state.torchDistance <= 0 then
        return
    end


    if countStep then

        state.torchCounter =
            state.torchCounter + 1

    end


    if state.torchCounter
        < state.torchDistance then

        save()

        return

    end


    placeTorchBehind()

end


-- ============================================================
-- NORMALE MINING-POSITION
--
-- 1. Frontblock abbauen
-- 2. oberen Block abbauen
-- 3. in den Block laufen
-- 4. Position speichern
-- 5. Fackel hinter uns setzen
-- ============================================================

local function mineAhead(
    row,
    col
)

    inventoryCheck()
    fuelCheck()


    -- Frontblock.
    digFront()


    -- Oberen Block.
    if state.y + 1
        < state.height then

        digAbove()

    end


    -- In den Block laufen.
    moveForwardRaw()


    state.currentRow =
        row

    state.currentCol =
        col

    state.atCell =
        true

    state.pendingAbove =
        false

    state.pendingTorch =
        true


    save()


    handleTorch(true)


    state.pendingTorch =
        false


    save()

end


-- ============================================================
-- NEUE REIHE
--
-- WICHTIG:
-- Der erste Block der neuen Reihe wird korrekt betreten.
-- Danach wird sein oberer Block SOFORT abgebaut.
-- ============================================================

local function enterNextRow(
    oldRow
)

    inventoryCheck()
    fuelCheck()


    local newRow =
        oldRow + 1


    if oldRow % 2 == 1 then

        -- +X -> +Z
        turnRight()

        moveForwardRaw()

        -- +Z -> -X
        turnRight()


        state.currentRow =
            newRow

        state.currentCol =
            state.width


    else

        -- -X -> +Z
        turnLeft()

        moveForwardRaw()

        -- +Z -> +X
        turnLeft()


        state.currentRow =
            newRow

        state.currentCol =
            1

    end


    state.atCell =
        true

    state.pendingAbove =
        true

    state.pendingTorch =
        false


    save()


    -- ========================================================
    -- WICHTIGER FIX:
    --
    -- Der obere Block des ersten Blocks der neuen Reihe.
    -- ========================================================

    if state.y + 1
        < state.height then

        digAbove()

    end


    state.pendingAbove =
        false

    state.pendingTorch =
        true


    save()


    handleTorch(true)


    state.pendingTorch =
        false


    save()

end


-- ============================================================
-- REIHENRICHTUNG
-- ============================================================

local function rowDirection(row)

    if row % 2 == 1 then
        return 0
    end


    return 2

end


-- ============================================================
-- LAYER
-- ============================================================

local function mineLayer(layer)

    state.layer =
        layer


    local targetY =
        (layer - 1) * 2


    -- ========================================================
    -- Neuer Layer
    -- ========================================================

    if state.currentLayer ~= layer then

        state.currentLayer =
            layer

        state.currentRow =
            1

        state.currentCol =
            1

        state.atCell =
            false

        state.pendingAbove =
            false

        state.pendingTorch =
            false

        state.torchCounter =
            0


        save()


        goTo(
            0,
            targetY,
            0
        )


        face(
            START_DIR
        )

    end


    -- ========================================================
    -- Y korrigieren
    -- ========================================================

    if state.y ~= targetY then

        goTo(
            state.x,
            targetY,
            state.z
        )

    end


    -- ========================================================
    -- Recovery: oberer Block
    -- ========================================================

    if state.pendingAbove then

        if state.y + 1
            < state.height then

            digAbove()

        end


        state.pendingAbove =
            false


        save()

    end


    -- ========================================================
    -- Recovery: Fackel
    -- ========================================================

    if state.pendingTorch then

        handleTorch(false)


        state.pendingTorch =
            false


        save()

    end


    -- ========================================================
    -- Erste Position
    -- ========================================================

    if not state.atCell then

        state.currentRow =
            1

        state.currentCol =
            1


        face(
            rowDirection(1)
        )


        mineAhead(
            1,
            1
        )

    end


    -- ========================================================
    -- Hauptschleife
    -- ========================================================

    while true do

        local row =
            state.currentRow

        local col =
            state.currentCol


        -- ====================================================
        -- Ungerade Reihe -> +X
        -- ====================================================

        if row % 2 == 1 then

            if col < state.width then

                local nextCol =
                    col + 1


                face(
                    rowDirection(row)
                )


                mineAhead(
                    row,
                    nextCol
                )


            else

                -- Reihe fertig.
                if row >= state.depth then
                    break
                end


                enterNextRow(
                    row
                )

            end


        -- ====================================================
        -- Gerade Reihe -> -X
        -- ====================================================

        else

            if col > 1 then

                local nextCol =
                    col - 1


                face(
                    rowDirection(row)
                )


                mineAhead(
                    row,
                    nextCol
                )


            else

                -- Reihe fertig.
                if row >= state.depth then
                    break
                end


                enterNextRow(
                    row
                )

            end

        end

    end


    -- ========================================================
    -- Layer fertig
    -- ========================================================

    state.currentLayer =
        layer + 1

    state.currentRow =
        1

    state.currentCol =
        1

    state.atCell =
        false

    state.pendingAbove =
        false

    state.pendingTorch =
        false

    state.torchCounter =
        0


    save()

end


-- ============================================================
-- GESAMTER AUFTRAG
-- ============================================================

local function runMining()

    local layers =
        math.ceil(
            state.height / 2
        )


    while state.currentLayer
        <= layers do

        mineLayer(
            state.currentLayer
        )

    end


    -- ========================================================
    -- Fertig -> Home
    -- ========================================================

    goHome()


    face(
        CHEST_DIR
    )


    assertChestFront()


    unload()


    face(
        START_DIR
    )


    print("")
    print("==============================")
    print("        MINING FERTIG")
    print("==============================")
    print("")

end


-- ============================================================
-- STATUS
-- ============================================================

local function showStatus()

    if state == nil then

        print("")
        print("Kein aktiver Auftrag.")
        print("")

        return

    end


    print("")
    print("==============================")
    print("       MINER V10.3.1")
    print("==============================")
    print("")


    print(
        "Groesse: "
        .. tostring(state.width)
        .. " x "
        .. tostring(state.depth)
        .. " x "
        .. tostring(state.height)
    )


    print(
        "Layer: "
        .. tostring(state.currentLayer)
    )


    print(
        "Reihe: "
        .. tostring(state.currentRow)
    )


    print(
        "Spalte: "
        .. tostring(state.currentCol)
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
        .. tostring(
            turtle.getFuelLevel()
        )
    )


    print(
        "Fackeln: "
        .. tostring(
            countItem(
                "minecraft:torch"
            )
        )
    )


    print(
        "Eimer: "
        .. tostring(
            countItem(
                "minecraft:bucket"
            )
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

    if fs.exists(
        STATE_FILE
    ) then

        fs.delete(
            STATE_FILE
        )

    end


    -- Alte States ebenfalls entfernen.
    if fs.exists(
        "miner_state"
    ) then

        fs.delete(
            "miner_state"
        )

    end


    if fs.exists(
        "miner_state_v103"
    ) then

        fs.delete(
            "miner_state_v103"
        )

    end


    print("")
    print("Miner State wurde geloescht.")
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
    -- Neuer State
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

        layer = 1,

        currentLayer = 1,
        currentRow = 1,
        currentCol = 1,

        atCell = false,

        pendingAbove = false,
        pendingTorch = false

    }


    save()


    print("")
    print("==============================")
    print("       MINER V10.3.1")
    print("==============================")
    print("")


    print(
        "Groesse: "
        .. tostring(width)
        .. " x "
        .. tostring(depth)
        .. " x "
        .. tostring(height)
    )


    print(
        "Fackelabstand: "
        .. tostring(torchDistance)
    )


    print("")
    print("Pruefe Kiste...")
    print("")


    -- ========================================================
    -- START-SERVICE
    --
    -- Fuel
    -- Fackeln
    -- Eimer
    --
    -- werden vor dem Mining aus der Kiste geholt.
    -- ========================================================

    checkChest()


    performService()


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
        print("Kein gueltiger V10.3.1 Auftrag vorhanden.")
        print("")
        print("Neuen Auftrag starten mit:")
        print("")
        print(" miner new 4 4 2 2")
        print("")

        return

    end


    print("")
    print("==============================")
    print("       MINER RESUME")
    print("==============================")
    print("")


    print(
        "Layer: "
        .. tostring(
            state.currentLayer
        )
    )


    print(
        "Reihe: "
        .. tostring(
            state.currentRow
        )
    )


    print(
        "Spalte: "
        .. tostring(
            state.currentCol
        )
    )


    print("")


    fuelCheck()


    inventoryCheck()


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