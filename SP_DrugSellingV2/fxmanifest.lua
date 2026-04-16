shared_script "@ReaperV4/imports/bypass.js"
shared_script "@ReaperV4/imports/bypass.lua"
shared_script "@ReaperV4/imports/bypass_s.lua"
shared_script "@ReaperV4/imports/bypass_c.lua"
lua54 "yes" -- needed for Reaper

shared_script '@WaveShield/resource/include.lua'
shared_script '@WaveShield/resource/waveshield.js'


-- resource bypass & lua runtime load for cfx.ac, do NOT touch
shared_script '@vanguard/bypass.lua'
lua54 'yes'
fx_version 'cerulean'
game 'gta5'
author 'sopaidej'
description 'Drug Dealer Script with Curb and Corner Selling'
version '2.0.0'
resource_manifest_name 'nbk_drug_dealer'
shared_script '@ox_lib/init.lua'
ui_page 'html/index.html'
files { 'html/index.html', 'html/script.js', 'html/style.css' }
client_script 'client.lua'
server_script 'server.lua'
shared_script 'config.lua'

dependencies {
    'ox_lib',
    'ox_inventory',
    'ox_target',
    'es_extended'
}
escrow_ignore {
    'config.lua',
}
dependency '/assetpacks'
