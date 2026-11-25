-- Built-in bosses, scenes and models. Numbers an owner tunes are in Warden's
-- Tuning tab instead (server/settings.lua), and staff make presets in the panel,
-- so updating this mod never needs this file merged.
GM = {
    version = "0.9.1",
    maxWave = 12,

    av = {
        record = "Vehicle.av_militech_manticore", -- av_trauma never appears when a server spawns it
        distance = 110,
        height = 70,
        loadMs = 1500, -- extra wait after it streams, so the model is built
        flightSeconds = 5,
        blastRadius = 12,
        fireSeconds = 90,
    },

    -- The Chimera belongs to open77_chimera; health and damage are multipliers.
    chimera = { name = "Militech Chimera", health = 2, damage = 0.8, height = 6, scaling = true, distance = 18 },


    -- AVs the panel offers. Only the Manticore has been seen flying in-game.
    avModels = {
        { record = "Vehicle.av_militech_manticore", name = "Militech Manticore", tested = true },
        { record = "Vehicle.av_rayfield_excalibur", name = "Rayfield Excalibur" },
        { record = "Vehicle.av_zetatech_valgus", name = "Zetatech Valgus" },
        { record = "Vehicle.av_zetatech_surveyor", name = "Zetatech Surveyor" },
        { record = "Vehicle.av_zetatech_octant", name = "Zetatech Octant" },
        { record = "Vehicle.av_zetatech_atlus", name = "Zetatech Atlus" },
        { record = "Vehicle.av_kurt_barghest", name = "Barghest AV" },
        { record = "Vehicle.av_militech", name = "Militech AV" },
        { record = "Vehicle.av_luxury", name = "Luxury AV" },
        -- quest versions: some may look or behave oddly outside their mission
        { record = "Vehicle.q112_arasaka_av", name = "Arasaka AV" },
        { record = "Vehicle.q000_arasaka_av", name = "Arasaka AV, prologue" },
        { record = "Vehicle.q000_arasaka_lux_av", name = "Arasaka luxury AV" },
        { record = "Vehicle.q005_saburo_av", name = "Saburo's AV" },
        { record = "Vehicle.q115_av_smasher", name = "Smasher's AV" },
        { record = "Vehicle.q108_arasaka_helicopter", name = "Arasaka helicopter" },
        { record = "Vehicle.av_trauma", name = "Trauma Team AV" },
        { record = "Vehicle.max_tac_av", name = "MaxTac AV" },
        { record = "Vehicle.q001_police_av", name = "NCPD AV" },
        { record = "Vehicle.q104_av_kang_tao_civilian", name = "Kang Tao AV" },
        { record = "Vehicle.q101_corpo_av", name = "Corporate AV" },
        { record = "Vehicle.q116_delamain_av", name = "Delamain AV" },
        { record = "Vehicle.q114_militech_av", name = "Militech AV, assault" },
        { record = "Vehicle.q110_huge_cargo_av", name = "Huge cargo AV" },
        { record = "Vehicle.q110_news_station_av", name = "News AV" },
        { record = "Vehicle.sa_ep1_airdrop_av", name = "Airdrop AV" },
        { record = "Vehicle.q306_av_atlus_stealth_nusa", name = "NUSA stealth Atlus" },
        { record = "Vehicle.q305_myers_av", name = "Myers' AV" },
        { record = "Vehicle.batty_av", name = "Batty AV" },
    },

    minion = "Character.cpz_maelstrom_grunt1_ranged1_lexington_wa",

    -- Seen working in-game by the author; other models start as catalogue guesses.
    testedModels = {
        "Character.arasaka_minotaur", "Character.Cyberninja_Oda",
        "Character.bls_se_wraiths_strong_gunner3_hmg_mb_elite",
        "Character.maelstrom_fast_fmelee3_mantis_wa_elite",
        "Character.maelstrom_strong_gunner2_defender_mb_rare",
        "Character.cpz_maelstrom_grunt1_ranged1_lexington_wa",
    },

    -- health and damage are difficulty multipliers. Hits are divided by health, so
    -- 1 is the platform's normal toughness. Use gm.status in a fight to tune it.
    bosses = {
        -- height: metres above the feet for the name card.
        warlord = {
            name = "Maelstrom Warlord", health = 8, damage = 2, height = 2.6,
            record = "Character.maelstrom_strong_gunner2_defender_mb_rare",
        },
        reaper = {
            name = "Maelstrom Reaper", health = 5, damage = 1.5, height = 2.3,
            record = "Character.maelstrom_fast_fmelee3_mantis_wa_elite",
        },
        juggernaut = {
            name = "Wraith Juggernaut", health = 6, damage = 1.5, height = 2.6,
            record = "Character.bls_se_wraiths_strong_gunner3_hmg_mb_elite",
        },
        ninja = { name = "Cyberninja", health = 3, damage = 1.5, height = 2.3, record = "Character.Cyberninja_Oda" },
        minotaur = { name = "Arasaka Minotaur", health = 5, damage = 1.5, height = 3.6, record = "Character.arasaka_minotaur" },
    },

    -- A scene is a list of steps run in order around the mark. wait is seconds.
    scenes = {
        avcrash = {
            { action = "announce", message = "msgCrashWarning" },
            { wait = 3 },
            { action = "cinematic", seconds = 10 },
            { action = "av" },
            { wait = 10 },
            { action = "announce", message = "msgCrashSurvivors" },
            { action = "wave", count = 4 },
        },
        bossfight = {
            { action = "announce", message = "msgBossfightIntro" },
            { wait = 4 },
            { action = "boom" },
            { action = "boss", preset = "warlord" },
            { action = "cinematic", seconds = 5 },
            { wait = 25 },
            { action = "wave", count = 3 },
        },
    },
}
