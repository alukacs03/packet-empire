class_name Loc
## Localisation foundation. Player-facing copy that has been moved out of code
## lives here under a stable id; everything else stays where it is until it is
## converted. Networking commands, protocol names, addresses and vendor CLI
## output are deliberately never translated: the accuracy is the point.

const FALLBACK := "en"
static var language := "en"

## id -> {language -> text}. Ids are namespaced by screen or system so a
## translator can see where a line lives without reading the code.
const CATALOG := {
	"opening.title": {"en": "Their first big night. Your network.", "hu": "Az első nagy estéjük. A te hálózatod."},
	"opening.duration": {"en": "THE OPENING SHIFT · ABOUT 20 to 30 MINUTES", "hu": "AZ ELSŐ MŰSZAK · KÖRÜLBELÜL 20-30 PERC"},
	"opening.promise": {"en": "A small webshop trusts you with its first sale. Start with an empty rack and build something people can depend on.", "hu": "Egy kis webáruház rád bízza az első vásárát. Kezdj egy üres rackkel, és építs valamit, amire számíthatnak."},
	"opening.build.title": {"en": "01  Bring it to life", "hu": "01  Keltsd életre"},
	"opening.build.body": {"en": "Install the hardware. Connect the cables. Make your first packets reach the other end.", "hu": "Telepítsd a hardvert. Kösd be a kábeleket. Juttasd el az első csomagokat a túloldalra."},
	"opening.care.title": {"en": "02  Be the person they call", "hu": "02  Téged hívnak, ha baj van"},
	"opening.care.body": {"en": "Investigate a real outage. Follow evidence in your own order. Ask for help whenever you need it.", "hu": "Vizsgálj ki egy valódi kiesést. Kövesd a bizonyítékokat a saját sorrendedben. Kérj segítséget, amikor szükséged van rá."},
	"opening.prove.title": {"en": "03  Carry their big night", "hu": "03  Vidd végig a nagy estéjüket"},
	"opening.prove.body": {"en": "Choose how to launch. Prepare your capacity. Watch the orders keep moving through the network you built.", "hu": "Válaszd ki az indulás módját. Készülj fel a forgalomra. Figyeld, ahogy a rendelések átjutnak az általad épített hálózaton."},
	"opening.pause": {"en": "Space pauses the clock. Your tools keep working. You have time to think.", "hu": "A szóköz megállítja az órát. Az eszközeid tovább működnek. Van időd gondolkodni."},
	"title.tagline": {
		"en": "Build the network. Win the contract. Survive the traffic.",
		"hu": "Építsd meg a hálózatot. Nyerd el a szerződést. Bírd a forgalmat."},
	"title.footer": {
		"en": "Real switches, real routing, real consequences.",
		"hu": "Valódi switchek, valódi routing, valódi következmények."},
	"title.eyebrow": {
		"en": "NETWORK OPERATIONS TYCOON",
		"hu": "HÁLÓZATÜZEMELTETŐ TYCOON"},
	"title.continue": {"en": "Continue", "hu": "Folytatás"},
	"title.continue.sub": {"en": "{company}, cycle {cycle}", "hu": "{company}, {cycle}. ciklus"},
	"title.demo": {"en": "Play the demo", "hu": "Demó indítása"},
	"title.demo.sub": {"en": "The opening arc, start to finish",
		"hu": "A nyitó ív, elejétől a végéig"},
	"title.new": {"en": "New game", "hu": "Új játék"},
	"title.new.sub": {"en": "The full campaign", "hu": "A teljes kampány"},
	"title.load": {"en": "Load game", "hu": "Játék betöltése"},
	"title.load.sub": {"en": "Pick a save slot", "hu": "Válassz mentési helyet"},
	"title.settings": {"en": "Settings", "hu": "Beállítások"},
	"title.settings.sub": {"en": "Scale, sound, colour, language", "hu": "Méret, hang, szín, nyelv"},
	"title.quit": {"en": "Quit", "hu": "Kilépés"},
	"settings.fullscreen": {"en": "Fullscreen", "hu": "Teljes képernyő"},
	"settings.sound": {"en": "Sound", "hu": "Hang"},
	"settings.colourblind": {"en": "Colourblind-friendly status colours",
		"hu": "Színtévesztő-barát állapotszínek"},
	"rack.metric.load": {"en": "CABINET LOAD", "hu": "SZEKRÉNY KIHASZNÁLTSÁG"},
	"rack.metric.power": {"en": "POWER", "hu": "TÁP"},
	"rack.metric.feeds": {"en": "FEED BALANCE", "hu": "TÁPÁGAK EGYENSÚLYA"},
	"rack.info": {"en": "Click hardware to inspect, or an empty U to install something there. Grab any free jack and pull it to another device.", "hu": "Kattints egy eszközre a megtekintéshez, vagy egy üres U-ra a beszereléshez. Fogj meg egy szabad portot és húzd egy másik eszközhöz."},
	"rack.note.tip": {"en": "Leave short context for yourself on this cabinet", "hu": "Rövid megjegyzés magadnak erről a szekrényről"},
	"rack.blueprints": {"en": "Blueprints", "hu": "Tervrajzok"},
	"rack.blueprints.tip": {"en": "Save this rack's layout, or build a saved one into an empty rack", "hu": "Mentsd a rack elrendezését, vagy építs egy mentettet egy üres rackbe"},
	"rack.blueprints.save": {"en": "Save this rack as a blueprint (named after the rack)", "hu": "Mentsd ezt a racket tervrajzként (a rack nevén)"},
	"rack.blueprints.build": {"en": "Build '{name}'   (${price} of hardware)", "hu": "'{name}' megépítése   ({price} $ hardver)"},
	"rack.blueprints.saved": {"en": "Blueprint saved.", "hu": "Tervrajz mentve."},
	"rack.blueprints.built": {"en": "Rack built from the blueprint.", "hu": "A rack a tervrajz szerint megépült."},
	"rack.services": {"en": "Service standards", "hu": "Szolgáltatássablonok"},
	"rack.services.tip": {"en": "Capture a working local LAN, or deploy it with fresh addresses and a customer VLAN.", "hu": "Ments el egy működő helyi hálózatot, vagy telepítsd új címekkel és ügyfél-VLAN-nal."},
	"rack.sell": {"en": "Sell rack (${price})", "hu": "Rack eladása ({price} $)"},
	"rack.sell.tip": {"en": "Only empty racks can be sold", "hu": "Csak üres rack adható el"},
	"rack.sold": {"en": "Rack sold for ${price}.", "hu": "Rack eladva {price} $-ért."},
	"rack.sell.full": {"en": "Empty the rack first: devices are still installed.", "hu": "Előbb ürítsd ki a racket: még vannak benne eszközök."},
	"services.lede": {"en": "Build it once. Prove it. Give the next customer the same care, with fresh addresses.", "hu": "Építsd meg egyszer. Bizonyítsd be. A következő ügyfél ugyanezt kapja, új címekkel."},
	"services.save": {"en": "Save this cabinet's working LAN", "hu": "A szekrény működő hálózatának mentése"},
	"services.saved": {"en": "Working service saved with its cabling.", "hu": "A működő szolgáltatás a kábelezésével együtt mentve."},
	"services.none": {"en": "No service standards yet. Connect and address a small LAN, verify a ping, then save it here.", "hu": "Még nincs szolgáltatássablon. Kábelezz és címezz egy kis hálózatot, ellenőrizd egy pinggel, majd mentsd itt."},
	"services.deploy_into": {"en": "Deploy into {rack}", "hu": "Telepítés ide: {rack}"},
	"services.prefix.placeholder": {"en": "Fresh /24 prefix, e.g. 10.80.0", "hu": "Új /24 előtag, pl. 10.80.0"},
	"services.prefix": {"en": "Network prefix · three octets", "hu": "Hálózati előtag · három oktett"},
	"services.vlan": {"en": "Customer VLAN", "hu": "Ügyfél-VLAN"},
	"services.deploy": {"en": "Deploy and verify connectivity", "hu": "Telepítés és a kapcsolat ellenőrzése"},
	"services.deployed": {"en": "Service deployed. Every server passed its connectivity check.", "hu": "Szolgáltatás telepítve. Minden szerver átment a kapcsolat-ellenőrzésen."},
	"menu.section.practice": {"en": "PRACTICE", "hu": "GYAKORLÁS"},
	"menu.section.share": {"en": "SHARE AND EXPORT", "hu": "MEGOSZTÁS ÉS EXPORT"},
	"menu.scenarios.tip": {"en": "Authored situations to work through; your own datacenter waits for you", "hu": "Megírt helyzetek, amiken végigmehetsz; a saját adatközpontod megvár"},
	"menu.sandbox.tip": {"en": "Free hardware, no bills, no events: somewhere to try an idea", "hu": "Ingyen hardver, számlák és események nélkül: hely egy ötlet kipróbálására"},
	"dev.hostname": {"en": "Hostname", "hu": "Gépnév"},
	"dev.psu.tip": {"en": "Which power feed this device is plugged into", "hu": "Melyik tápágra van bedugva ez az eszköz"},
	"dev.section.front": {"en": "FRONT PANEL  /  CLICK A PORT TO INSPECT OR CABLE", "hu": "ELŐLAP  /  KATTINTS EGY PORTRA: ÁLLAPOT VAGY KÁBELEZÉS"},
	"dev.section.vlans": {"en": "OBSERVED VLAN DATABASE  /  CONFIGURE IN CONSOLE", "hu": "MEGFIGYELT VLAN-OK  /  BEÁLLÍTÁS A KONZOLBAN"},
	"dev.note.tip": {"en": "Leave short handover context on this device", "hu": "Rövid átadási megjegyzés ehhez az eszközhöz"},
	"dev.console.open": {"en": "Open console", "hu": "Konzol megnyitása"},
	"dev.console.close": {"en": "Close console", "hu": "Konzol bezárása"},
	"dev.console.size.tip": {"en": "Cycle the console height (or type terminal length N)", "hu": "A konzol magasságának váltása (vagy: terminal length N)"},
	"dev.learn.tip": {"en": "Open the field manual at the article for what you last typed", "hu": "A kézikönyv fejezete arról, amit utoljára beírtál"},
	"dev.capture.tip": {"en": "Live capture (tcpdump) of this device", "hu": "Élő forgalomfigyelés (tcpdump) ezen az eszközön"},
	"dev.templates": {"en": "Templates", "hu": "Sablonok"},
	"dev.templates.tip": {"en": "Save this device as a standard, or apply one", "hu": "Mentsd ezt az eszközt sablonként, vagy alkalmazz egyet"},
	"find.title": {"en": "Find", "hu": "Keresés"},
	"find.placeholder": {"en": "device name, address, VLAN id, customer or site", "hu": "eszköznév, cím, VLAN azonosító, ügyfél vagy telephely"},
	"find.empty": {"en": "Type to search across every site.", "hu": "Gépelj: minden telephelyen keres."},
	"find.why.device": {"en": "device", "hu": "eszköz"},
	"find.why.model": {"en": "model", "hu": "típus"},
	"find.why.address": {"en": "address {cidr} on {iface}", "hu": "{cidr} cím a(z) {iface} porton"},
	"find.why.iface": {"en": "interface {iface}", "hu": "{iface} interfész"},
	"find.why.note": {"en": "note: {text}", "hu": "jegyzet: {text}"},
	"find.why.iface_note": {"en": "{iface} note: {text}", "hu": "{iface} jegyzet: {text}"},
	"find.customer": {"en": "customer: {name} ({kind}, ${fee}/cycle)", "hu": "ügyfél: {name} ({kind}, {fee} $/ciklus)"},
	"find.tag.offline": {"en": "OFFLINE", "hu": "KIKAPCSOLVA"},
	"find.tag.psec": {"en": "port-security shutdown", "hu": "portbiztonsági lezárás"},
	"find.tag.unsaved": {"en": "unsaved config", "hu": "mentetlen konfiguráció"},
	"find.tag.congested": {"en": "congested link", "hu": "túlterhelt kapcsolat"},
	"help.title": {"en": "Keys and controls", "hu": "Billentyűk és vezérlés"},
	"help.floor": {"en": "FLOOR", "hu": "PADLÓ"},
	"help.views": {"en": "VIEWS", "hu": "NÉZETEK"},
	"help.console": {"en": "CONSOLE", "hu": "KONZOL"},
	"help.h1": {"en": "select mode / place-rack mode", "hu": "kijelölés / rack elhelyezése"},
	"help.h2": {"en": "pause and resume", "hu": "szünet és folytatás"},
	"help.h3": {"en": "normal, fast and faster", "hu": "normál, gyors és gyorsabb"},
	"help.h4": {"en": "operations dashboard (device health)", "hu": "üzemeltetési panel (eszközök állapota)"},
	"help.h5": {"en": "find a device, address, VLAN or customer", "hu": "eszköz, cím, VLAN vagy ügyfél keresése"},
	"help.h6": {"en": "logical topology map", "hu": "logikai topológiatérkép"},
	"help.h7": {"en": "this help", "hu": "ez a súgó"},
	"help.h8": {"en": "system menu (save, practice, share and export, quit)", "hu": "rendszermenü (mentés, gyakorlás, megosztás és export, kilépés)"},
	"help.h9": {"en": "save the game to the current slot", "hu": "mentés az aktuális helyre"},
	"help.h10": {"en": "pan the floor", "hu": "a padló mozgatása"},
	"help.h11": {"en": "zoom toward the cursor", "hu": "nagyítás a kurzor felé"},
	"help.h12": {"en": "open the rack cabinet", "hu": "a rackszekrény megnyitása"},
	"help.h13": {"en": "open its front panel", "hu": "az előlap megnyitása"},
	"help.h14": {"en": "pull a cable between two devices in the same cabinet", "hu": "kábel húzása két eszköz között ugyanabban a szekrényben"},
	"help.h15": {"en": "inspect its state or arrange a remote cable run", "hu": "állapot megtekintése vagy távoli kábelezés"},
	"help.h16": {"en": "remove a blanking panel", "hu": "vakpanel eltávolítása"},
	"help.h17": {"en": "move a node on the topology map", "hu": "csomópont mozgatása a térképen"},
	"help.h18": {"en": "close the panel on top (the console first, then the card)", "hu": "a felső panel bezárása (előbb a konzol, aztán a kártya)"},
	"help.h19": {"en": "addresses, VLANs, routing and policy live here", "hu": "címek, VLAN-ok, útválasztás és szabályok itt élnek"},
	"help.h20": {"en": "complete the command or list candidates", "hu": "parancs kiegészítése vagy a lehetőségek listája"},
	"help.h21": {"en": "show what is possible at this point", "hu": "mit lehet itt beírni"},
	"help.h22": {"en": "command history", "hu": "parancselőzmények"},
	"help.h23": {"en": "back to privileged exec, like a real console", "hu": "vissza a privilegizált módba, mint egy igazi konzolon"},
	"help.h24": {"en": "start and end of the line", "hu": "a sor eleje és vége"},
	"help.h25": {"en": "delete to the start, to the end, the previous word", "hu": "törlés a sor elejéig, végéig, az előző szóig"},
	"help.h26": {"en": "clear the screen / abandon the line", "hu": "képernyő törlése / a sor elvetése"},
	"help.h27": {"en": "wipe the screen", "hu": "a képernyő törlése"},
	"help.h28": {"en": "run the last command again", "hu": "az utolsó parancs újra"},
	"help.h29": {"en": "several lines pasted run one after another", "hu": "több beillesztett sor egymás után fut"},
	"help.h30": {"en": "size the pane to N rows (the ▤ button takes over again)", "hu": "a panel N sor magas (a ▤ gomb újra átveszi)"},
	"help.h31": {"en": "jump into another device's CLI, or FRR's shell on a Linux box (exit returns)", "hu": "ugrás egy másik eszköz CLI-jébe, vagy az FRR shelljébe egy Linux gépen (az exit visszahoz)"},
	"help.h32": {"en": "close the console", "hu": "a konzol bezárása"},
	"settings.motion.tip": {"en": "Replaces traveling highlights and decorative movement with static confirmations", "hu": "A mozgó kiemeléseket és díszmozgásokat álló visszajelzésekre cseréli"},
	"settings.toolbox.tip": {"en": "For experienced players: reveal every navigation area without waiting for campaign unlocks", "hu": "Tapasztalt játékosoknak: minden panel elérhető a kampány feloldásai nélkül"},
	"settings.hints.tip": {"en": "A comment line under a console error that says what to try, and a LEARN chip that opens the field manual", "hu": "Egy megjegyzés a konzolhiba alatt, hogy mit érdemes próbálni, és egy LEARN gomb, ami a kézikönyvet nyitja"},
	"title.error": {"en": "Something went wrong", "hu": "Valami elromlott"},
	"rack.blank.fitted": {"en": "Blanking panel fitted · right-click to remove · left-click to install hardware", "hu": "Vakpanel beszerelve · jobb klikk: eltávolítás · bal klikk: hardver beszerelése"},
	"rack.blank.gap": {"en": "Open rack gap · right-click to fit a blanking panel · left-click to install hardware", "hu": "Üres rackhely · jobb klikk: vakpanel · bal klikk: hardver beszerelése"},
	"settings.motion": {"en": "Reduce motion", "hu": "Kevesebb mozgás"},
	"settings.hints": {"en": "Learner hints under console errors", "hu": "Tanulói tippek a konzol hibái alatt"},
	"settings.volume": {"en": "Volume", "hu": "Hangerő"},
	"settings.music": {"en": "Music and hum", "hu": "Zene és zúgás"},
	"title.intro.title": {"en": "What this is", "hu": "Mi ez"},
	"title.intro.p1": {"en": "You run a small network business. It starts with one rack in somebody else's building and a customer who wants two offices joined up.", "hu": "Egy kis hálózati céget vezetsz. Egy rackkel indul valaki más épületében, és egy ügyféllel, aki két irodát akar összekötni."},
	"title.intro.p2": {"en": "Everything under the hood is real: MAC learning, VLANs, spanning tree, routing, DHCP, BGP. The switches take Arista-style commands, the cheap gear takes RouterOS. Nothing is faked, so when a ping fails there is a reason and you can find it.", "hu": "A motorháztető alatt minden valódi: MAC-tanulás, VLAN-ok, feszítőfa, útválasztás, DHCP, BGP. A switchek Arista-stílusú parancsokat vesznek, az olcsó gépek RouterOS-t. Semmi sincs hamisítva: ha egy ping nem megy, annak oka van, és megtalálhatod."},
	"title.intro.p3": {"en": "The demo covers the opening arc, which is about half an hour. It ends at the point where the business game opens up.", "hu": "A demó a nyitó ívet fedi le, ami nagyjából fél óra. Ott ér véget, ahol az üzleti játék kinyílik."},
	"title.intro.tips": {"en": "Worth knowing", "hu": "Jó tudni"},
	"title.intro.tip1": {"en": "F1 shows the keys and controls at any time.", "hu": "Az F1 bármikor megmutatja a billentyűket és a vezérlést."},
	"title.intro.tip2": {"en": "Escape steps back out of anything.", "hu": "Az Escape mindenből visszalép."},
	"title.intro.tip3": {"en": "The field manual (LEARN) explains every concept the game uses.", "hu": "A kézikönyv (LEARN) elmagyaráz minden fogalmat, amit a játék használ."},
	"title.slots.title": {"en": "Save slots", "hu": "Mentési helyek"},
	"title.slots.auto": {"en": "The autosave is written every few cycles while you play. It is never used for a new game.", "hu": "Az automatikus mentés néhány ciklusonként íródik játék közben. Új játékhoz sosem használjuk."},
	"title.slots.autosave": {"en": "Autosave", "hu": "Automentés"},
	"title.slots.slot": {"en": "Slot {n}", "hu": "{n}. hely"},
	"title.slots.empty": {"en": "empty", "hu": "üres"},
	"title.slots.load": {"en": "Load", "hu": "Betöltés"},
	"title.slots.delete": {"en": "Delete", "hu": "Törlés"},
	"title.slots.delete_confirm": {"en": "Delete? (click again)", "hu": "Törlés? (kattints újra)"},
	"title.new.title": {"en": "New game", "hu": "Új játék"},
	"title.new.demo_title": {"en": "Play the demo", "hu": "Demó indítása"},
	"title.new.company": {"en": "Company name", "hu": "Cégnév"},
	"title.new.company_hint": {"en": "Your company (blank picks one for you)", "hu": "A céged (üresen kap egy nevet)"},
	"title.new.difficulty": {"en": "Difficulty", "hu": "Nehézség"},
	"title.new.start": {"en": "Start", "hu": "Indítás"},
	"title.new.start_demo": {"en": "Start the demo", "hu": "Demó indítása"},
	"title.new.slot_note": {"en": "A new game takes the first free slot. If all three are full it overwrites the oldest, so rename or clear a slot first if you want to keep it.", "hu": "Az új játék az első szabad helyre kerül. Ha mind a három foglalt, a legrégebbit írja felül, ezért előbb ürítsd ki azt, amit meg akarsz tartani."},
	"title.new.demo_note": {"en": "The demo runs on the standard difficulty so the pacing matches the walkthrough.", "hu": "A demó a normál nehézségen fut, hogy a tempó a végigjátszáshoz igazodjon."},
	"title.new.last": {"en": "The last company", "hu": "Az előző cég"},
	"settings.toolbox": {"en": "Show the full toolbox from the start",
		"hu": "Mutasd a teljes eszköztárat az elejétől"},
	"settings.language": {"en": "Language", "hu": "Nyelv"},
	"settings.scale": {"en": "Interface scale", "hu": "Felület mérete"},
	"menu.resume": {"en": "Resume", "hu": "Vissza a játékhoz"},
	"menu.save": {"en": "Save game", "hu": "Játék mentése"},
	"menu.save_as": {"en": "Save to slot…", "hu": "Mentés helyre…"},
	"menu.to_title": {"en": "Save and return to title", "hu": "Mentés és vissza a főmenübe"},
	"menu.scenarios": {"en": "Scenarios…", "hu": "Forgatókönyvek…"},
	"menu.sandbox": {"en": "Sandbox mode", "hu": "Homokozó mód"},
	"menu.settings": {"en": "Settings…", "hu": "Beállítások…"},
	"menu.difficulty": {"en": "Difficulty…", "hu": "Nehézség…"},
	"menu.quit": {"en": "Save & quit", "hu": "Mentés és kilépés"},
	"settings.on": {"en": "on", "hu": "be"},
	"settings.off": {"en": "off", "hu": "ki"},
	"title.esc": {"en": "ESC returns to this briefing.",
		"hu": "Az ESC visszavisz ehhez az eligazításhoz."},
	"settings.again": {"en": "You can change these again from the in-game menu.",
		"hu": "Ezeket a játékon belüli menüből is átállíthatod."},
	"welcome.title": {
		"en": "Welcome to the floor",
		"hu": "Üdv a gépteremben"},
	"welcome.shift": {
		"en": "SHIFT 01  /  LEGACY COLO  /  02:13",
		"hu": "01. MŰSZAK  /  RÉGI KOLOKÁCIÓ  /  02:13"},
	"welcome.lede": {
		"en": "One borrowed cage. Questionable wiring. Enough cash for one rack. Turn this forgotten corner into a network people can depend on.",
		"hu": "Egy kölcsönkapott ketrec. Kétes kábelezés. Pénz pontosan egy rakra. Csinálj ebből az elfeledett sarokból olyan hálózatot, amire számítani lehet."},
	"welcome.module1.title": {"en": "READ THE ROOM", "hu": "OLVASD A TERMET"},
	"welcome.module1.body": {
		"en": "Right-drag to pan. Scroll to zoom. Every cable and blinking port is part of the simulation.",
		"hu": "Jobb gombbal húzva mozgatsz, görgetéssel nagyítasz. Minden kábel és villogó port a szimuláció része."},
	"welcome.module2.title": {"en": "BUILD FOR REAL", "hu": "ÉPÍTS IGAZÁN"},
	"welcome.module2.body": {
		"en": "Place a rack, install hardware, then wire ports. Cheap PacketTik gear speaks RouterOS.",
		"hu": "Helyezz el egy rakot, építs bele hardvert, aztán kösd össze a portokat. Az olcsó PacketTik eszközök RouterOS-t beszélnek."},
	"welcome.module3.title": {"en": "KEEP IT ALIVE", "hu": "TARTSD ÉLETBEN"},
	"welcome.module3.body": {
		"en": "Contracts fund the floor. Diagnose failures at the console and earn the next expansion.",
		"hu": "A szerződések tartják el a géptermet. A konzolon diagnosztizáld a hibákat, és keresd ki a következő bővítést."},
	"welcome.tip": {
		"en": "The live brief stays on the right. It gives you the next objective without solving the network for you.",
		"hu": "Az élő feladatleírás jobb oldalt marad. Megadja a következő célt, de nem oldja meg helyetted a hálózatot."},
	"welcome.start": {
		"en": "CLOCK IN  ·  OPEN THE FIRST JOB",
		"hu": "MŰSZAK KEZDÉSE  ·  AZ ELSŐ MUNKA"},
	"contract.rackup.title": {
		"en": "Rack and stack",
		"hu": "Beépítés és bekábelezés"},
	"contract.rackup.customer": {
		"en": "Your first colo",
		"hu": "Az első kolokációd"},
	"contract.rackup.hint": {
		"en": "Press R, click a floor tile to place the rack, then click the rack to open it. Buy from the slot menu: one switch, two servers. Then click a server's port and choose Run cable, and click the switch port you want it in.",
		"hu": "Nyomd meg az R-t, kattints egy padlócsempére a rak elhelyezéséhez, majd kattints a rakra a megnyitásához. A férőhely-menüből vegyél egy switchet és két szervert. Ezután kattints a szerver portjára, válaszd a Kábel húzása lehetőséget, és kattints arra a switchportra, amelyikbe akarod."},
	"contract.rackup.brief": {
		"en": "Welcome to your corner of the colo floor! Buy a rack (BUILD or R, click a floor tile), open it and install one switch and two servers, then cable both servers to the switch (click a server port, then 'Run cable…').",
		"hu": "Üdv a kolokáció saját sarkodban! Vegyél egy rakot (ÉPÍTÉS vagy R, majd kattints egy padlócsempére), nyisd ki, építs bele egy switchet és két szervert, végül kösd mindkét szervert a switchre (kattints a szerver portjára, majd a „Kábel húzása…” lehetőségre)."},
	"event.outage.raised": {
		"en": "FIRST OUTAGE: {customer} is unreachable. A known-safe access port tripped; acknowledge the alert and diagnose from evidence.",
		"hu": "ELSŐ ÜZEMZAVAR: {customer} nem érhető el. Egy biztonságosan visszaállítható hozzáférési port esett ki; vedd át az incidenst, és a bizonyítékokból diagnosztizálj."},
	"event.outage.status": {
		"en": "CUSTOMER COMMS: {customer} sees the honest update. Outage reputation loss is now -2/cycle instead of -4.",
		"hu": "ÜGYFÉLKOMMUNIKÁCIÓ: {customer} látja az őszinte tájékoztatást. Az üzemzavar hírnévvesztesége mostantól -2/ciklus a -4 helyett."},
	"event.outage.recovered": {
		"en": "FIRST OUTAGE COMPLETE: calm diagnosis kept {customer} and left the network more resilient.",
		"hu": "ELSŐ ÜZEMZAVAR LEZÁRVA: a nyugodt diagnózis megtartotta {customer} ügyfelet, és ellenállóbbá tette a hálózatot."},
	"pedia.vlans.title": {
		"en": "VLANs",
		"hu": "VLAN-ok"},
	"pedia.vlans.body": {
		"en": "One physical switch, many isolated networks. Each access port belongs to one VLAN; frames never cross VLANs without a router. Separate customers = separate VLANs.",
		"hu": "Egy fizikai switch, sok elkülönített hálózat. Minden hozzáférési port egyetlen VLAN-hoz tartozik; a keretek router nélkül soha nem lépnek át másik VLAN-ba. Külön ügyfél = külön VLAN."},
	"ui.cycles": {
		"en": "{count} cycle|{count} cycles",
		"hu": "{count} ciklus|{count} ciklus"},
	"ui.money": {
		"en": "${amount}",
		"hu": "{amount} $"},
}

static func languages() -> Array:
	return ["en", "hu", "pseudo"]

static func language_label(code: String) -> String:
	match code:
		"hu":
			return "Magyar"
		"pseudo":
			return "Pseudo (layout test)"
	return "English"

static func has(id: String) -> bool:
	return CATALOG.has(id)

static func t(id: String, args := {}) -> String:
	## Missing ids never crash and never silently vanish: they come back as the
	## id itself, which is loud enough to notice and safe enough to ship.
	if not CATALOG.has(id):
		return id
	var entry: Dictionary = CATALOG[id]
	var text: String = String(entry.get(language, entry.get(FALLBACK, id)))
	if language == "pseudo":
		text = String(entry.get(FALLBACK, id))
	# substitute first: the pseudo transform accents the letters inside a
	# placeholder too, and then nothing matches and the braces ship
	for key: String in args:
		text = text.replace("{%s}" % key, str(args[key]))
	if language == "pseudo":
		text = pseudo(text)
	return text

static var _plural_rx: RegEx = null

static func tidy_plurals(text: String) -> String:
	## "1 cycle(s)" -> "1 cycle", "3 cycle(s)" -> "3 cycles": the "(s)" spelling is
	## resolved on the way to the screen, so no line ever reads "1 cycles"
	## ponytail: English suffix rules only; the Hungarian forms carry no "(s)"
	if "(s)" not in text:
		return text
	if _plural_rx == null:
		_plural_rx = RegEx.new()
		_plural_rx.compile("(\\d+) ([A-Za-z]+)\\(s\\)")
	var out := text
	for m in _plural_rx.search_all(text):
		var n := int(m.get_string(1))
		var noun := m.get_string(2)
		out = out.replace(m.get_string(0), "%d %s" % [n, noun if n == 1 else noun + "s"])
	return out

static func plural(id: String, count: int, args := {}) -> String:
	## Two forms, separated by a pipe: enough for English and Hungarian, and
	## honest about not being enough for every language.
	var merged := args.duplicate()
	merged["count"] = count
	var text := t(id, merged)
	var forms := text.split("|")
	if forms.size() < 2:
		return text
	return String(forms[0]) if count == 1 else String(forms[1])

static func money(amount: int) -> String:
	return t("ui.money", {"amount": amount})

static func percent(value: float) -> String:
	return "%d%%" % int(round(value * 100.0))

static func cycles(count: int) -> String:
	return plural("ui.cycles", count)

static func pseudo(text: String) -> String:
	## Longer, accented, and still readable: the point is to find clipping and
	## hard-coded strings, not to be funny.
	const MAP := {"a": "à", "e": "ë", "i": "í", "o": "ö", "u": "ü", "A": "Á", "E": "É",
		"O": "Ö", "s": "š", "n": "ñ"}
	var out := ""
	for c in text:
		out += String(MAP.get(c, c))
	var padding := int(max(1.0, float(text.length()) * 0.3))
	return "[%s%s]" % [out, "·".repeat(padding)]

static func missing_ids(used: Array) -> Array:
	var out: Array = []
	for id: String in used:
		if not CATALOG.has(id):
			out.append(id)
	return out

static func placeholder_problems() -> Array:
	## Every translation must carry the same {placeholders} as the English, or
	## a live value silently disappears at runtime.
	var problems: Array = []
	for id: String in CATALOG:
		var entry: Dictionary = CATALOG[id]
		var base := _placeholders(String(entry.get(FALLBACK, "")))
		for lang: String in entry:
			if lang == FALLBACK:
				continue
			if _placeholders(String(entry[lang])) != base:
				problems.append("%s (%s)" % [id, lang])
	return problems

static func _placeholders(text: String) -> Array:
	var out: Array = []
	var rest := text
	while "{" in rest:
		var start := rest.find("{")
		var end := rest.find("}", start)
		if end < 0:
			break
		out.append(rest.substr(start, end - start + 1))
		rest = rest.substr(end + 1)
	out.sort()
	return out
