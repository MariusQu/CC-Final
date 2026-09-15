-- ============================================================
--                    MINER V11.1
-- ============================================================
--
-- CC:Tweaked Mining Turtle
--
-- Aufbau:
--
--       KISTE
--         |
--       TURTLE ---> MINING
--
-- Die Kiste steht hinter der Turtle.
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


local VERSION = 111
local STATE_FILE = "miner_state_v111"

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

-- Die Kiste steht hinter der Turtle.
local CHEST_DIR = 2


local MIN_FUEL = 500
local RETURN_RESERVE = 20

local MAX_TORCHES = 32
local MIN_TORCHES = 4

local MAX_BUCKETS = 4
local MIN_BUCKETS = 2

local MIN_FREE_SLOTS = 2


-- ============================================================
-- GLOBALER STATE
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
    print("          MINER V11.1")
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

    if not fs.exists(
        STATE_FILE
    ) then

        return nil

    end

    local file, err =
        fs.open(
            STATE_FILE,
            "r"
        )

    if file == nil then

        error(
            "State konnte nicht geladen werden: "
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
            "Der V11.1 State ist beschaedigt."
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
        print("Danach einen neuen Auftrag starten.")
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

            total =
                total + 1

        end

    end

    return total

end


-- ============================================================
-- ITEMS BEHALTEN
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


local function turnAround()

    turnRight()
    turnRight()

end


local function face(direction)

    local difference =
        (direction - state.dir) % 4

    if difference == 1 then

        turnRight()

    elseif difference == 2 then

        turnAround()

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
-- POSITION AKTUALISIEREN
-- ============================================================

local function updateForwardPosition()

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

end


local function updateBackPosition()

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
                    + 1

                if fuel < required then

                    performService()

                end

            end

        else

            if turtle.getFuelLevel()
                ~= "unlimited"
            and turtle.getFuelLevel() < 1 then

                error(
                    "Fuel waehrend Service ausgegangen."
                )

            end

        end

        local ok, err =
            turtle.forward()

        if ok then

            updateForwardPosition()
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
-- ZURUECK
-- ============================================================

local function moveBackRaw()

    if turtle.getFuelLevel()
        ~= "unlimited"
    and turtle.getFuelLevel() < 1 then

        if not servicing then

            performService()

        else

            error(
                "Kein Fuel fuer Rueckwaertsbewegung."
            )

        end

    end

    local ok, err =
        turtle.back()

    if not ok then

        return false, err

    end

    updateBackPosition()
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
                    + 1

                if fuel < required then

                    performService()

                end

            end

        end

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

                if not collectUp() then

                    error(
                        "Fluessigkeit ueber der Turtle "
                        .. "und kein Eimer vorhanden."
                    )

                end

            else

                local dug, digErr =
                    turtle.digUp()

                if not dug then

                    error(
                        "Block ueber der Turtle "
                        .. "kann nicht abgebaut werden: "
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

local function moveDownRaw()

    while true do

        if not servicing then

            local fuel =
                turtle.getFuelLevel()

            if fuel ~= "unlimited" then

                local required =
                    homeDistance()
                    + RETURN_RESERVE
                    + 1

                if fuel < required then

                    performService()

                end

            end

        end

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

                if not collectDown() then

                    error(
                        "Fluessigkeit unter der Turtle "
                        .. "und kein Eimer vorhanden."
                    )

                end

            else

                local dug, digErr =
                    turtle.digDown()

                if not dug then

                    error(
                        "Block unter der Turtle "
                        .. "kann nicht abgebaut werden: "
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
            "Block vorne konnte nicht abgebaut werden: "
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
            "Block oben konnte nicht abgebaut werden: "
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
-- KISTEN-INVENTAR
-- ============================================================

local function getChestPeripheral()

    local chest =
        peripheral.wrap("front")

    if chest == nil then
        return nil
    end

    if type(chest.list) ~= "function" then
        return nil
    end

    if type(chest.pushItems) ~= "function" then
        return nil
    end

    return chest

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


-- ============================================================
-- FALLBACK ITEM AUS KISTE
-- ============================================================

local function pullNamedFallback(
    name,
    amount
)

    local oldSlot =
        turtle.getSelectedSlot()

    local received = 0
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

        local after =
            countItem(name)

        local got =
            after - before

        if got > 0 then

            received =
                received + got

        else

            break

        end

    end

    turtle.select(oldSlot)

    return received

end


-- ============================================================
-- ITEM AUS KISTE HOLEN
-- ============================================================

local function pullNamed(
    name,
    amount
)

    if amount <= 0 then
        return 0
    end

    local chest =
        getChestPeripheral()

    if chest == nil then

        return pullNamedFallback(
            name,
            amount
        )

    end

    local chestName =
        peripheral.getName(chest)

    if chestName == nil then
        return 0
    end

    local oldSlot =
        turtle.getSelectedSlot()

    local received = 0
    local attempts = 0

    while received < amount
    and attempts < 128 do

        attempts =
            attempts + 1

        local list =
            chest.list()

        local sourceSlot =
            findChestItem(
                list,
                name
            )

        if sourceSlot == nil then
            break
        end

        if sourceSlot ~= 1 then

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

            list =
                chest.list()

            sourceSlot =
                findChestItem(
                    list,
                    name
                )

            if sourceSlot == nil then
                break
            end

            local source =
                list[sourceSlot]

            if source == nil then
                break
            end

            local wanted =
                math.min(
                    amount - received,
                    source.count
                )

            local ok, moved =
                pcall(
                    function()

                        return chest.pushItems(
                            chestName,
                            sourceSlot,
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

        local receivingSlot =
            findReceivingSlot(name)

        if receivingSlot == nil then
            break
        end

        turtle.select(
            receivingSlot
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

    turtle.select(oldSlot)

    return received

end


-- ============================================================
-- VORRAETE HOLEN
-- ============================================================

local function refillSupplies()

    assertChestFront()

    -- ========================================================
    -- FACKELN
    -- ========================================================

    local torchCount =
        countItem(
            "minecraft:torch"
        )

    if torchCount < MAX_TORCHES then

        pullNamed(
            "minecraft:torch",
            MAX_TORCHES - torchCount
        )

    end


    -- ========================================================
    -- EIMER
    -- ========================================================

    local bucketCount =
        countItem(
            "minecraft:bucket"
        )

    if bucketCount < MAX_BUCKETS then

        pullNamed(
            "minecraft:bucket",
            MAX_BUCKETS - bucketCount
        )

    end


    -- ========================================================
    -- FUEL
    -- ========================================================

    if turtle.getFuelLevel()
        ~= "unlimited" then

        if turtle.getFuelLevel()
            < MIN_FUEL then

            pullNamed(
                "minecraft:charcoal",
                32
            )

            if turtle.getFuelLevel()
                < MIN_FUEL then

                pullNamed(
                    "minecraft:coal",
                    32
                )

            end

            refuelInventory()

        end

    end


    -- ========================================================
    -- FACKELPRUEFUNG
    -- ========================================================

    if state.torchDistance > 0 then

        if countItem(
            "minecraft:torch"
        ) < MIN_TORCHES then

            error(
                "Fackelabstand ist aktiviert, "
                .. "aber es sind nicht genug Fackeln vorhanden."
            )

        end

    end


    -- ========================================================
    -- EIMERPRUEFUNG
    -- ========================================================

    if countItem(
        "minecraft:bucket"
    ) < MIN_BUCKETS then

        error(
            "Nicht genug leere Eimer in der Kiste."
        )

    end


    -- ========================================================
    -- FUELPRUEFUNG
    -- ========================================================

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
    -- NACH HAUSE
    -- ========================================================

    goHome()


    -- ========================================================
    -- KISTE
    -- ========================================================

    face(
        CHEST_DIR
    )

    assertChestFront()


    -- ========================================================
    -- MATERIAL ABLADEN
    -- ========================================================

    unload()


    -- ========================================================
    -- FUEL / FACKELN / EIMER HOLEN
    -- ========================================================

    refillSupplies()


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
        < required then

        error(
            "Nach dem Service ist nicht genug Fuel "
            .. "fuer die aktuelle Position vorhanden."
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
            "Inventar konnte nicht ausreichend "
            .. "geleert werden."
        )

    end

end


-- ============================================================
-- FACKEL: EINEN VERSUCH AUSFUEHREN
-- ============================================================

local function tryPlaceTorchDown()

    local blocked, data =
        turtle.inspectDown()

    -- Bereits eine Fackel vorhanden.
    if blocked
    and data ~= nil
    and data.name == "minecraft:torch" then

        return true

    end

    -- Ohne Block unter der Turtle kann keine
    -- stehende Fackel auf den Boden gesetzt werden.
    if not blocked then

        state.lastTorchError =
            "Kein Block unter der Turtle."

        return false

    end

    local torchSlot =
        findItem(
            "minecraft:torch"
        )

    if torchSlot == nil then

        state.lastTorchError =
            "Keine Fackel im Inventar."

        return false

    end

    local oldSlot =
        turtle.getSelectedSlot()

    turtle.select(
        torchSlot
    )

    local placed, placeErr =
        turtle.placeDown()

    -- Falls z.B. ein Mob die Platzierung verhindert,
    -- einmal angreifen und erneut versuchen.
    if not placed then

        turtle.attackDown()
        sleep(0.1)

        placed, placeErr =
            turtle.placeDown()

    end

    turtle.select(oldSlot)

    if placed then

        state.lastTorchError = nil

        return true

    end

    state.lastTorchError =
        tostring(placeErr)

    return false

end


-- ============================================================
-- FACKEL HINTER DER TURTLE
--
-- WICHTIG:
--
-- Die Turtle befindet sich nach dem normalen Mining
-- auf der aktuellen Position.
--
-- Soll die Fackel HINTER der Turtle liegen, wird:
--
--       aktuelle Position
--              |
--              v
--           TURTLE
--
-- zuerst ein Block zurueck gefahren:
--
--          FACKEL
--             |
--             v
--           TURTLE
--
-- und dort placeDown() ausgefuehrt.
--
-- Danach faehrt die Turtle wieder vor.
--
-- Die Fackel wird also NICHT unter der eigentlichen
-- Arbeitsposition gesetzt.
-- ============================================================

local function placeTorchBehind()

    if state.layer ~= 1 then
        return true
    end

    if state.torchDistance <= 0 then
        return true
    end

    if state.torchCounter
        < state.torchDistance then

        return true

    end


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

        state.lastTorchError =
            "Keine Fackeln vorhanden."

        print("")
        print("WARNUNG: Keine Fackeln vorhanden.")
        print("Fackel wird beim naechsten Schritt erneut versucht.")
        print("")

        return false

    end


    local oldSlot =
        turtle.getSelectedSlot()


    -- ========================================================
    -- RECOVERY-PHASE 1
    -- ========================================================

    state.pendingTorch = true
    state.torchPhase = 1
    state.torchPlaced = false

    save()


    -- ========================================================
    -- ZUR POSITION HINTER DER TURTLE
    -- ========================================================

    local moved, moveErr =
        moveBackRaw()

    if not moved then

        state.pendingTorch = false
        state.torchPhase = 0
        state.torchPlaced = false

        state.lastTorchError =
            "Konnte nicht zur Fackelposition zurueckfahren: "
            .. tostring(moveErr)

        save()

        turtle.select(oldSlot)

        return false

    end


    -- ========================================================
    -- RECOVERY-PHASE 2
    -- ========================================================

    state.torchPhase = 2
    save()


    -- ========================================================
    -- FACKEL SETZEN
    -- ========================================================

    local placed =
        tryPlaceTorchDown()

    if placed then

        state.torchPlaced = true

    else

        state.torchPlaced = false

        print("")
        print("WARNUNG: Fackel konnte nicht gesetzt werden.")
        print(
            "Grund: "
            .. tostring(state.lastTorchError)
        )
        print("Die Turtle setzt die Fackel spaeter erneut.")
        print("")

    end


    -- ========================================================
    -- RECOVERY-PHASE 3
    -- ========================================================

    state.torchPhase = 3
    save()


    -- ========================================================
    -- ZUR ARBEITSPOSITION ZURUECK
    -- ========================================================

    local returned, returnErr =
        moveForwardRaw()

    if not returned then

        error(
            "Konnte nach Fackelsetzung nicht "
            .. "zur Arbeitsposition zurueckfahren: "
            .. tostring(returnErr)
        )

    end


    -- ========================================================
    -- NUR BEI ERFOLG ZAEHLER ZURUECKSETZEN
    -- ========================================================

    if state.torchPlaced then

        state.torchCounter = 0
        state.lastTorchError = nil

    end


    state.pendingTorch = false
    state.torchPhase = 0

    turtle.select(oldSlot)

    save()

    return state.torchPlaced

end


-- ============================================================
-- FACKEL-RECOVERY
-- ============================================================

local function recoverTorch()

    if not state.pendingTorch then
        return
    end


    -- ========================================================
    -- PHASE 1
    --
    -- Noch nicht zur Fackelposition zurueck.
    -- ========================================================

    if state.torchPhase == 1 then

        local moved, moveErr =
            moveBackRaw()

        if not moved then

            state.pendingTorch = false
            state.torchPhase = 0
            state.torchPlaced = false

            state.lastTorchError =
                "Recovery konnte nicht zur Fackelposition fahren: "
                .. tostring(moveErr)

            save()

            return

        end

        state.torchPhase = 2
        save()

    end


    -- ========================================================
    -- PHASE 2
    --
    -- Turtle steht jetzt einen Block hinter der
    -- eigentlichen Arbeitsposition.
    -- ========================================================

    if state.torchPhase == 2 then

        local placed =
            tryPlaceTorchDown()

        if placed then

            state.torchPlaced = true

        else

            state.torchPlaced = false

        end

        state.torchPhase = 3
        save()

    end


    -- ========================================================
    -- PHASE 3
    --
    -- Wieder zur Arbeitsposition.
    -- ========================================================

    if state.torchPhase == 3 then

        local returned, returnErr =
            moveForwardRaw()

        if not returned then

            error(
                "Fackel-Recovery konnte nicht "
                .. "zur Arbeitsposition zurueckkehren: "
                .. tostring(returnErr)
            )

        end

        if state.torchPlaced then

            state.torchCounter = 0
            state.lastTorchError = nil

        end

        state.pendingTorch = false
        state.torchPhase = 0

        save()

    end

end


-- ============================================================
-- FACKELZAEHLER
--
-- Die erste Mining-Position wird nur registriert.
--
-- Danach zaehlt jeder weitere betretene Block.
--
-- Beispiel Abstand 6:
--
-- Position 1 -> Zaehler 0
-- Position 2 -> Zaehler 1
-- Position 3 -> Zaehler 2
-- Position 4 -> Zaehler 3
-- Position 5 -> Zaehler 4
-- Position 6 -> Zaehler 5
-- Position 7 -> Zaehler 6
--
-- Dann wird die Fackel HINTER der Turtle auf Position 6
-- gesetzt.
--
-- Damit stimmen die Abstaende entlang des gesamten
-- Serpentinenweges auch beim Reihenwechsel.
-- ============================================================

local function handleTorch()

    if state.layer ~= 1 then
        return
    end

    if state.torchDistance <= 0 then
        return
    end


    if not state.hasVisitedCell then

        state.hasVisitedCell = true
        state.torchCounter = 0

        save()

        return

    end


    state.torchCounter =
        state.torchCounter + 1

    save()


    if state.torchCounter
        < state.torchDistance then

        return

    end


    placeTorchBehind()

end


-- ============================================================
-- NORMALER MINING-SCHRITT
--
-- WICHTIGER V11-FIX:
--
-- 1. Block vorne abbauen
-- 2. Vorfahren
-- 3. Position speichern
-- 4. Block oben abbauen
-- 5. Fackel behandeln
--
-- Dadurch wird auch der obere Block der letzten
-- Position einer Reihe korrekt abgebaut.
-- ============================================================

local function mineAhead(
    row,
    col
)

    inventoryCheck()
    fuelCheck()


    -- ========================================================
    -- 1. VORNE ABBauen
    -- ========================================================

    digFront()


    -- ========================================================
    -- 2. VORFAHREN
    -- ========================================================

    moveForwardRaw()


    -- ========================================================
    -- 3. POSITION
    -- ========================================================

    state.currentRow =
        row

    state.currentCol =
        col

    state.atCell =
        true

    save()


    -- ========================================================
    -- 4. OBEN ABBauen
    -- ========================================================

    state.pendingAbove =
        true

    save()

    if state.y + 1
        < state.height then

        digAbove()

    end

    state.pendingAbove =
        false

    save()


    -- ========================================================
    -- 5. FACKEL
    -- ========================================================

    handleTorch()

end


-- ============================================================
-- NEUE REIHE
-- ============================================================

local function enterNextRow(
    oldRow
)

    inventoryCheck()
    fuelCheck()

    local newRow =
        oldRow + 1


    -- ========================================================
    -- UNGERADE REIHE
    --
    -- +X
    -- rechts -> +Z
    -- vor
    -- rechts -> -X
    -- ========================================================

    if oldRow % 2 == 1 then

        turnRight()

        moveForwardRaw()

        state.currentRow =
            newRow

        state.currentCol =
            state.width

        save()

        turnRight()


    else

        -- ====================================================
        -- GERADE REIHE
        --
        -- -X
        -- links -> +Z
        -- vor
        -- links -> +X
        -- ====================================================

        turnLeft()

        moveForwardRaw()

        state.currentRow =
            newRow

        state.currentCol =
            1

        save()

        turnLeft()

    end


    state.atCell =
        true

    save()


    -- ========================================================
    -- OBEN AUF DER ERSTEN POSITION DER NEUEN REIHE
    -- ========================================================

    state.pendingAbove =
        true

    save()

    if state.y + 1
        < state.height then

        digAbove()

    end

    state.pendingAbove =
        false

    save()


    -- ========================================================
    -- FACKEL
    --
    -- WICHTIG:
    --
    -- Auch der Reihenwechsel zaehlt als betretene Position.
    --
    -- Dadurch funktioniert die Fackellogik auch genau
    -- am Ende / Anfang einer Reihe.
    -- ========================================================

    handleTorch()

end


-- ============================================================
-- RECOVERY OBERER BLOCK
-- ============================================================

local function recoverAbove()

    if not state.pendingAbove then
        return
    end

    if state.y + 1
        < state.height then

        digAbove()

    end

    state.pendingAbove =
        false

    save()

end


-- ============================================================
-- RICHTUNG EINER REIHE
-- ============================================================

local function rowDirection(row)

    if row % 2 == 1 then
        return 0
    end

    return 2

end


-- ============================================================
-- EIN LAYER
-- ============================================================

local function mineLayer(
    layer
)

    local targetY =
        (layer - 1) * 2


    -- ========================================================
    -- NEUER LAYER
    --
    -- state.layer zeigt auf den zuletzt gestarteten Layer.
    --
    -- Wenn layer anders ist, muss die Turtle zum Start
    -- dieses Layers gebracht werden.
    -- ========================================================

    if state.layer ~= layer then

        state.layer =
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

        state.torchPhase =
            0

        state.torchPlaced =
            false

        state.torchCounter =
            0

        state.hasVisitedCell =
            false

        state.lastTorchError =
            nil

        save()


        -- ====================================================
        -- ZUM STARTPUNKT DES LAYERS
        -- ====================================================

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
    -- Y KORRIGIEREN
    -- ========================================================

    if state.y ~= targetY then

        goTo(
            state.x,
            targetY,
            state.z
        )

    end


    -- ========================================================
    -- RECOVERY
    -- ========================================================

    recoverAbove()
    recoverTorch()


    -- ========================================================
    -- ERSTE POSITION
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
    -- HAUPTSCHLEIFE
    -- ========================================================

    while true do

        local row =
            state.currentRow

        local col =
            state.currentCol


        -- ====================================================
        -- UNGERADE REIHE -> +X
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
        -- GERADE REIHE -> -X
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
    -- LAYER FERTIG
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

    state.torchPhase =
        0

    state.torchPlaced =
        false

    state.torchCounter =
        0

    state.hasVisitedCell =
        false

    state.lastTorchError =
        nil

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
    -- FERTIG
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
    print("         MINING FERTIG")
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
    print("          MINER V11.1")
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
        "Naechster Layer: "
        .. tostring(state.currentLayer)
    )


    print(
        "Layer zuletzt: "
        .. tostring(state.layer)
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


    print(
        "Fackelabstand: "
        .. tostring(
            state.torchDistance
        )
    )


    print(
        "Fackelzaehler: "
        .. tostring(
            state.torchCounter
        )
    )


    if state.lastTorchError ~= nil then

        print(
            "Letzter Fackelfehler: "
            .. tostring(
                state.lastTorchError
            )
        )

    end


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

    local oldStates = {
        "miner_state",
        "miner_state_v103",
        "miner_state_v1031",
        "miner_state_v110"
    }


    for _, filename in ipairs(oldStates) do

        if fs.exists(filename) then
            fs.delete(filename)
        end

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

        torchDistance =
            6

    end


    if torchDistance < 0 then

        torchDistance =
            0

    end


    -- ========================================================
    -- NEUER STATE
    -- ========================================================

    state = {

        version = VERSION,

        width = width,
        depth = depth,
        height = height,

        torchDistance =
            torchDistance,

        torchCounter =
            0,

        hasVisitedCell =
            false,

        pendingTorch =
            false,

        torchPhase =
            0,

        torchPlaced =
            false,

        lastTorchError =
            nil,

        x = 0,
        y = 0,
        z = 0,

        dir = START_DIR,

        layer = 1,
        currentLayer = 1,

        currentRow = 1,
        currentCol = 1,

        atCell = false,

        pendingAbove = false

    }


    save()


    print("")
    print("==============================")
    print("          MINER V11.1")
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

    print(
        "Hole Fuel, Fackeln und Eimer..."
    )

    print("")


    -- ========================================================
    -- START-SERVICE
    --
    -- Fuel, Fackeln und Eimer werden hier aus der Kiste
    -- geholt.
    -- ========================================================

    checkChest()

    performService()


    -- ========================================================
    -- MINING STARTEN
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
        print("Kein gueltiger V11.1 Auftrag vorhanden.")
        print("")
        print("Neuen Auftrag starten mit:")
        print("")
        print(" miner new 4 4 2 6")
        print("")

        return

    end


    -- ========================================================
    -- FEHLENDE FELDER VON RECOVERY ABSICHERN
    -- ========================================================

    if state.hasVisitedCell == nil then
        state.hasVisitedCell = false
    end

    if state.pendingTorch == nil then
        state.pendingTorch = false
    end

    if state.torchPhase == nil then
        state.torchPhase = 0
    end

    if state.torchPlaced == nil then
        state.torchPlaced = false
    end

    if state.lastTorchError == nil then
        state.lastTorchError = nil
    end

    save()


    print("")
    print("==============================")
    print("          MINER RESUME")
    print("==============================")
    print("")


    print(
        "Naechster Layer: "
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


    -- ========================================================
    -- OBEREN BLOCK RECOVERY
    -- ========================================================

    recoverAbove()


    -- ========================================================
    -- FACKEL RECOVERY
    -- ========================================================

    recoverTorch()


    -- ========================================================
    -- MINING FORTSETZEN
    -- ========================================================

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