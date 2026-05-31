-- mods.lua
-- modhousekeeper's curated mod list.
--
-- This is the source of truth for *which* norns projects are mods (community.json
-- does not distinguish mods from scripts). community.json, when available, is used
-- to enrich descriptions and to resolve the canonical install directory; explicit
-- fields here always win.
--
-- Each entry:
--   name        (required) display name
--   url         (required) primary GitHub repository
--   description (required) one-line description
--   category    (required) category header it appears under
--   dir         (optional) on-disk directory name, if it differs from the URL
--               basename (e.g. broadcast installs as "broadcast", not
--               "norns-broadcast"). Usually resolved from community.json instead.
--   alts        (optional) list of { url=, description= } alternative repos/branches
--
-- `categories` fixes the display order of the headers.

return {
  categories = {
    "Arc & Grid",
    "FX",
    "MIDI & OSC",
    "Modulation & sequencing",
    "Network & Streaming",
    "Nota Bene (nb)",
    "Misc",
  },

  mods = {
    -- Arc & Grid
    -- (arcify removed: it is a Lua library (lib/arcify.lua), not a mod -- no lib/mod.lua)
    { name = "Combiner", url = "https://github.com/dstroud/combiner", description = "Configure & aggregate multiple grids", category = "Arc & Grid" },
    { name = "gridkeys", url = "https://github.com/p3r7/gridkeys", description = "Use grid as MIDI keyboard anywhere", category = "Arc & Grid" },
    { name = "iiitoii", url = "https://github.com/andr-ew/iiitoii", description = "iii community scripts ported to norns + crow", category = "Arc & Grid" },

    -- FX
    { name = "FX", url = "https://github.com/sixolet/fx", description = "Multi-effects processor for norns", category = "FX",
      alts = {
        { url = "https://github.com/vehka/fx", description = "serial insert effects" },
        { url = "https://github.com/vehka/fx/tree/feature/pre-post-insert-sends", description = "sends before and after inserts" },
      } },
    { name = "FX Bitcrusher", url = "https://github.com/vehka/fx_bitcrusher", description = "bitcrusher from the pedalboard script", category = "FX" },
    { name = "FX Delay", url = "https://github.com/sixolet/fx_delay", description = "basic delay with a very gentle filter on it", category = "FX" },
    { name = "FX Distortion", url = "https://github.com/vehka/fx_distortion", description = "distortion from the pedalboard script", category = "FX" },
    { name = "FX Filter", url = "https://github.com/xmacex/fx_filter", description = "DFM1 sc filter as an effect", category = "FX" },
    { name = "FX Grains", url = "https://github.com/sixolet/fx_grains", description = "MI Clouds", category = "FX" },
    { name = "FX Resonator", url = "https://github.com/sixolet/fx_resonator", description = "MI Rings, also an nb voice", category = "FX" },
    { name = "FX Tanh", url = "https://github.com/sixolet/fx_tanh", description = "tanh saturator, meant for use as an end-of-chain insert", category = "FX" },

    -- MIDI & OSC
    { name = "14b-mod", url = "https://github.com/Thomasbru/14b-mod", description = "map 14-bit midi to norns parameters", category = "MIDI & OSC" },
    { name = "changez", url = "https://github.com/cachilders/changez", description = "convert program changes to cc", category = "MIDI & OSC" },
    { name = "CyberMIDI", url = "https://github.com/dstroud/cybermidi", description = "Send MIDI between Norns over IP", category = "MIDI & OSC" },
    { name = "mididi", url = "https://github.com/dwtong/midididi", description = "record and play back midi cc loops", category = "MIDI & OSC" },
    { name = "Midigrid", url = "https://github.com/jaggednz/midigrid", description = "Use launchpads & MIDI controllers as grid", category = "MIDI & OSC" },
    -- (miker2049/midigrid alt dropped: that fork is a library, no lib/mod.lua)
    { name = "midikit", url = "https://github.com/xmacex/midikit", description = "MIDI CC output from mod matrix", category = "MIDI & OSC" },
    { name = "mod_clock_div", url = "https://github.com/tomwaters/mod_clock_div", description = "output divisions of the norns clock as midi note on events", category = "MIDI & OSC" },
    { name = "osc-mod", url = "https://github.com/jaseknighter/osc-mod", description = "control the params from any norns script via osc", category = "MIDI & OSC" },
    { name = "passthrough v2", url = "https://github.com/nattog/passthrough", description = "MIDI routing between connected ports", category = "MIDI & OSC" },

    -- Modulation & sequencing
    { name = "Choukanzu", url = "https://github.com/ryleelyman/choukanzu", description = "bird's-eye view of norns script params", category = "Modulation & sequencing" },
    { name = "cyrene", url = "https://github.com/21echoes/cyrene", description = "drum sequencer based on MI's Grids", category = "Modulation & sequencing" },
    { name = "Mod Matrix", url = "https://github.com/sixolet/matrix", description = "Modulation matrix and API for sources", category = "Modulation & sequencing" },
    { name = "Pam's toolkit", url = "https://github.com/sixolet/toolkit", description = "LFOs, rhythms, sequencers, and mults (needs Mod Matrix)", category = "Modulation & sequencing" },
    { name = "pset_seq", url = "https://github.com/jaseknighter/pset_seq", description = "Sequencer for script presets", category = "Modulation & sequencing" },
    { name = "Telexo", url = "https://github.com/brokyo/norns-telexo", description = "Control TXO CV and TR ports from params", category = "Modulation & sequencing" },

    -- Network & Streaming
    { name = "broadcast", url = "https://github.com/schollz/broadcast", description = "Stream audio to norns.online", category = "Network & Streaming" },
    -- ndi-mod (Dewb/ndi-mod) omitted: its mod.lua lives at mod/lib/mod.lua and it
    -- needs a native NDI build, so a plain git clone can't install it as a mod.
    { name = "QRemote", url = "https://github.com/Quixotic7/qremote", description = "Remote control for norns", category = "Network & Streaming" },
    { name = "receiver", url = "https://github.com/markijzerman/receiver", description = "Receive broadcasts from norns users", category = "Network & Streaming" },
    { name = "semiconductor", url = "https://github.com/jaseknighter/norns_semiconductor", description = "Norns ensemble performance script", category = "Network & Streaming" },

    -- Nota Bene (nb)
    { name = "tg", url = "https://github.com/sixolet/tg", description = "Access to nb voices directly from the params menu", category = "Nota Bene (nb)" },
    { name = "nbout", url = "https://github.com/sixolet/nbout", description = "A virtual 17th midi device that outputs to nb voices", category = "Nota Bene (nb)" },
    { name = "nbin", url = "https://github.com/sixolet/nbin", description = "playing nb voices with an external MIDI source", category = "Nota Bene (nb)" },
    { name = "emplaitress", url = "https://github.com/sixolet/emplaitress", description = "nb voice provider - four copies of MI Plaits", category = "Nota Bene (nb)" },
    { name = "nb_wsyn", url = "https://github.com/sixolet/nb_wsyn", description = "voice mod to provide access to w/syn for nb scripts", category = "Nota Bene (nb)" },
    { name = "nb_jf", url = "https://github.com/sixolet/nb_jf", description = "voice mod to provide access to Just Friends for nb scripts", category = "Nota Bene (nb)" },
    { name = "nb_crow", url = "https://github.com/sixolet/nb_crow", description = "Crow v/8 and envelope", category = "Nota Bene (nb)" },
    { name = "nb_ex", url = "https://github.com/sixolet/nb_ex", description = "Disting ex i2c support through Crow", category = "Nota Bene (nb)" },
    { name = "nb_ansible", url = "https://github.com/sixolet/nb_ansible", description = "Ansible voices", category = "Nota Bene (nb)" },
    { name = "nb_harvest", url = "https://github.com/imminentgloom/nb_harvest", description = "høstløv, the synth voice from høst", category = "Nota Bene (nb)" },
    { name = "Seeker", url = "https://github.com/brokyo/seeker", description = "A lightweight n.b arpeggiation mod", category = "Nota Bene (nb)" },
    { name = "sidvagn", url = "https://github.com/sonocircuit/sidvagn", description = "keyboard and sequencer", category = "Nota Bene (nb)" },
    { name = "Oilcan Percussion Co", url = "https://github.com/zjb-s/oilcan", description = "Greasy percussion synth for n.b", category = "Nota Bene (nb)" },
    { name = "doubledecker", url = "https://github.com/sixolet/doubledecker", description = "2-layer synth a la CS-80 (nb voice)", category = "Nota Bene (nb)" },
    { name = "nb_drumcrow", url = "https://github.com/entzmingerc/nb_drumcrow", description = "Turns crow into a synth voice for nb", category = "Nota Bene (nb)" },
    { name = "nb_polyperc", url = "https://github.com/dstroud/nb_polyperc", description = "PolyPerc engine as an nb voice", category = "Nota Bene (nb)" },
    { name = "nb_rudiments", url = "https://github.com/entzmingerc/nb_rudiments", description = "Rudiments synth engine as an nb voice", category = "Nota Bene (nb)" },

    -- Misc
    { name = "cron", url = "https://github.com/stvnrlly/cron", description = "Manage cron on norns via Maiden during development", category = "Misc" },
    { name = "lumberjack", url = "https://github.com/stvnrlly/lumberjack", description = "save the current script's matron logs to a text file", category = "Misc" },
    { name = "Monomaniac", url = "https://github.com/xmacex/monomaniac", description = "Toggle stereo and mono input", category = "Misc" },
    { name = "nice-tapes", url = "https://github.com/MentalSandal/nice-tapes", description = "Customized tape file names", category = "Misc" },
    { name = "Oblique", url = "https://github.com/stvnrlly/oblique", description = "Oblique Strategies in params menu", category = "Misc" },
    { name = "playdate-norns", url = "https://github.com/midouest/playdate-norns", description = "Playdate API available for norns scripts", category = "Misc" },
    { name = "playdate-norns-arc", url = "https://github.com/midouest/playdate-norns-arc", description = "Turn Playdate into an arc emulator for norns", category = "Misc" },
    { name = "random_script", url = "https://github.com/stvnrlly/random_script", description = "Find a random script on norns", category = "Misc" },
    { name = "warmreload", url = "https://github.com/schollz/warmreload", description = "Auto-reload scripts", category = "Misc" },
    { name = "z_tuning", url = "https://github.com/catfact/z_tuning", description = "apply custom tunings", category = "Misc" },
    { name = "norns-example-mod", url = "https://github.com/monome/norns-example-mod", description = "Example mod for matron", category = "Misc" },
  },
}
