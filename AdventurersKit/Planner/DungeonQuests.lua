-- A WoW: Forever sajat dungeonjai (a Questie nem ismeri oket): szintsav es questek. Sajat
-- masolat a ForeverDungeonJournal Data\Dungeons.lua-jabol, hogy ne fuggjunk mas addontol.
-- A Questie dungeon tablaja (Zones\dungeons.lua) ezeket nem tartalmazza, a questjeik
-- zoneOrSort-ja pedig a kulso zona, ezert a quest ID alapjan rendeljuk oket a dungeonhoz.
-- quests = { { qid, nev, szint, min. szint, frakcio ("Horde" / "Alliance" / nil = mindketto) } }
local ADDON_NAME, NS = ...

local H, A = "Horde", "Alliance"

local FOREVER = {
    { "Hall of Thanes", 13, 20, {
        { 96395, "An Ancient Grudge", 15, 10 },
        { 96403, "Important Heirlooms", 15, 10 },
        { 96394, "The Restless Dead", 15, 10, A },
        { 96393, "Old Ironforge Incursion", 16, 9, A },
        { 98423, "The Treaty of Understanding", 16, 9, A },
    } },
    { "Ruins of Lordaeron", 15, 22, {
        { 95250, "Abominable Creatures", 21, 16, A },
        { 97288, "Unending Torment", 21, 15, H },
        { 92401, "A Frightened Request", 22, 15, H },
        { 95195, "Bloodied Insignia", 22, 16, A },
        { 95189, "Crest of Lordaeron", 22, 16, A },
        { 95204, "Crest of Lordaeron", 22, 16, H },
        { 92421, "Light's Justice", 22, 15, H },
        { 92415, "Remember That I Love You", 22, 15, A },
        { 95216, "The New Plague", 22, 16, H },
        { 92422, "The Wrath of Rath'mael", 22, 15, H },
    } },
    { "Excavation Site: Wetlands", 26, 33, {
        { 95682, "Open the Maw", 31, 24, H },
        { 95697, "Changing Tastes", 31, 24, H },
        { 98815, "Highland Hides", 28, 24, A },
        { 95772, "Songblade Search", 31, 24, A },
        { 95646, "Horrors in the Highland", 31, 24, A },
        { 95809, "Heartwoven", 31, 24, A },
        { 98824, "Prehistoric Prism", 31, 24, A },
        { 98823, "Earthen Echo", 31, 24, H },
        { 95795, "Fallen in the Fen", 31, 24, A },
    } },
    { "City of Dalaran", 28, 35, {
        { 92456, "A Green Sample", 33, 24, A },
        { 92489, "Power Overwhelming", 33, 24, A },
        { 92457, "Starving Arcane", 33, 30, A },
        { 92458, "Heart of Disruption", 33, 30, A },
        { 96984, "Heart of Disruption", 33, 30, H },
        { 96987, "Opportunistic Education", 33, 24, H },
        { 96988, "Source of Power", 33, 24, H },
        { 96986, "The Grave Knight", 33, 24, H },
    } },
    { "The Drowned City", 35, 42, {
        { 95775, "The Drowned City", 40, 30, H },
        { 96078, "A Tale Spun Around the Fire", 40, 30, H },
        { 95776, "The Only Good Brinescale...", 38, 30, H },
        { 96774, "Ancient Gurubashi Idol", 40, 30, H },
        { 95787, "Take Two With Water", 40, 30, A },
        { 95788, "Magics of the Drowned City", 40, 30, A },
        { 95799, "Findings for the Explorer's League", 40, 30, A },
        { 95798, "The Web of Magic", 40, 30, A },
        { 97130, "Ancient Gurubashi Secrets", 40, 34, A },
        { 95789, "Shady Saltseers", 40, 34 },
        { 95791, "The Saltseer Captain", 40, 34 },
    } },
    { "Krol'dok Stronghold", 40, 47, {
        { 94968, "Eye of Mugg", 45, 40, H },
        { 94972, "Tome of Twilight", 44, 39, H },
        { 94975, "A Token of Vengeance", 42, 38, H },
        { 94982, "Eye of Mugg", 45, 40, A },
        { 94983, "Twilight Mementos", 42, 38, A },
        { 94984, "Tome of Twilight", 44, 39, A },
        { 96771, "Vengeance of the Highborne", 45, 37, A },
        { 94981, "Key Ingredients", 41, 38, A },
        { 94974, "Key Ingredients", 41, 38, H },
        { 94998, "Curios of Curiosity", 42, 38, A },
    } },
    { "Alcaz Prison", 48, 55, {
        { 96772, "The Dragon's Journal", 53, 46, A },
    } },
    { "Blackmaw Hold", 55, 60, {
        { 92343, "Get to the Roots of It", 55, 45, H },
        { 92344, "Get to the Roots of It", 55, 45, A },
        { 97173, "Blackmaw Magic", 59, 52, A },
        { 97198, "Blackmaw Magic", 59, 52, H },
        { 92069, "Claws That Rend, Tusks that Gore", 58, 45 },
        { 92070, "A Lost Memento", 55, 47 },
    } },
    { "Shaper's Terrace", 58, 60, {
        { 95928, "Crystalline Elements", 60, 55, H },
    } },
}
NS.ForeverDungeons = FOREVER

-- qid -> { dungeon, nev, szint, min. szint, frakcio }
local byQid = {}
for _, d in ipairs(FOREVER) do
    for _, q in ipairs(d[4]) do byQid[q[1]] = { d[1], q[2], q[3], q[4], q[5] } end
end
NS.ForeverDungeonQuest = function(qid) return qid and byQid[tonumber(qid)] end
