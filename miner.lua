-- ============================================================
--                       MINER V10.3
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


local VERSION = 103
local STATE_FILE = "miner_state_v103"

local args = {...}
local command = args[1]


-- ============================================================
-- KONFIGURATION
-- ============================================================

local START_DIR = 0
local CHEST_DIR = 2

-- 0 = +X
-- 1 = +Z
-- 2 = -X
-- 3 = -Z

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

-- Vorwaertsdeklaration wegen Kreis:
-- Bewegung -> Fuel -> Service -> Bewegung
local performService


-- ============================================================
-- HILFE
-- ============================================================

local function usage()

    print("")
    print("==============================")
    print("         MINER V10.3")
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
-- HILFSFUNKTIONEN
-- ============================================================

local function abs(n)

    if n < 0 then
        return -n
    end

    return n

end


local function homeDistance()

    if not state then
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
            "miner_state_v103 ist beschaedigt."
        )

    end


    if data.version ~= VERSION then

        print("")
        print("Ein alter Miner-State wurde gefunden.")
        print("")
        print("Bitte zuerst:")
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
        and item.name == name then

            if turtle.getItemSpace(slot) > 0 then
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
-- FUEL AUS INVENTAR
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

            if item.name == "minecraft:charcoal"
            or item.name == "minecraft:coal" then

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

        -- Bei normalem Mining wird dafuer gesorgt,
        -- dass noch genug Fuel fuer den Rueckweg vorhanden ist.
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

            -- Falls z.B. ein Mob im Weg steht.
            turtle.attack()

            sleep(0.2)

        end

    end

end


-- ============================================================
-- RUECKWAERTS
--
-- Wird nur fuer das Fackelsetzen verwendet.
-- ============================================================

local function moveBackRaw()

    if turtle.getFuelLevel()
        ~= "unlimited"
    and turtle.getFuelLevel() < 1 then

        error(
            "Kein Fuel fuer Rueckwaertsbewegung."
        )

    end


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

        elseif turtle.getFuelLevel()
            ~= "unlimited"
        and turtle.getFuelLevel() < 1 then

            error(
                "Fuel waehrend des Service ausgegangen."
            )

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

        elseif turtle.getFuelLevel()
            ~= "unlimited"
        and turtle.getFuelLevel() < 1 then

            error(
                "Fuel waehrend des Service ausgegangen."
            )

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
-- FRONTBLOCK ABBauen
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
-- ZU EINER POSITION
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
-- Die Kiste befindet sich HINTER der Turtle.
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


    local isChest =
        string.find(
            name,
            "chest",
            1,
            true
        )


    if not isChest then

        face(oldDir)


        error(
            "Hinter der Turtle steht keine Kiste."
        )

    end


    face(oldDir)


    return true

end


-- ============================================================
-- KISTE VORNE PRUEFEN
--
-- Wird verwendet, wenn die Turtle bereits zur Kiste schaut.
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
-- INVENTAR IN KISTE
-- ============================================================

local function unload()

    local oldSlot =
        turtle.getSelectedSlot()


    for slot = 1, 16 do

        local item =
            turtle.getItemDetail(slot)


        if item ~= nil then

            if not isKeepItem(item.name) then

                turtle.select(slot)


                local ok, err =
                    turtle.drop()


                if not ok then

                    error(
                        "Slot "
                        .. tostring(slot)
                        .. " konnte nicht in die "
                        .. "Kiste gelegt werden: "
                        .. tostring(err)
                    )

                end

            end

        end

    end


    turtle.select(oldSlot)

end


-- ============================================================
-- LEEREN KISTENSLOT FINDEN
-- ============================================================

local function findChestEmptySlot(list, size)

    for slot = 1, size do

        if list[slot] == nil then
            return slot
        end

    end


    return nil

end


-- ============================================================
-- ITEM IN KISTE FINDEN
-- ============================================================

local function findChestItem(list, name)

    for slot, item in pairs(list) do

        if item ~= nil
        and item.name == name then

            return slot

        end

    end


    return nil

end


-- ============================================================
-- ITEM AUS KISTE HOLEN
--
-- Primär wird die Inventar-Peripherie der Kiste verwendet.
-- Dadurch kann auch bei gemischter Kiste gezielt nach
-- Fackeln/Fuel/Eimern gesucht werden.
--
-- Falls die Kiste nicht als Inventar-Peripherie verfügbar
-- ist, wird als Fallback turtle.suck() verwendet.
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


    -- ========================================================
    -- Versuch mit Kisten-Peripherie.
    -- ========================================================

    local chest =
        peripheral.wrap("front")


    if chest ~= nil
    and chest.list ~= nil
    and chest.pushItems ~= nil then

        local chestName =
            peripheral.getName(chest)


        if chestName ~= nil then

            local attempts = 0


            while received < amount
            and attempts < 64 do

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
                -- Zielitem muss in Kistenslot 1.
                -- ------------------------------------------------

                if targetSlot ~= 1 then

                    if list[1] ~= nil then

                        local emptySlot =
                            findChestEmptySlot(
                                list,
                                chest.size()
                            )


                        if emptySlot == nil then

                            break

                        end


                        local ok, moved =
                            pcall(
                                function()

                                    return chest.pushItems(
                                        chestName,
                                        1,
                                        list[1].count,
                                        emptySlot
                                    )

                                end
                            )


                        if not ok
                        or moved == nil
                        or moved <= 0 then

                            break

                        end

                    end


                    local freshList =
                        chest.list()


                    local target =
                        freshList[targetSlot]


                    if target == nil
                    or target.name ~= name then

                        break

                    end


                    local wanted =
                        math.min(
                            amount - received,
                            target.count
                        )


                    local ok, moved =
                        pcall(
                            function()

                                return chest.pushItems(
                                    chestName,
                                    targetSlot,
                                    wanted,
                                    1
                                )

                            end
                        )


                    if not ok
                    or moved == nil
                    or moved <= 0 then

                        break

                    end

                end


                -- ------------------------------------------------
                -- Zielitem befindet sich nun in Slot 1.
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


                local sucked =
                    turtle.suck(
                        wanted
                    )


                if not sucked then
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
    -- Fallback ohne Inventar-Peripherie.
    -- ========================================================

    if received < amount then

        local attempts = 0


        while received < amount
        and attempts < 64 do

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

                -- Falsches Item wieder in die Kiste.
                turtle.drop()

            else

                local after =
                    countItem(name)


                local got =
                    after - before


                if got > 0 then

                    received =
                        received + got

                end

            end

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

            -- Erst Charcoal.
            pullNamed(
                "minecraft:charcoal",
                16
            )


            -- Danach Coal.
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
    -- PRUEFUNGEN
    -- ========================================================

    if state.torchDistance > 0 then

        if countItem("minecraft:torch")
            < MIN_TORCHES then

            error(
                "Zu wenige Fackeln in der Kiste. "
                .. "Mindestens "
                .. tostring(MIN_TORCHES)
                .. " werden benoetigt."
            )

        end

    end


    if countItem("minecraft:bucket")
        < MIN_BUCKETS then

        error(
            "Zu wenige leere Eimer in der Kiste. "
            .. "Mindestens "
            .. tostring(MIN_BUCKETS)
            .. " werden benoetigt."
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
-- 1. Nach Hause
-- 2. Zur Kiste drehen
-- 3. Items abladen
-- 4. Fuel/Fackeln/Eimer holen
-- 5. Zur alten Position
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


    -- Neue Vorräte holen.
    refillSupplies()


    -- ========================================================
    -- RUECKWEG
    -- ========================================================

    if turtle.getFuelLevel()
        ~= "unlimited" then

        local returnDistance =
            abs(oldX)
            + abs(oldY)
            + abs(oldZ)


        if turtle.getFuelLevel()
            < returnDistance + RETURN_RESERVE then

            -- Noch einmal Fuel versuchen.
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
-- FACKELN
--
-- NUR LAYER 1.
--
-- Die Fackel wird hinter der Turtle auf den Boden gesetzt.
-- Es wird NICHT gedreht.
--
-- Dadurch kann die Fackellogik die Reihenrichtung
-- nicht mehr veraendern.
-- ============================================================

local function placeTorchNow()

    if state.layer ~= 1 then
        return
    end


    if state.torchDistance <= 0 then
        return
    end


    -- --------------------------------------------------------
    -- Hinter der Turtle muss innerhalb des Abbaubereichs sein.
    --
    -- Ungerade Reihe:
    -- Richtung +X
    -- Start ist col 1
    --
    -- Gerade Reihe:
    -- Richtung -X
    -- Start ist col width
    -- --------------------------------------------------------

    if state.currentRow % 2 == 1 then

        if state.currentCol == 1 then

            state.torchCounter = 0
            save()

            return

        end

    else

        if state.currentCol == state.width then

            state.torchCounter = 0
            save()

            return

        end

    end


    local slot =
        findItem(
            "minecraft:torch"
        )


    if slot == nil then

        performService()


        slot =
            findItem(
                "minecraft:torch"
            )

    end


    if slot == nil then

        error(
            "Keine Fackeln mehr vorhanden."
        )

    end


    local oldSlot =
        turtle.getSelectedSlot()


    -- --------------------------------------------------------
    -- Einen Block zurueck.
    -- --------------------------------------------------------

    moveBackRaw()


    -- --------------------------------------------------------
    -- Falls dort bereits eine Fackel liegt,
    -- keine zweite setzen.
    -- --------------------------------------------------------

    local blocked, data =
        turtle.inspectDown()


    if blocked
    and data ~= nil
    and data.name == "minecraft:torch" then

        -- Zurueck.
        moveForwardRaw()


        turtle.select(oldSlot)


        state.torchCounter = 0

        save()


        return

    end


    turtle.select(slot)


    local placed, err =
        turtle.placeDown()


    turtle.select(oldSlot)


    -- Zurueck zur Arbeitsposition.
    moveForwardRaw()


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


    placeTorchNow()

end


-- ============================================================
-- EINE NORMALE MINING-POSITION
--
-- Frontblock
--   ↓
-- oberer Block
--   ↓
-- Bewegung in den Block
--   ↓
-- Fackel
-- ============================================================

local function mineAhead(
    row,
    col
)

    inventoryCheck()
    fuelCheck()


    -- Frontblock abbauen.
    digFront()


    -- Oberen Block abbauen.
    --
    -- WICHTIG:
    -- state.y + 1 < height
    --
    -- Dadurch wird bei Hoehe 2 der obere Block
    -- ebenfalls abgebaut.
    if state.y + 1
        < state.height then

        digAbove()

    end


    -- In den gerade abgebauten Block.
    moveForwardRaw()


    -- Position jetzt wirklich aktualisieren.
    state.currentRow =
        row

    state.currentCol =
        col

    state.atCell = true

    state.pendingAbove = false
    state.pendingTorch = true


    save()


    -- Fackel setzen.
    handleTorch(true)


    state.pendingTorch = false


    save()

end


-- ============================================================
-- ERSTE POSITION EINER NEUEN REIHE
--
-- DAS IST DER WICHTIGE FIX.
--
-- Die Turtle wechselt seitlich in den ersten Block
-- der neuen Reihe.
--
-- Danach wird:
--
--   1. der obere Block dieses Blocks abgebaut
--   2. die Position gespeichert
--   3. die Fackellogik ausgefuehrt
--
-- Damit wird der obere Block beim Reihenwechsel
-- NICHT mehr uebersprungen.
-- ============================================================

local function enterNextRow(
    oldRow
)

    inventoryCheck()
    fuelCheck()


    local newRow =
        oldRow + 1


    -- ========================================================
    -- Seitlich +Z.
    -- ========================================================

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


    state.atCell = true
    state.pendingAbove = true
    state.pendingTorch = false


    save()


    -- ========================================================
    -- WICHTIG:
    --
    -- Der obere Block des ersten Blocks der neuen Reihe.
    -- ========================================================

    if state.y + 1
        < state.height then

        digAbove()

    end


    state.pendingAbove = false
    state.pendingTorch = true


    save()


    handleTorch(true)


    state.pendingTorch = false


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

        state.atCell = false

        state.pendingAbove = false
        state.pendingTorch = false


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
    -- Falls wir bereits auf einem hoeheren Layer sind,
    -- Position trotzdem korrigieren.
    -- ========================================================

    if state.y ~= targetY then

        goTo(
            state.x,
            targetY,
            state.z
        )

    end


    -- ========================================================
    -- Recovery:
    --
    -- Falls das Programm genau beim Reihenwechsel
    -- beendet wurde.
    -- ========================================================

    if state.pendingAbove then

        if state.y + 1
            < state.height then

            digAbove()

        end


        state.pendingAbove = false
        save()

    end


    if state.pendingTorch then

        handleTorch(false)


        state.pendingTorch = false
        save()

    end


    local row =
        state.currentRow or 1


    local col =
        state.currentCol or 1


    -- ========================================================
    -- Wenn wir noch ausserhalb der ersten Position stehen.
    -- ========================================================

    if not state.atCell then

        row = 1
        col = 1


        state.currentRow = 1
        state.currentCol = 1


        face(
            rowDirection(1)
        )


        mineAhead(
            1,
            1
        )


        row = 1
        col = 1

    end


    -- ========================================================
    -- Hauptschleife.
    --
    -- state.currentRow/currentCol beschreibt immer den
    -- Block, auf dem die Turtle gerade steht.
    -- ========================================================

    while true do

        row =
            state.currentRow

        col =
            state.currentCol


        -- ====================================================
        -- Gibt es in dieser Reihe noch einen weiteren Block?
        -- ====================================================

        if row % 2 == 1 then

            -- Ungerade Reihe: +X
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


                -- Naechste Reihe.
                enterNextRow(row)

            end


        else

            -- Gerade Reihe: -X
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


                -- Naechste Reihe.
                enterNextRow(row)

            end

        end

    end


    -- ========================================================
    -- Layer abgeschlossen.
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
-- GESAMTEN AUFTRAG
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
    -- Fertig -> nach Hause.
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
        print("Kein aktiver Auftrag.")
        print("")

        return

    end


    print("")
    print("==============================")
    print("         MINER V10.3")
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


    -- Alten V10-State ebenfalls entfernen,
    -- damit es keine Verwechslung gibt.
    if fs.exists(
        "miner_state"
    ) then

        fs.delete(
            "miner_state"
        )

    end


    print("")
    print("Miner V10.3 State wurde geloescht.")
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
    print("        MINER V10.3")
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
    print("Hole Vorräte aus der Kiste...")
    print("")


    -- ========================================================
    -- START-SERVICE
    --
    -- Genau hier werden jetzt beim START:
    --
    --   Fuel
    --   Fackeln
    --   Eimer
    --
    -- aus der Kiste geholt.
    -- ========================================================

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
        print("Kein gueltiger V10.3 Auftrag vorhanden.")
        print("")
        print("Neuen Auftrag starten mit:")
        print("")
        print(" miner new 4 4 2 2")
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


    -- Falls beim vorherigen Lauf Fuel knapp wurde,
    -- zuerst Service.
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