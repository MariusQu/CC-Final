-- ============================================================
--              MINER V8 -> V9 UPDATE
-- ============================================================
--
-- Erstellt aus der vorhandenen miner.lua eine miner_v9.lua.
--
-- Änderungen:
--   - Fackeln weiterhin NUR in Layer 1
--   - turtle.placeDown() wird geprüft
--   - Fackelbewegung nutzt turtle.back()
--   - Kein Vorwärtsfahren nach dem letzten Block einer Reihe
--   - Oberer Block wird auch am letzten Block der Reihe abgebaut
--   - Rest der V8 bleibt unverändert
--
-- ============================================================

local INPUT  = "miner.lua"
local OUTPUT = "miner_v9.lua"
local BACKUP = "miner_v8_backup.lua"


-- ============================================================
-- DATEI LESEN
-- ============================================================

local function readFile(path)

    if not fs.exists(path) then
        error(
            "Datei nicht gefunden: "
            .. path
        )
    end

    local file, err =
        fs.open(path, "r")

    if not file then
        error(
            "Kann Datei nicht lesen: "
            .. tostring(err)
        )
    end

    local content =
        file.readAll()

    file.close()

    return content

end


-- ============================================================
-- DATEI SCHREIBEN
-- ============================================================

local function writeFile(path, content)

    local file, err =
        fs.open(path, "w")

    if not file then
        error(
            "Kann Datei nicht schreiben: "
            .. tostring(err)
        )
    end

    file.write(content)
    file.close()

end


-- ============================================================
-- ABSCHNITT ERSETZEN
-- ============================================================

local function replaceSection(
    source,
    startMarker,
    endMarker,
    replacement
)

    local startPos =
        string.find(
            source,
            startMarker,
            1,
            true
        )

    if not startPos then

        error(
            "Start des Abschnitts nicht gefunden:\n"
            .. startMarker
        )

    end


    local endPos =
        string.find(
            source,
            endMarker,
            startPos,
            true
        )

    if not endPos then

        error(
            "Ende des Abschnitts nicht gefunden:\n"
            .. endMarker
        )

    end


    return
        string.sub(
            source,
            1,
            startPos - 1
        )
        .. replacement
        .. string.sub(
            source,
            endPos
        )

end


-- ============================================================
-- V8 LADEN
-- ============================================================

print("")
print("==============================")
print("      MINER V8 -> V9")
print("==============================")
print("")

local source =
    readFile(INPUT)


-- ============================================================
-- SICHERHEITSPRUEFUNG
-- ============================================================

if not string.find(
    source,
    "local VERSION = 8",
    1,
    true
) then

    error(
        "Die Datei sieht nicht wie die erwartete MINER V8 aus."
    )

end


-- ============================================================
-- VERSION
--
-- Die State-Version bleibt bewusst 8.
--
-- Dadurch kann ein vorhandener State grundsaetzlich
-- weiterhin gelesen werden.
-- ============================================================

source =
    source:gsub(
        "MINER V8",
        "MINER V9"
    )


-- ============================================================
-- TORCH BEHIND
-- ============================================================

local newTorchBehind = [=[local function torchBehind()

    -- ========================================================
    -- Fackeln NUR in Layer 1.
    -- ========================================================

    if state.layer ~= 1 then
        return
    end


    if state.torchDistance <= 0 then
        return
    end


    -- ========================================================
    -- Abstand zaehlen.
    -- ========================================================

    state.torchCounter =
        state.torchCounter + 1


    if state.torchCounter
        < state.torchDistance then

        save()
        return

    end


    -- ========================================================
    -- Fackel suchen.
    -- ========================================================

    local slot =
        findItem(
            "minecraft:torch"
        )


    if not slot then

        service()

        slot =
            findItem(
                "minecraft:torch"
            )

    end


    if not slot then

        error(
            "Keine Fackeln vorhanden."
        )

    end


    -- ========================================================
    -- Bei der ersten Position einer ungeraden Reihe
    -- liegt "hinter der Turtle" ausserhalb des Raumes.
    --
    -- Dort keine Fackel setzen.
    -- ========================================================

    if state.currentCol == 1
    and state.currentRow % 2 == 1 then

        state.torchCounter = 0

        save()

        return

    end


    local oldSlot =
        turtle.getSelectedSlot()


    -- ========================================================
    -- Fuel sicherstellen.
    -- ========================================================

    fuelCheck()


    -- ========================================================
    -- Einen Block zurueck.
    --
    -- Wichtig:
    -- Die Turtle dreht sich dabei NICHT.
    -- Dadurch bleibt state.dir unveraendert.
    -- ========================================================

    local moved, moveErr =
        turtle.back()


    if not moved then

        error(
            "Kann fuer Fackel nicht zurueckfahren: "
            .. tostring(moveErr)
        )

    end


    -- ========================================================
    -- Fackel setzen.
    -- ========================================================

    turtle.select(slot)


    local placed, placeErr =
        turtle.placeDown()


    -- ========================================================
    -- Sofort wieder zurueck auf die Arbeitsposition.
    -- ========================================================

    local returned, returnErr =
        turtle.forward()


    turtle.select(oldSlot)


    if not returned then

        error(
            "Kann nach dem Fackelsetzen nicht "
            .. "zurueck zur Arbeitsposition: "
            .. tostring(returnErr)
        )

    end


    -- ========================================================
    -- Jetzt erst den Platzierungsfehler melden.
    -- Die Turtle befindet sich zu diesem Zeitpunkt wieder
    -- an ihrer urspruenglichen Position.
    -- ========================================================

    if not placed then

        error(
            "Fackel konnte nicht gesetzt werden: "
            .. tostring(placeErr)
        )

    end


    -- ========================================================
    -- Zaehler zuruecksetzen.
    -- ========================================================

    state.torchCounter = 0

    save()

end

]=]


source =
    replaceSection(
        source,
        "local function torchBehind()",
        "-- ============================================================\n-- EINE ABBauPOSITION",
        newTorchBehind
    )


-- ============================================================
-- MINE POSITION
-- ============================================================

local newMinePosition = [=[local function minePosition(
    shouldMove
)

    inventoryCheck()
    fuelCheck()


    -- ========================================================
    -- Block vorne abbauen.
    -- ========================================================

    digFront()


    -- ========================================================
    -- Block ueber der Turtle abbauen.
    --
    -- Das passiert auch dann, wenn dies die letzte
    -- Position einer Reihe ist.
    -- ========================================================

    if state.y + 1 < state.height then

        digAbove()

    end


    -- ========================================================
    -- Nur dann vorwaerts fahren, wenn noch eine weitere
    -- Spalte in dieser Reihe kommt.
    --
    -- DAS ist der wichtige Fix fuer den Reihenwechsel.
    -- ========================================================

    if shouldMove then

        moveForwardRaw()

    end


    -- ========================================================
    -- Fackel hinter der Turtle.
    -- ========================================================

    torchBehind()


    save()

end

]=]


source =
    replaceSection(
        source,
        "local function minePosition()",
        "-- ============================================================\n-- REIHENRICHTUNG",
        newMinePosition
    )


-- ============================================================
-- MINE LAYER
-- ============================================================

local newMineLayer = [=[local function mineLayer(layer)

    state.layer = layer


    -- ========================================================
    -- Startposition des Layers.
    -- ========================================================

    local targetY =
        (layer - 1) * 2


    goTo(
        0,
        targetY,
        0
    )


    -- Erste Reihe beginnt immer bei +X.
    face(0)


    local startRow = 1
    local startCol = 1


    -- ========================================================
    -- Resume.
    -- ========================================================

    if state.currentLayer == layer then

        startRow =
            state.currentRow or 1

        startCol =
            state.currentCol or 1

    else

        state.currentLayer = layer
        state.currentRow = 1
        state.currentCol = 1

        save()

    end


    -- ========================================================
    -- Reihen.
    -- ========================================================

    for row = startRow, state.depth do

        state.currentRow = row


        -- Richtung der Reihe.
        face(
            rowDirection(row)
        )


        local firstCol = 1


        if row == startRow then

            firstCol = startCol

        end


        -- ====================================================
        -- Spalten.
        -- ====================================================

        for col = firstCol, state.width do

            state.currentRow = row
            state.currentCol = col

            save()


            -- ==================================================
            -- Position abbauen.
            --
            -- Nur wenn NICHT die letzte Spalte:
            -- danach vorwaerts fahren.
            -- ==================================================

            minePosition(
                col < state.width
            )


            -- ==================================================
            -- Die gespeicherte Spalte ist weiterhin die
            -- naechste Spalte.
            --
            -- Das ist wichtig fuer resume.
            -- ==================================================

            state.currentCol =
                col + 1

            save()

        end


        -- ====================================================
        -- Reihe fertig.
        --
        -- Die Turtle steht jetzt NICHT mehr einen Block
        -- ausserhalb der Reihe.
        -- ====================================================

        if row < state.depth then

            state.currentRow =
                row + 1

            state.currentCol = 1

            nextRow(row)

        end

    end


    -- ========================================================
    -- Layer fertig.
    -- ========================================================

    state.currentLayer =
        layer + 1

    state.currentRow = 1
    state.currentCol = 1

    save()

end

]=]


source =
    replaceSection(
        source,
        "local function mineLayer(layer)",
        "-- ============================================================\n-- STATUS",
        newMineLayer
    )


-- ============================================================
-- BACKUP DER ORIGINALDATEI
-- ============================================================

if fs.exists(BACKUP) then
    fs.delete(BACKUP)
end


fs.copy(
    INPUT,
    BACKUP
)


-- ============================================================
-- V9 SCHREIBEN
-- ============================================================

writeFile(
    OUTPUT,
    source
)


-- ============================================================
-- ERFOLG
-- ============================================================

print("")
print("==============================")
print("       MINER V9 ERSTELLT")
print("==============================")
print("")

print(
    "Neue Datei: "
    .. OUTPUT
)

print(
    "Backup:     "
    .. BACKUP
)

print("")
print("Die originale miner.lua wurde NICHT veraendert.")
print("")
print("Zum Testen:")
print("")
print("  miner_v9 new 10 20 6 6")
print("")
print("Wenn alles funktioniert:")
print("")
print("  delete miner")
print("  rename miner_v9 miner")
print("")