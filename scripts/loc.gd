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
	"unlock.facility.kicker": {"en": "NEW GROUND  /  THE BUILDING", "hu": "ÚJ TEREP  /  AZ ÉPÜLET"},
	"unlock.facility.title": {"en": "The building is yours to look after now.", "hu": "Az épület mostantól a te gondod."},
	"unlock.facility.body": {"en": "Filters, an aircon service, a generator test, a battery check. None of it is urgent until the afternoon it is, and by then it is expensive.", "hu": "Szűrők, klímaszerviz, generátorteszt, akkumulátor-ellenőrzés. Egyik sem sürgős addig a délutánig, amikor az lesz, és akkor már drága."},
	"unlock.facility.where": {"en": "OPS  /  FACILITY", "hu": "OPS  /  LÉTESÍTMÉNY"},
	"unlock.facility.action": {"en": "See the schedule", "hu": "Nézd meg az ütemtervet"},
	"unlock.renewals.kicker": {"en": "NEW DIARY  /  RENEWALS", "hu": "ÚJ NAPTÁR  /  MEGÚJÍTÁSOK"},
	"unlock.renewals.title": {"en": "Something is about to lapse.", "hu": "Valami hamarosan lejár."},
	"unlock.renewals.body": {"en": "Licences and contracts run out quietly. A lapsed licence does not break the device; it caps it, which is much harder to find.", "hu": "A licencek és szerződések csendben járnak le. A lejárt licenc nem töri el az eszközt; korlátozza, amit sokkal nehezebb megtalálni."},
	"unlock.renewals.where": {"en": "OPS  /  RECORDS", "hu": "OPS  /  NYILVÁNTARTÁS"},
	"unlock.renewals.action": {"en": "Open the calendar", "hu": "Nyisd meg a naptárat"},
	"unlock.duties.kicker": {"en": "NEW BOARD  /  DUTIES", "hu": "ÚJ TÁBLA  /  FELADATOK"},
	"unlock.duties.title": {"en": "There are two of them now.", "hu": "Most már ketten vagytok."},
	"unlock.duties.body": {"en": "Chores can be handed over. What you give away costs money and a little control, and comes back done the way that person works.", "hu": "A rutinfeladatok átadhatók. Amit kiadsz, pénzbe és egy kis kontrollba kerül, és úgy jön vissza, ahogy az a személy dolgozik."},
	"unlock.duties.where": {"en": "OPS  /  AUTOMATION", "hu": "OPS  /  AUTOMATIZÁLÁS"},
	"unlock.duties.action": {"en": "Assign something", "hu": "Ossz ki valamit"},
	"unlock.second_site.kicker": {"en": "NEW GROUND  /  A SECOND BUILDING", "hu": "ÚJ TEREP  /  EGY MÁSODIK ÉPÜLET"},
	"unlock.second_site.title": {"en": "Everything you own is in one room.", "hu": "Minden, amid van, egy szobában van."},
	"unlock.second_site.body": {"en": "A second floor costs a fit-out and rent, splits the crew and doubles the diary. What it buys is the one thing another rack cannot: a service that is still there when this room is not, which is what the customers who ask about fires are paying for.", "hu": "Egy második emelet kiépítésbe és bérletbe kerül, megosztja a csapatot és megduplázza a naptárat. Amit vesz rajta: az egyetlen dolog, amit egy újabb rack nem tud: egy szolgáltatás, ami akkor is él, amikor ez a szoba nem, és a tűzről kérdező ügyfelek ezért fizetnek."},
	"unlock.second_site.where": {"en": "COMPANY  /  MARKET", "hu": "CÉG  /  PIAC"},
	"unlock.second_site.action": {"en": "See what is available", "hu": "Nézd meg, mi elérhető"},
	"unlock.oncall.kicker": {"en": "NEW ARRANGEMENT  /  THE PHONE", "hu": "ÚJ MEGÁLLAPODÁS  /  A TELEFON"},
	"unlock.oncall.title": {"en": "The room is empty and something can still break.", "hu": "A szoba üres, és valami még mindig elromolhat."},
	"unlock.oncall.body": {"en": "Somebody can carry the phone for a retainer. When it rings it is them, it costs half, and it costs them less, because that is what the retainer bought.", "hu": "Valaki hordhatja a telefont készenléti díjért. Ha csörög, ő az, feleannyiba kerül, és neki is kevesebbe, mert ezt vette meg a készenléti díj."},
	"unlock.oncall.where": {"en": "COMPANY  /  BUSINESS", "hu": "CÉG  /  ÜZLET"},
	"unlock.oncall.action": {"en": "Put somebody on call", "hu": "Tegyél valakit készenlétbe"},
	"unlock.handover.kicker": {"en": "NEW HABIT  /  THE HANDOVER", "hu": "ÚJ SZOKÁS  /  AZ ÁTADÁS"},
	"unlock.handover.title": {"en": "The shift going home left you a note.", "hu": "A hazamenő műszak hagyott egy jegyzetet."},
	"unlock.handover.body": {"en": "What happened, what is still open, and what to look at first. Notes nobody reads stop being true, and the next shift finds out the hard way.", "hu": "Mi történt, mi van még nyitva, és mit nézz meg először. A jegyzet, amit senki nem olvas, előbb-utóbb nem igaz, és a következő műszak a nehezebb úton tudja meg."},
	"unlock.handover.where": {"en": "COMPANY  /  LOG", "hu": "CÉG  /  NAPLÓ"},
	"unlock.handover.action": {"en": "Read it", "hu": "Olvasd el"},
	"unlock.failover.kicker": {"en": "NEW EXERCISE  /  PROVING IT", "hu": "ÚJ GYAKORLAT  /  BIZONYÍTÁS"},
	"unlock.failover.title": {"en": "Redundancy you have never tested is a belief.", "hu": "A soha nem tesztelt redundancia csak hit."},
	"unlock.failover.body": {"en": "Book a failover test. The upstream goes away on purpose, at a cycle you chose, and the result is judged on whether any customer noticed.", "hu": "Foglalj átállási tesztet. A felmenő kapcsolat szándékosan elmegy, egy általad választott ciklusban, és az eredményt az dönti el, hogy észrevette-e bármelyik ügyfél."},
	"unlock.failover.where": {"en": "OPS  /  FACILITY", "hu": "OPS  /  LÉTESÍTMÉNY"},
	"unlock.failover.action": {"en": "Book one", "hu": "Foglalj egyet"},
	"unlock.access.kicker": {"en": "NEW QUESTION  /  THE DOOR", "hu": "ÚJ KÉRDÉS  /  AZ AJTÓ"},
	"unlock.access.title": {"en": "Somebody who does not work here is on the floor.", "hu": "Valaki, aki nem itt dolgozik, a padlón van."},
	"unlock.access.body": {"en": "An open floor is fastest and keeps no record of anything. Badges and escorts cost time on every visit and are the only reason you would ever know.", "hu": "A nyitott padló a leggyorsabb, és semmiről nem vezet nyilvántartást. A belépőkártya és a kísérés minden látogatásnál időbe kerül, és az egyetlen ok, amiért valaha megtudnád."},
	"unlock.access.where": {"en": "OPS  /  FACILITY", "hu": "OPS  /  LÉTESÍTMÉNY"},
	"unlock.access.action": {"en": "Decide the policy", "hu": "Döntsd el a szabályt"},
	"unlock.compliance.kicker": {"en": "NEW SCRUTINY  /  CONTROLS", "hu": "ÚJ ELLENŐRZÉS  /  KONTROLLOK"},
	"unlock.compliance.title": {"en": "Somebody wants to see the paperwork.", "hu": "Valaki látni akarja a papírokat."},
	"unlock.compliance.body": {"en": "Eight controls, each answered by the live network rather than a checkbox. What you can prove is worth money to the customers who ask.", "hu": "Nyolc kontroll, mindegyikre az élő hálózat válaszol, nem egy pipa. Amit bizonyítani tudsz, az pénzt ér a kérdező ügyfeleknek."},
	"unlock.compliance.where": {"en": "OPS  /  RECORDS", "hu": "OPS  /  NYILVÁNTARTÁS"},
	"unlock.compliance.action": {"en": "Check readiness", "hu": "Ellenőrizd a készültséget"},
	"unlock.support.kicker": {"en": "NEW ROUTE  /  THE VENDOR", "hu": "ÚJ ÚT  /  A GYÁRTÓ"},
	"unlock.support.title": {"en": "This one is not yours to fix.", "hu": "Ezt nem te fogod megjavítani."},
	"unlock.support.body": {"en": "A defect no configuration touches needs a case: evidence, a wait the length of your cover, and somebody who has seen it before.", "hu": "Egy hibához, amit semmilyen beállítás nem érint, ügy kell: bizonyíték, a támogatásod hosszúságú várakozás, és valaki, aki már látta."},
	"unlock.support.where": {"en": "OPS  /  HARDWARE", "hu": "OPS  /  HARDVER"},
	"unlock.support.action": {"en": "Open the case", "hu": "Nyisd meg az ügyet"},
	"unlock.map.kicker": {"en": "NEW TOOL  /  WALL MAP", "hu": "ÚJ ESZKÖZ  /  FALITÉRKÉP"},
	"unlock.map.title": {"en": "The wall map is live.", "hu": "A falitérkép él."},
	"unlock.map.body": {"en": "One rack has become a network. Trace the path here before you crawl behind the cabinet.", "hu": "Egy rackből hálózat lett. Itt kövesd az utat, mielőtt a szekrény mögé másznál."},
	"unlock.map.where": {"en": "MAP  ·  TOP TOOLBAR", "hu": "TÉRKÉP  ·  FELSŐ ESZKÖZTÁR"},
	"unlock.map.action": {"en": "Open Map", "hu": "Térkép megnyitása"},
	"unlock.market.kicker": {"en": "NEW DESK  /  MARKET", "hu": "ÚJ ASZTAL  /  PIAC"},
	"unlock.market.title": {"en": "The tender board is open.", "hu": "A pályázati tábla nyitva."},
	"unlock.market.body": {"en": "Three clean jobs gave sales something to brag about. Qualify leads, price the risk, and choose who you work for.", "hu": "Három tiszta munka adott az értékesítésnek dicsekednivalót. Minősítsd az érdeklődőket, árazd be a kockázatot, és válaszd meg, kinek dolgozol."},
	"unlock.market.where": {"en": "COMPANY  /  MARKET", "hu": "CÉG  /  PIAC"},
	"unlock.market.action": {"en": "See the board", "hu": "Nézd meg a táblát"},
	"unlock.business.kicker": {"en": "NEW DESK  /  BUSINESS", "hu": "ÚJ ASZTAL  /  ÜZLET"},
	"unlock.business.title": {"en": "The books have arrived.", "hu": "Megérkeztek a könyvek."},
	"unlock.business.body": {"en": "A live customer turns blinking lights into invoices. Follow what was earned, billed, and actually paid.", "hu": "Egy élő ügyfél a villogó lámpákból számlát csinál. Kövesd, mit kerestél, mit számláztál, és mit fizettek ki valóban."},
	"unlock.business.where": {"en": "COMPANY  /  BUSINESS", "hu": "CÉG  /  ÜZLET"},
	"unlock.business.action": {"en": "Open the books", "hu": "Nyisd meg a könyveket"},
	"unlock.log.kicker": {"en": "NEW DESK  /  INCIDENT LOG", "hu": "ÚJ ASZTAL  /  INCIDENSNAPLÓ"},
	"unlock.log.title": {"en": "Start the incident clock.", "hu": "Indítsd az incidens óráját."},
	"unlock.log.body": {"en": "The first unhappy packet deserves a paper trail. Record what customers heard and what the room did.", "hu": "Az első boldogtalan csomag megérdemli a papírnyomot. Jegyezd fel, mit hallottak az ügyfelek és mit tett a szoba."},
	"unlock.log.where": {"en": "COMPANY  /  LOG", "hu": "CÉG  /  NAPLÓ"},
	"unlock.log.action": {"en": "Read the log", "hu": "Olvasd a naplót"},
	"unlock.ops.kicker": {"en": "NEW TOOL  /  OPERATIONS", "hu": "ÚJ ESZKÖZ  /  ÜZEMELTETÉS"},
	"unlock.ops.title": {"en": "You are on call now.", "hu": "Mostantól készenlétben vagy."},
	"unlock.ops.body": {"en": "A paying service needs more than hope. Watch capacity, monitors, spares, and the work waiting for a pair of hands.", "hu": "Egy fizető szolgáltatásnak több kell a reménynél. Figyeld a kapacitást, a figyelőket, a tartalékokat és a kezekre váró munkát."},
	"unlock.ops.where": {"en": "OPS  ·  TOP TOOLBAR", "hu": "OPS  ·  FELSŐ ESZKÖZTÁR"},
	"unlock.ops.action": {"en": "Open Ops", "hu": "Ops megnyitása"},
	"unlock.expand.kicker": {"en": "NEW OPTION  /  FACILITY", "hu": "ÚJ LEHETŐSÉG  /  LÉTESÍTMÉNY"},
	"unlock.expand.title": {"en": "The tape measure is out.", "hu": "Elő a mérőszalaggal."},
	"unlock.expand.body": {"en": "This corner has proved itself. The next room brings more floor, and puts power and cooling on your books.", "hu": "Ez a sarok bizonyított. A következő szoba több padlót hoz, és az áramot meg a hűtést a te könyveidre teszi."},
	"unlock.expand.where": {"en": "EXPAND  ·  TOP TOOLBAR", "hu": "BŐVÍTÉS  ·  FELSŐ ESZKÖZTÁR"},
	"unlock.expand.action": {"en": "Point it out", "hu": "Mutasd meg"},
	"brief.deliver": {"en": "DELIVER  /  {customer}", "hu": "SZÁLLÍTÁS  /  {customer}"},
	"brief.open_delivery": {"en": "Open customer delivery brief", "hu": "Ügyfél szállítási összefoglaló"},
	"brief.open": {"en": "Open the brief", "hu": "Összefoglaló megnyitása"},
	"brief.getting_started": {"en": "GETTING STARTED", "hu": "ELSŐ LÉPÉSEK"},
	"brief.step.rack": {"en": "Buy a rack: press R, click a floor tile", "hu": "Vegyél egy racket: R, majd kattints egy padlócsempére"},
	"brief.step.switch": {"en": "Click the rack, install a switch", "hu": "Kattints a rackre, szerelj be egy switchet"},
	"brief.step.servers": {"en": "Install two servers (Dill R110)", "hu": "Szerelj be két szervert (Dill R110)"},
	"brief.step.cable": {"en": "Cable both servers: click a port, Run cable", "hu": "Kábelezd be mindkét szervert: kattints egy portra, Kábel húzása"},
	"brief.step.collect": {"en": "Open Company > Jobs, collect 'Rack and stack'", "hu": "Nyisd meg: Cég > Munkák, vedd fel a 'Rack és beszerelés' munkát"},
	"brief.next_move": {"en": "YOUR NEXT MOVE", "hu": "A KÖVETKEZŐ LÉPÉSED"},
	"brief.hide.tip": {"en": "Hide this panel until the next job or outage (or click the objective line to bring it back)", "hu": "Elrejti a panelt a következő munkáig vagy kiesésig (vagy kattints a célsorra, és visszajön)"},
	"demo.first_night": {"en": "Your first night on the floor", "hu": "Az első éjszakád a padlón"},
	"demo.shift_complete": {"en": "Shift complete", "hu": "Műszak vége"},
	"demo.stay": {"en": "STAY ON THE FLOOR", "hu": "MARADJ A PADLÓN"},
	"demo.back": {"en": "RETURN TO TITLE", "hu": "VISSZA A CÍMKÉPERNYŐRE"},
	"demo.built.title": {"en": "YOU BUILT", "hu": "MEGÉPÍTETTED"},
	"demo.built.body": {"en": "Two switches, isolated tenants, a resilient core and two offices routed together.", "hu": "Két switch, elszigetelt bérlők, egy ellenálló mag és két, egymáshoz irányított iroda."},
	"demo.operated.title": {"en": "YOU OPERATED", "hu": "ÜZEMELTETTED"},
	"demo.operated.body": {"en": "Real MAC learning, VLAN tagging, spanning tree and longest-prefix routing.", "hu": "Valódi MAC-tanulás, VLAN-címkézés, feszítőfa és leghosszabb előtagú útválasztás."},
	"demo.next.title": {"en": "NEXT SHIFT", "hu": "KÖVETKEZŐ MŰSZAK"},
	"demo.next.body": {"en": "Own the room, and everything in it: the power bill, the crew, the customers who remember.", "hu": "Legyen tiéd a szoba, és minden, ami benne van: a villanyszámla, a csapat, az ügyfelek, akik emlékeznek."},
	"demo.beyond.0": {"en": "THE NETWORK  /  DHCP · DNS · NAT · BGP · OSPF · VRRP · MLAG · IPv6 · NAT64 · VXLAN · EVPN · WIREGUARD · 802.1X · MULTI-SITE WAN", "hu": "A HÁLÓZAT  /  DHCP · DNS · NAT · BGP · OSPF · VRRP · MLAG · IPv6 · NAT64 · VXLAN · EVPN · WIREGUARD · 802.1X · TÖBBTELEPHELYES WAN"},
	"demo.beyond.1": {"en": "THE BUSINESS  /  customers who remember how you treated them, rivals with grudges and favours, decisions whose bill arrives later", "hu": "AZ ÜZLET  /  ügyfelek, akik emlékeznek, hogyan bántál velük, riválisok sérelmekkel és szívességekkel, döntések, amelyek számlája később érkezik"},
	"demo.beyond.2": {"en": "THE BUILDING  /  power, cooling, filters, fire, water, badges, contractors, and the paperwork somebody eventually asks to see", "hu": "AZ ÉPÜLET  /  áram, hűtés, szűrők, tűz, víz, belépőkártyák, alvállalkozók, és a papírmunka, amit egyszer valaki látni akar"},
	"demo.beyond.3": {"en": "THE PEOPLE  /  a crew who copy your habits, standing duties, somebody carrying the phone at three in the morning, and who takes the blame when it was one of them", "hu": "AZ EMBEREK  /  egy csapat, amely a szokásaidat másolja, állandó feladatok, valaki, aki hajnali háromkor viszi a telefont, és hogy ki viszi el a balhét, ha egyikük volt"},
	"demo.beyond.4": {"en": "THE ROOMS  /  a second building with its own diary, its own fire protection and its own dock, and hardware that gets there on a van", "hu": "A SZOBÁK  /  egy második épület saját naptárral, saját tűzvédelemmel és saját rakodóval, és hardver, ami furgonnal érkezik"},
	"demo.beyond.5": {"en": "PROVING IT  /  a failover test you book, that takes the upstream away on purpose, and customers who ask for the result in writing", "hu": "BIZONYÍTÁS  /  egy átállási teszt, amit te foglalsz, ami szándékosan elviszi a felmenő kapcsolatot, és ügyfelek, akik írásban kérik az eredményt"},
	"demo.beyond.6": {"en": "THE RUN  /  it ends: sold, retired, or broke. It is scored, and something survives into the next one.", "hu": "A JÁTÉK  /  véget ér: eladva, nyugdíjba vonulva vagy csődben. Pontozzák, és valami átmegy a következőbe."},
	"iface.state.up": {"en": "UP / ENABLED", "hu": "ÉL / ENGEDÉLYEZVE"},
	"iface.state.admin_down": {"en": "ADMINISTRATIVELY DISABLED", "hu": "ADMINISZTRATÍVAN LETILTVA"},
	"iface.state.errdisabled": {"en": "ERR-DISABLED / PORT SECURITY", "hu": "HIBÁRA LETILTVA / PORTBIZTONSÁG"},
	"iface.state.down": {"en": "DOWN / {fault}", "hu": "NEM ÉL / {fault}"},
	"iface.access": {"en": "ACCESS  /  VLAN {vlan}", "hu": "ACCESS  /  VLAN {vlan}"},
	"iface.trunk": {"en": "TRUNK  /  {vlans}", "hu": "TRUNK  /  {vlans}"},
	"iface.all_vlans": {"en": "ALL VLANS", "hu": "MINDEN VLAN"},
	"iface.cable.none": {"en": "Cable: not connected", "hu": "Kábel: nincs bedugva"},
	"iface.cable.patch": {"en": "Physical patch:", "hu": "Fizikai patch:"},
	"iface.cable.open_rack": {"en": "Open rack elevation", "hu": "Rack nézet megnyitása"},
	"iface.cable.open_rack.tip": {"en": "Pull the fitted plug from its jack to repatch or unplug it", "hu": "Húzd ki a bedugott dugót az aljzatból az átkábelezéshez vagy kihúzáshoz"},
	"iface.cable.remote": {"en": "Remote link:", "hu": "Távoli kapcsolat:"},
	"iface.cable.disconnect": {"en": "Disconnect", "hu": "Bontás"},
	"iface.cable.disconnect.tip": {"en": "Remove this remote or circuit-backed link", "hu": "A távoli vagy áramkörre épülő kapcsolat eltávolítása"},
	"section.link_state": {"en": "LINK STATE", "hu": "KAPCSOLAT ÁLLAPOTA"},
	"section.frame_size": {"en": "FRAME SIZE", "hu": "KERETMÉRET"},
	"section.switching": {"en": "SWITCHING", "hu": "KAPCSOLÁS"},
	"section.ip_addresses": {"en": "IP ADDRESSES", "hu": "IP-CÍMEK"},
	"section.port_security": {"en": "PORT SECURITY", "hu": "PORTBIZTONSÁG"},
	"ops.title": {"en": "Network operations", "hu": "Hálózatüzemeltetés"},
	"ops.metric.devices": {"en": "DEVICES", "hu": "ESZKÖZÖK"},
	"ops.metric.links": {"en": "CABLE PLANT", "hu": "KÁBELEZÉS"},
	"ops.metric.alerts": {"en": "ATTENTION", "hu": "FIGYELEM"},
	"ops.metric.power": {"en": "LIVE DRAW", "hu": "AKTUÁLIS FOGYASZTÁS"},
	"ops.tab.capacity": {"en": "Capacity", "hu": "Kapacitás"},
	"ops.tab.traffic": {"en": "Traffic", "hu": "Forgalom"},
	"ops.tab.hardware": {"en": "Hardware", "hu": "Hardver"},
	"ops.tab.facility": {"en": "Facility", "hu": "Létesítmény"},
	"ops.tab.automation": {"en": "Automation", "hu": "Automatizálás"},
	"ops.tab.records": {"en": "Records", "hu": "Nyilvántartás"},
	"ops.tab.board": {"en": "Board", "hu": "Igazgatóság"},
	"section.a_visit_is_booked": {"en": "A VISIT IS BOOKED", "hu": "LÁTOGATÁS FOGLALVA"},
	"section.active_deals": {"en": "ACTIVE DEALS", "hu": "ÉLŐ SZERZŐDÉSEK"},
	"section.address_space": {"en": "ADDRESS SPACE", "hu": "CÍMTARTOMÁNY"},
	"section.airflow": {"en": "AIRFLOW", "hu": "LÉGÁRAMLÁS"},
	"section.an_approach": {"en": "AN APPROACH", "hu": "EGY MEGKÖZELÍTÉS"},
	"section.assets_and_spares": {"en": "ASSETS AND SPARES", "hu": "ESZKÖZÖK ÉS TARTALÉKOK"},
	"section.audit_readiness": {"en": "AUDIT READINESS", "hu": "AUDITKÉSZÜLTSÉG"},
	"section.bid_desk_incoming_opportunities": {"en": "BID DESK  /  INCOMING OPPORTUNITIES", "hu": "AJÁNLATOK  /  BEÉRKEZŐ LEHETŐSÉGEK"},
	"section.campaign": {"en": "CAMPAIGN", "hu": "KAMPÁNY"},
	"section.capacity": {"en": "CAPACITY", "hu": "KAPACITÁS"},
	"section.career_profile": {"en": "CAREER PROFILE", "hu": "PÁLYAPROFIL"},
	"section.certificates": {"en": "CERTIFICATES", "hu": "TANÚSÍTVÁNYOK"},
	"section.change_management": {"en": "CHANGE MANAGEMENT", "hu": "VÁLTOZÁSKEZELÉS"},
	"section.chapter_index": {"en": "CHAPTER INDEX", "hu": "FEJEZETEK"},
	"section.client_ask": {"en": "CLIENT ASK", "hu": "ÜGYFÉLKÉRÉS"},
	"section.customer_window_what_your_network_is_carrying": {"en": "CUSTOMER WINDOW  /  WHAT YOUR NETWORK IS CARRYING", "hu": "ÜGYFÉLABLAK  /  MIT VISZ A HÁLÓZATOD"},
	"section.decisions": {"en": "DECISIONS", "hu": "DÖNTÉSEK"},
	"section.defence": {"en": "DEFENCE", "hu": "VÉDELEM"},
	"section.devices": {"en": "DEVICES", "hu": "ESZKÖZÖK"},
	"section.documentation": {"en": "DOCUMENTATION", "hu": "DOKUMENTÁCIÓ"},
	"section.energy_and_the_books": {"en": "ENERGY AND THE BOOKS", "hu": "ENERGIA ÉS A KÖNYVELÉS"},
	"section.event_log": {"en": "EVENT LOG", "hu": "ESEMÉNYNAPLÓ"},
	"section.facility_schedule": {"en": "FACILITY SCHEDULE", "hu": "LÉTESÍTMÉNYI ÜTEMTERV"},
	"section.failover_test": {"en": "FAILOVER TEST", "hu": "ÁTÁLLÁSI TESZT"},
	"section.field_manual_reference": {"en": "FIELD MANUAL  /  REFERENCE", "hu": "KÉZIKÖNYV  /  REFERENCIA"},
	"section.fire_smoke_and_water": {"en": "FIRE, SMOKE AND WATER", "hu": "TŰZ, FÜST ÉS VÍZ"},
	"section.history": {"en": "HISTORY", "hu": "ELŐZMÉNYEK"},
	"section.how_the_place_is_trending": {"en": "HOW THE PLACE IS TRENDING", "hu": "MERRE TART A HELY"},
	"section.how_this_run_ended": {"en": "HOW THIS RUN ENDED", "hu": "HOGY VÉGZŐDÖTT EZ A JÁTÉK"},
	"section.incident_timeline": {"en": "INCIDENT TIMELINE", "hu": "INCIDENS IDŐVONAL"},
	"section.incidents_awaiting_a_post_mortem": {"en": "INCIDENTS AWAITING A POST-MORTEM", "hu": "KIÉRTÉKELÉSRE VÁRÓ INCIDENSEK"},
	"section.job_complete_proof_of_work": {"en": "JOB COMPLETE  /  PROOF OF WORK", "hu": "MUNKA KÉSZ  /  A MUNKA BIZONYÍTÉKA"},
	"section.live_estate_current_shift": {"en": "LIVE ESTATE  /  CURRENT SHIFT", "hu": "ÉLŐ ÁLLOMÁNY  /  AKTUÁLIS MŰSZAK"},
	"section.live_solution_snapshot": {"en": "LIVE SOLUTION SNAPSHOT", "hu": "ÉLŐ MEGOLDÁS PILLANATKÉPE"},
	"section.marketing_and_cover": {"en": "MARKETING AND COVER", "hu": "MARKETING ÉS BIZTOSÍTÁS"},
	"section.monitors": {"en": "MONITORS", "hu": "FIGYELŐK"},
	"section.nobody_claims_these": {"en": "NOBODY CLAIMS THESE", "hu": "EZEKET SENKI SEM VÁLLALJA"},
	"section.opening_arc_network_online_handover_ready": {"en": "OPENING ARC  /  NETWORK ONLINE  /  HANDOVER READY", "hu": "NYITÁNY  /  HÁLÓZAT ÉL  /  ÁTADÁSRA KÉSZ"},
	"section.pipeline": {"en": "PIPELINE", "hu": "ÉRDEKLŐDŐK"},
	"section.playbooks": {"en": "PLAYBOOKS", "hu": "FORGATÓKÖNYVEK"},
	"section.port_inspector_read_only_logical_state": {"en": "PORT INSPECTOR  /  READ-ONLY LOGICAL STATE", "hu": "PORTVIZSGÁLÓ  /  CSAK OLVASHATÓ LOGIKAI ÁLLAPOT"},
	"section.power": {"en": "POWER", "hu": "TÁP"},
	"section.quarterly_reports": {"en": "QUARTERLY REPORTS", "hu": "NEGYEDÉVES JELENTÉSEK"},
	"section.receivables": {"en": "RECEIVABLES", "hu": "KÖVETELÉSEK"},
	"section.receiving": {"en": "RECEIVING", "hu": "ÁRUÁTVÉTEL"},
	"section.renewals_calendar": {"en": "RENEWALS CALENDAR", "hu": "MEGÚJÍTÁSI NAPTÁR"},
	"section.runbooks_and_automation": {"en": "RUNBOOKS AND AUTOMATION", "hu": "RUNBOOKOK ÉS AUTOMATIZÁLÁS"},
	"section.runs_before_this_one": {"en": "RUNS BEFORE THIS ONE", "hu": "KORÁBBI JÁTÉKOK"},
	"section.sites": {"en": "SITES", "hu": "TELEPHELYEK"},
	"section.somebody_else_s_outage": {"en": "SOMEBODY ELSE'S OUTAGE", "hu": "VALAKI MÁS KIESÉSE"},
	"section.staff": {"en": "STAFF", "hu": "SZEMÉLYZET"},
	"section.standing_duties": {"en": "STANDING DUTIES", "hu": "ÁLLANDÓ FELADATOK"},
	"section.status_page": {"en": "STATUS PAGE", "hu": "ÁLLAPOTOLDAL"},
	"section.the_competition": {"en": "THE COMPETITION", "hu": "A VERSENYTÁRSAK"},
	"section.the_parts_drawer": {"en": "THE PARTS DRAWER", "hu": "AZ ALKATRÉSZFIÓK"},
	"section.this_quarter_s_targets": {"en": "THIS QUARTER'S TARGETS", "hu": "E NEGYEDÉV CÉLJAI"},
	"section.tickets": {"en": "TICKETS", "hu": "HIBAJEGYEK"},
	"section.top_talkers": {"en": "TOP TALKERS", "hu": "LEGNAGYOBB FORGALMÚAK"},
	"section.transit_and_peering": {"en": "TRANSIT AND PEERING", "hu": "TRANZIT ÉS PEERING"},
	"section.unreachable": {"en": "UNREACHABLE", "hu": "ELÉRHETETLEN"},
	"section.vendor_support": {"en": "VENDOR SUPPORT", "hu": "GYÁRTÓI TÁMOGATÁS"},
	"section.wan_circuits": {"en": "WAN CIRCUITS", "hu": "WAN ÁRAMKÖRÖK"},
	"section.what_kind_of_company_this_is": {"en": "WHAT KIND OF COMPANY THIS IS", "hu": "MILYEN CÉG EZ"},
	"section.what_you_wrote_about_these": {"en": "WHAT YOU WROTE ABOUT THESE", "hu": "AMIT EZEKRŐL ÍRTÁL"},
	"section.who_is_on_the_floor": {"en": "WHO IS ON THE FLOOR", "hu": "KI VAN A PADLÓN"},
	"section.practice": {"en": "PRACTICE", "hu": "GYAKORLÁS"},
	"section.share_and_export": {"en": "SHARE AND EXPORT", "hu": "MEGOSZTÁS ÉS EXPORT"},
	"company.title": {"en": "Customers and company", "hu": "Ügyfelek és cég"},
	"company.tab.jobs": {"en": "Jobs", "hu": "Munkák"},
	"company.tab.business": {"en": "Business", "hu": "Üzlet"},
	"company.tab.market": {"en": "Market", "hu": "Piac"},
	"company.tab.log": {"en": "Log", "hu": "Napló"},
	"company.flow.section": {"en": "LAST CYCLE  /  BUSINESS FLOW", "hu": "UTOLSÓ CIKLUS  /  PÉNZÁRAMLÁS"},
	"company.flow.body": {"en": "Revenue is what the network earned. An invoice makes it receivable; collection is when cash reaches the bank. Power and transit leave immediately.", "hu": "A bevétel az, amit a hálózat megkeresett. A számla követeléssé teszi; a beszedés az, amikor a pénz a bankba ér. Az áram és a tranzit azonnal távozik."},
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
	"service.first_standard": {"en": "The first standard is a local LAN: one SW5 or S8 and two to four R110 servers, in one VLAN. Routes and application services stay manual.", "hu": "Az első szabvány egy helyi LAN: egy SW5 vagy S8 és két-négy R110 szerver, egy VLAN-ban. Az útvonalak és az alkalmazásszolgáltatások kézi tervezésűek maradnak."},
	"toast.plug_reseated": {"en": "Plug reseated: %s %s.", "hu": "Csatlakozó visszadugva: %s %s."},
	"toast.cable_run": {"en": "Cable run: %s %s ⇄ %s %s", "hu": "Kábel kihúzva: %s %s ⇄ %s %s"},
	"toast.unplugged": {"en": "Unplugged %s %s from %s %s.", "hu": "Kihúzva: %s %s innen: %s %s."},
	"toast.drop_free_port": {"en": "Drop the cable on a free port in this rack.", "hu": "Ejtsd a kábelt egy szabad portra ebben a rackben."},
	"toast.not_enough_money": {"en": "Not enough available for a %s ($%d, cash and protected delivery funds total $%d).", "hu": "Nincs elég pénz egy %s vásárlásához (%d $, a készpénz és a védett szállítási keret együtt %d $)."},
	"toast.saved_template": {"en": "Saved '%s standard' as a template.", "hu": "'%s szabvány' sablonként elmentve."},
	"toast.confirmed_commit": {"en": "Confirmed commit %s on %s.", "hu": "Megerősített commit: %s, eszköz: %s."},
	"toast.decommissioned": {"en": "Decommissioned for $%d.%s", "hu": "Leszerelve %d $ értékben.%s"},
	"toast.renamed": {"en": "Renamed %s to %s.", "hu": "%s átnevezve erre: %s."},
	"device.console_note": {"en": "Addressing, VLANs, MTU and policy are configured at the device console.", "hu": "A címzést, a VLAN-okat, az MTU-t és a szabályokat az eszköz konzolján állítod be."},
	"toast.no_free_ports": {"en": "No free ports anywhere to run a cable to.", "hu": "Sehol sincs szabad port, ahová kábelt húzhatnál."},
	"toast.close_panel_find": {"en": "Close the open panel first (Esc), then Find.", "hu": "Először zárd be a nyitott panelt (Esc), aztán jöhet a Keresés."},
	"toast.report_clipboard": {"en": "The report is on your clipboard.", "hu": "A jelentés a vágólapodon van."},
	"toast.dry_run": {"en": "Dry run: %d planned, %d would be skipped.", "hu": "Próbafutás: %d tervezett, %d maradna ki."},
	"toast.playbook_ran": {"en": "Ran '%s' on %d device(s), %d with errors.", "hu": "'%s' lefutott %d eszközön, %d hibával."},
	"toast.close_panel_ops": {"en": "Close the open panel first (Esc), then Ops.", "hu": "Először zárd be a nyitott panelt (Esc), aztán jöhet az Üzemeltetés."},
	"toast.damaged_slot": {"en": "Slot %d holds a damaged save. Delete it from the title screen before reusing it.", "hu": "A(z) %d. hely sérült mentést tartalmaz. Töröld a címképernyőn, mielőtt újra használnád."},
	"toast.saved_slot": {"en": "Saved to slot %d.", "hu": "Mentve a(z) %d. helyre."},
	"toast.finish_drill_first": {"en": "Finish or abandon the drill first.", "hu": "Először fejezd be vagy add fel a gyakorlatot."},
	"toast.sandbox_mode": {"en": "Sandbox mode %s.", "hu": "Homokozó mód: %s."},
	"toast.setting_applied": {"en": "Setting applied.", "hu": "Beállítás alkalmazva."},
	"toast.difficulty_set": {"en": "Difficulty set to %s: fault rate, prices and cycle length change from now. The bank balance stays, and the run is scored at the preset it started on.", "hu": "Nehézség beállítva: %s. A hibaarány, az árak és a ciklushossz mostantól változik. A bankegyenleg marad, és a játék az induló nehézségen kap pontszámot."},
	"toast.question_copied": {"en": "Copied. Paste it to whoever you are asking.", "hu": "Kimásolva. Illeszd be annak, akitől kérdezel."},
	"toast.fix_copied": {"en": "Your fix is on the clipboard. Send it back.", "hu": "A javításod a vágólapon van. Küldd vissza."},
	"toast.answer_read": {"en": "Read %d line(s) of answer into the log.", "hu": "%d sornyi válasz beolvasva a naplóba."},
	"toast.back_home": {"en": "Back in your own datacenter.", "hu": "Újra a saját adatközpontodban."},
	"toast.topology_exported": {"en": "Topology exported and copied to the clipboard.", "hu": "A topológia exportálva és a vágólapra másolva."},
	"toast.lab_written": {"en": "Lab written to %s and the topology copied.", "hu": "A labor ide íródott: %s, a topológia kimásolva."},
	"toast.code_copied": {"en": "Code copied. The same code builds the same network.", "hu": "Kód kimásolva. Ugyanaz a kód ugyanazt a hálózatot építi."},
	"toast.scored": {"en": "Scored %d. The card is on your clipboard.", "hu": "Pontszám: %d. A kártya a vágólapodon van."},
	"toast.scenario_passed": {"en": "Scenario passed: %s", "hu": "Forgatókönyv teljesítve: %s"},
	"drill.floors": {"en": "This network is on %d floors: %s. The switcher in the toolbar moves between them.", "hu": "Ez a hálózat %d szinten van: %s. Az eszköztár váltójával lépkedhetsz köztük."},
	"drill.broken": {"en": "Something is broken. Restore connectivity between:", "hu": "Valami elromlott. Állítsd helyre a kapcsolatot ezek között:"},
	"drill.press_check": {"en": "Press Check when you believe it is fixed.", "hu": "Nyomd meg az Ellenőrzést, ha úgy gondolod, kijavítottad."},
	"toast.close_panel_map": {"en": "Close the open panel first (Esc), then the map.", "hu": "Először zárd be a nyitott panelt (Esc), aztán jöhet a térkép."},
	"toast.map_locked": {"en": "The network map unlocks after the first rack is physically delivered.", "hu": "A hálózati térkép az első rack tényleges kiszállítása után nyílik meg."},
	"tutorial.promise_sold": {"en": "Promise sold: %s", "hu": "Eladott ígéret: %s"},
	"tutorial.post_now": {"en": "Posting now makes the reputation loss visible and smaller: −2 instead of −4 per outage cycle.", "hu": "Ha most posztolsz, a hírnévveszteség látható és kisebb lesz: kiesési ciklusonként −2 a −4 helyett."},
	"toast.first_outage_closed": {"en": "First outage closed. The network is stronger for it.", "hu": "Az első kiesés lezárva. A hálózat erősebb lett tőle."},
	"finale.empty_cage": {"en": "You walked into an empty cage. You leave behind a routed, redundant tenant network, and every packet reached its destination for a real reason.", "hu": "Egy üres ketrecbe léptél be. Egy routolt, redundáns bérlői hálózatot hagysz magad után, és minden csomag valódi okból ért célba."},
	"business.reference": {"en": "Willing to be a reference: %s. Customers who have been happy for a long time are worth more than any advertising.", "hu": "Referenciának vállalkozik: %s. A régóta elégedett ügyfelek többet érnek bármilyen reklámnál."},
	"business.no_intel": {"en": "You have no read on competitor pricing yet: lose a bid and you will learn.", "hu": "Még nem látsz rá a versenytársak áraira: veszíts el egy pályázatot, és tanulsz."},
	"business.intel": {"en": "Market intelligence from %d observed bid(s).", "hu": "Piaci ismeret %d megfigyelt ajánlatból."},
	"business.sold_company": {"en": "You sold the company. Everything still runs, and none of it is yours.", "hu": "Eladtad a céget. Minden működik tovább, de semmi sem a tiéd."},
	"market.word_is": {"en": "Word is: %s. Nobody has asked them what they actually need yet.", "hu": "Azt beszélik: %s. Még senki sem kérdezte meg, mire van valójában szükségük."},
	"market.expires": {"en": "Expires in %d cycle(s).", "hu": "%d ciklus múlva lejár."},
	"market.they_want": {"en": "They want: %s.", "hu": "Ezt akarják: %s."},
	"market.tender_closes": {"en": "Tender closes in %d cycle(s).", "hu": "A pályázat %d ciklus múlva zárul."},
	"market.your_price": {"en": "Your price:  $", "hu": "Az árad ($):  "},
	"log.nothing_yet": {"en": "Nothing has happened yet.", "hu": "Még semmi sem történt."},
	"toast.pack_details": {"en": "Pack details are in the log.", "hu": "A csomag részletei a naplóban vannak."},
	"toast.diagnostics_copied": {"en": "Diagnostics copied to the clipboard.", "hu": "Diagnosztika a vágólapra másolva."},
	"toast.not_saved_drill": {"en": "Not saved: a drill is running. Finish or abandon it first.", "hu": "Nincs mentve: gyakorlat fut. Előbb fejezd be vagy add fel."},
	"toast.not_saved_puzzle": {"en": "Not saved: a puzzle is open. Close it to get your own world back first.", "hu": "Nincs mentve: egy feladvány van nyitva. Zárd be, hogy visszakapd a saját világodat."},
	"toast.saved_to": {"en": "Saved to %s at %s.", "hu": "Mentve ide: %s, ekkor: %s."},
	"demo.needs": {"en": "Needs: %s  ($%d)", "hu": "Szükséges: %s  (%d $)"},
	"toast.not_yet": {"en": "Not yet: %s", "hu": "Még nem: %s"},
	"demo.finished": {"en": "The demo arc is finished. The full game carries on from here.", "hu": "A demó íve véget ért. A teljes játék innen folytatódik."},
	"btn.got_it": {"en": "Got it", "hu": "Értem"},
	"btn.customers": {"en": "Customers", "hu": "Ügyfelek"},
	"btn.field_manual": {"en": "Field manual", "hu": "Kézikönyv"},
	"btn.find_anything": {"en": "Find anything", "hu": "Keress bármit"},
	"btn.floor": {"en": "Floor", "hu": "Szint"},
	"btn.build_rack": {"en": "Build a rack", "hu": "Rack építése"},
	"btn.close_esc": {"en": "Close  ·  Esc", "hu": "Bezárás  ·  Esc"},
	"btn.rack_named": {"en": "Rack %s", "hu": "%s rack"},
	"btn.packets": {"en": "Packets ⇅", "hu": "Csomagok ⇅"},
	"btn.save_config": {"en": "Save config", "hu": "Konfiguráció mentése"},
	"btn.arm_confirmed_commit": {"en": "Arm confirmed commit", "hu": "Megerősítendő commit élesítése"},
	"btn.send_other_floor": {"en": "Send to another floor…", "hu": "Küldés másik szintre…"},
	"btn.decommission": {"en": "Decommission…", "hu": "Leszerelés…"},
	"btn.remote_hands": {"en": "Remote hands…", "hu": "Helyszíni segítség…"},
	"btn.physical_work": {"en": "Physical work…", "hu": "Fizikai munka…"},
	"btn.go_other_end": {"en": "Go to other end ⇄", "hu": "Ugrás a túloldalra ⇄"},
	"btn.run_cable": {"en": "Run cable…", "hu": "Kábel húzása…"},
	"btn.network_operations": {"en": "Network operations", "hu": "Hálózatüzemeltetés"},
	"btn.crew_short_notice": {"en": "Bring in a crew at short notice ($600)", "hu": "Csapat behívása rövid határidővel (600 $)"},
	"btn.walk_to_rack": {"en": "Walk to the rack", "hu": "Séta a rackhez"},
	"btn.confirm": {"en": "Confirm", "hu": "Megerősítés"},
	"btn.walk_and_write": {"en": "Walk it and write it up ($30)", "hu": "Bejárás és jegyzőkönyv (30 $)"},
	"btn.investigate": {"en": "Investigate ($50)", "hu": "Kivizsgálás (50 $)"},
	"btn.turn_off": {"en": "Turn it off", "hu": "Kikapcsolás"},
	"btn.buy_model": {"en": "Buy %s ($%d)", "hu": "%s vásárlása (%d $)"},
	"btn.open_case_against": {"en": "Open a case against %s", "hu": "Ügy nyitása: %s"},
	"btn.send_to": {"en": "Send %s", "hu": "%s küldése"},
	"btn.attach_bundle": {"en": "Attach a tech-support bundle", "hu": "Tech-support csomag csatolása"},
	"btn.take_back": {"en": "Take it back", "hu": "Visszavonás"},
	"btn.escalate": {"en": "Escalate ($200)", "hu": "Eszkaláció (200 $)"},
	"btn.load_fixed_image": {"en": "Load the fixed image", "hu": "Javított image betöltése"},
	"btn.renew": {"en": "Renew", "hu": "Megújítás"},
	"btn.manual": {"en": "Manual", "hu": "Kézikönyv"},
	"btn.copy_report": {"en": "Copy the report", "hu": "Jelentés másolása"},
	"btn.second_company": {"en": "Start the second company  (%s)", "hu": "Második cég indítása  (%s)"},
	"btn.retire": {"en": "Retire at the top", "hu": "Visszavonulás a csúcson"},
	"btn.clear_history": {"en": "Clear the history", "hu": "Előzmények törlése"},
	"btn.be_this": {"en": "Be this", "hu": "Legyen ez"},
	"btn.rebrand": {"en": "Rebrand ($5000 and some standing)…", "hu": "Márkaváltás (5000 $ és némi tekintély)…"},
	"btn.cameras": {"en": "Put cameras in ($1200)", "hu": "Kamerák beszerelése (1200 $)"},
	"btn.get_somebody": {"en": "Get somebody in ($%d)", "hu": "Hívj valakit (%d $)"},
	"btn.cancel_it": {"en": "Cancel it", "hu": "Lemondás"},
	"btn.book_failover": {"en": "Book a failover test", "hu": "Átállási teszt foglalása"},
	"btn.do_it_cost": {"en": "Do it ($%d)", "hu": "Csináld (%d $)"},
	"btn.delegate": {"en": "Delegate", "hu": "Delegálás"},
	"btn.reset_counters": {"en": "Reset the counters", "hu": "Számlálók nullázása"},
	"btn.install_ups": {"en": "Install a UPS on this floor  ($%d)", "hu": "UPS telepítése erre a szintre  (%d $)"},
	"btn.reverify": {"en": "Ask them to re-verify", "hu": "Kérj újraellenőrzést"},
	"btn.stock_up": {"en": "Stock up…", "hu": "Készletezés…"},
	"btn.order_by_hand": {"en": "Order by hand", "hu": "Kézi rendelés"},
	"btn.cabling_expedient": {"en": "Cabling: expedient", "hu": "Kábelezés: rögtönzött"},
	"btn.redo_leads": {"en": "Redo the improvised leads (%d)", "hu": "Rögtönzött kábelek cseréje (%d)"},
	"btn.order_hardware": {"en": "Order hardware…", "hu": "Hardver rendelése…"},
	"btn.check_order": {"en": "Check against the order", "hu": "Egyeztetés a rendeléssel"},
	"btn.unpack": {"en": "Unpack", "hu": "Kicsomagolás"},
	"btn.take_out": {"en": "Take it out", "hu": "Kivétel"},
	"btn.buy_spare": {"en": "Buy a spare…", "hu": "Tartalék vásárlása…"},
	"btn.swap_spares": {"en": "Swap from spares", "hu": "Csere tartalékból"},
	"btn.rma": {"en": "Send it back (RMA)", "hu": "Visszaküldés (RMA)"},
	"btn.new_runbook": {"en": "New runbook…", "hu": "Új runbook…"},
	"btn.dry_run": {"en": "Dry run", "hu": "Próbafutás"},
	"btn.run_it": {"en": "Run it", "hu": "Futtatás"},
	"btn.bind_alert": {"en": "Bind to an alert…", "hu": "Riasztáshoz kötés…"},
	"btn.roll_back": {"en": "Roll back", "hu": "Visszaállítás"},
	"btn.run_on": {"en": "Run on…", "hu": "Futtatás ezen…"},
	"btn.delete": {"en": "Delete", "hu": "Törlés"},
	"btn.save_playbook": {"en": "Save playbook", "hu": "Playbook mentése"},
	"btn.remove": {"en": "Remove", "hu": "Eltávolítás"},
	"btn.add_check": {"en": "Add a check…", "hu": "Ellenőrzés hozzáadása…"},
	"btn.packet_empire": {"en": "Packet Empire", "hu": "Packet Empire"},
	"btn.hand_fault": {"en": "Hand somebody this fault…", "hu": "Add át valakinek ezt a hibát…"},
	"btn.incident_drill": {"en": "Incident drill  (+$%d)", "hu": "Incidensgyakorlat  (+%d $)"},
	"btn.content_workshop": {"en": "Content workshop  (%d pack(s))", "hu": "Tartalomműhely  (%d csomag)"},
	"btn.export_topology": {"en": "Export the topology", "hu": "Topológia exportálása"},
	"btn.export_clab": {"en": "Export to containerlab", "hu": "Export containerlabba"},
	"btn.challenge_code": {"en": "Challenge code", "hu": "Kihíváskód"},
	"btn.show_approach": {"en": "Stuck? Show me the approach", "hu": "Elakadtál? Mutasd a megközelítést"},
	"btn.check": {"en": "Check", "hu": "Ellenőrzés"},
	"btn.leave_scenario": {"en": "Leave scenario", "hu": "Kilépés a forgatókönyvből"},
	"btn.abandon_reveal": {"en": "Abandon (reveal faults)", "hu": "Feladás (hibák felfedése)"},
	"btn.open_ledger": {"en": "Open the business ledger", "hu": "Üzleti főkönyv megnyitása"},
	"btn.keep_operating_customer": {"en": "Keep operating this customer", "hu": "Ügyfél további üzemeltetése"},
	"btn.ack_incident": {"en": "Acknowledge incident", "hu": "Incidens nyugtázása"},
	"btn.open_status_page": {"en": "Open status page", "hu": "Státuszoldal megnyitása"},
	"btn.inspect_service_network": {"en": "Inspect the service network", "hu": "Szolgáltatási hálózat vizsgálata"},
	"btn.restore_with_help": {"en": "Restore with help", "hu": "Helyreállítás segítséggel"},
	"btn.open_affected_port": {"en": "Open affected port", "hu": "Érintett port megnyitása"},
	"btn.teaching_restore": {"en": "Use teaching restore point", "hu": "Oktató visszaállítási pont használata"},
	"btn.review_harden": {"en": "Review and harden", "hu": "Átnézés és megerősítés"},
	"finale.intro": {"en": "Six contracts. One tired colo cage. About half an hour to prove you can turn cheap hardware into a network people trust.", "hu": "Hat szerződés. Egy fáradt colo ketrec. Nagyjából fél óra, hogy bizonyítsd: olcsó hardverből is építhető hálózat, amiben megbíznak."},
	"btn.chase": {"en": "Chase", "hu": "Sürgetés"},
	"btn.spot_tariff": {"en": "Switch to a spot tariff", "hu": "Váltás spot tarifára"},
	"btn.efficiency_retrofit": {"en": "Efficiency retrofit  ($%d)", "hu": "Hatékonysági korszerűsítés  (%d $)"},
	"btn.dismiss_accountant": {"en": "Dismiss the accountant", "hu": "Könyvelő elbocsátása"},
	"btn.buy_slash29": {"en": "Buy another /29  ($%d)", "hu": "Még egy /29 vásárlása  (%d $)"},
	"btn.approach_peer": {"en": "Approach another network to peer with", "hu": "Keress másik hálózatot peeringre"},
	"btn.ix_port": {"en": "Take a port at the internet exchange  ($%d, then $%d/cycle)", "hu": "Port az internetcserepontnál  (%d $, majd %d $/ciklus)"},
	"btn.borrow": {"en": "Borrow $%d", "hu": "%d $ felvétele"},
	"btn.repay": {"en": "Repay $%d", "hu": "%d $ törlesztése"},
	"btn.spend_more": {"en": "Spend more", "hu": "Költs többet"},
	"btn.cut_back": {"en": "Cut back", "hu": "Visszafogás"},
	"btn.take_cover": {"en": "Take cover", "hu": "Fedezékbe"},
	"btn.declare_window": {"en": "Declare a window", "hu": "Karbantartási ablak kihirdetése"},
	"btn.close_out": {"en": "Close it out", "hu": "Lezárás"},
	"btn.abort_revert": {"en": "Abort and revert", "hu": "Megszakítás és visszaállítás"},
	"btn.push_past_rollback": {"en": "Push on past the rollback point", "hu": "Tovább a visszaállítási ponton túl"},
	"btn.submit_change_plan": {"en": "Submit a change plan…", "hu": "Változtatási terv benyújtása…"},
	"btn.enable": {"en": "Enable", "hu": "Engedélyezés"},
	"btn.call_somebody_out": {"en": "Call somebody out ($%d)", "hu": "Hívj ki valakit (%d $)"},
	"btn.raise": {"en": "Raise", "hu": "Emelés"},
	"btn.train": {"en": "Train…", "hu": "Képzés…"},
	"btn.let_go": {"en": "Let go", "hu": "Elbocsátás"},
	"btn.hire_someone": {"en": "Hire someone…   (payroll $%d/cycle against $%d/cycle coming in)", "hu": "Felvétel…   (bérköltség %d $/ciklus, bevétel %d $/ciklus)"},
	"btn.lease_site": {"en": "Lease another site…", "hu": "Újabb telephely bérlése…"},
	"btn.cancel": {"en": "Cancel", "hu": "Mégse"},
	"btn.order_circuit": {"en": "Order a circuit…", "hu": "Vonal rendelése…"},
	"btn.sell_company": {"en": "Sell the company", "hu": "Cég eladása"},
	"btn.turn_down": {"en": "Turn them down", "hu": "Elutasítás"},
	"btn.go_see_them": {"en": "Go and see them  ($%d)", "hu": "Látogasd meg őket  (%d $)"},
	"btn.submit_proposal": {"en": "Submit the proposal", "hu": "Ajánlat benyújtása"},
	"btn.acquire": {"en": "Acquire", "hu": "Felvásárlás"},
	"btn.read_it": {"en": "Read it", "hu": "Elolvasom"},
	"btn.open_case": {"en": "Open a case", "hu": "Ügy nyitása"},
	"btn.triage": {"en": "Triage…", "hu": "Osztályozás…"},
	"btn.close_it": {"en": "Close it", "hu": "Lezárás"},
	"btn.post_update": {"en": "Post update", "hu": "Frissítés közzététele"},
	"btn.replay": {"en": "Replay", "hu": "Visszajátszás"},
	"btn.write_up": {"en": "Write it up", "hu": "Jegyzőkönyv írása"},
	"btn.waits_morning": {"en": "It waits until morning", "hu": "Reggelig várhat"},
	"btn.accept_per_cycle": {"en": "Accept $%d/cycle", "hu": "Elfogadás: %d $/ciklus"},
	"btn.walk_away": {"en": "Walk away", "hu": "Elsétálok"},
	"btn.send_quote": {"en": "Send quote", "hu": "Árajánlat küldése"},
	"btn.decline": {"en": "Decline", "hu": "Elutasítás"},
	"btn.keep": {"en": "Keep", "hu": "Megtartás"},
	"btn.put_in_writing": {"en": "Put it in writing", "hu": "Írásba foglalás"},
	"btn.their_way": {"en": "Do it their way", "hu": "Legyen az ő módjukon"},
	"btn.hold_firm": {"en": "Hold firm", "hu": "Kitartás"},
	"btn.take_it": {"en": "Take it", "hu": "Elfogadom"},
	"btn.let_end": {"en": "Let it end", "hu": "Hadd járjon le"},
	"btn.check_integration": {"en": "Check integration & collect $1500", "hu": "Integráció ellenőrzése és 1500 $ felvétele"},
	"btn.check_mastery": {"en": "Check mastery", "hu": "Tudás ellenőrzése"},
	"btn.continue_operating": {"en": "Continue operating", "hu": "Üzemeltetés folytatása"},
	"btn.show_commands": {"en": "Stuck? Show me the commands", "hu": "Elakadtál? Mutasd a parancsokat"},
	"btn.check_requirements": {"en": "Check requirements & collect", "hu": "Követelmények ellenőrzése és felvétel"},
	"btn.site_visit": {"en": "Site visit ($350)", "hu": "Helyszíni látogatás (350 $)"},
	"btn.hand_to_team": {"en": "Hand it to the team", "hu": "Átadás a csapatnak"},
	"btn.assign": {"en": "Assign…", "hu": "Kiosztás…"},
	"btn.auto": {"en": "Auto", "hu": "Automatikus"},
	"btn.on_schedule": {"en": "On schedule", "hu": "Ütemezve"},
	"btn.standing_order": {"en": "Standing order", "hu": "Állandó rendelés"},
	"btn.cabling_documented": {"en": "Cabling: documented", "hu": "Kábelezés: dokumentált"},
	"btn.disable": {"en": "Disable", "hu": "Letiltás"},
	"btn.chase_case": {"en": "Chase the case", "hu": "Ügy sürgetése"},
	"btn.collect": {"en": "Collect $%d", "hu": "%d $ felvétele"},
	"tip.incidents": {"en": "Service interrupted. Open incident communication and evidence.", "hu": "Szolgáltatáskiesés. Nyisd meg az incidenskommunikációt és a bizonyítékokat."},
	"tip.leads": {"en": "Optional new business. Your live services take priority.", "hu": "Lehetséges új üzlet. Az élő szolgáltatásaid elsőbbséget élveznek."},
	"tip.activity": {"en": "Read your company activity.", "hu": "Olvasd el a céged tevékenységét."},
	"tip.select_mode": {"en": "Select mode (Q)", "hu": "Kijelölő mód (Q)"},
	"tip.place_rack": {"en": "Place a rack (R)", "hu": "Rack elhelyezése (R)"},
	"tip.clock": {"en": "Current shift, traffic level and season. The room lighting follows this clock; unattended hours leave incidents waiting for the next crew.", "hu": "Aktuális műszak, forgalmi szint és évszak. A terem világítása ezt az órát követi; a felügyelet nélküli órákban az incidensek a következő csapatra várnak."},
	"tip.cash": {"en": "Cash and reputation. Electricity and cooling are included in this colo lease.", "hu": "Készpénz és hírnév. Az áram és a hűtés benne van ebben a colo bérletben."},
	"ph.handover_note": {"en": "Short context for whoever opens this next…", "hu": "Rövid háttér annak, aki legközelebb megnyitja…"},
	"ph.hostname": {"en": "hostname, Enter to apply", "hu": "hostnév, Enter az alkalmazáshoz"},
	"tip.confirmed_commit": {"en": "The change reverts in three cycles unless you come back and confirm it. This is what saves you when you cut your own path.", "hu": "A változtatás három ciklus múlva visszaáll, hacsak vissza nem jössz megerősíteni. Ez ment meg, ha elvágod a saját utadat."},
	"tip.send_floor": {"en": "It leaves the rack now and arrives on the other dock as a crate. Its configuration stays behind.", "hu": "Most kikerül a rackből, és ládaként érkezik a másik rakodóra. A konfigurációja itt marad."},
	"tip.decommission": {"en": "Pulling it is the fast half. What you skip is what an auditor asks about later.", "hu": "A kihúzás a gyors fele. Amit kihagysz, arról kérdez később az auditor."},
	"tip.remote_hands": {"en": "Somebody else's hands, doing exactly what you wrote. Labels are what make that safe.", "hu": "Valaki más keze, pontosan azt teszi, amit leírtál. A címkék teszik ezt biztonságossá."},
	"tip.physical_work": {"en": "Reseat it, swap the optic, swap the lead. The wrong one costs the part and fixes nothing.", "hu": "Dugd vissza, cseréld az optikát, cseréld a kábelt. A rossz választás az alkatrészbe kerül, és nem javít semmit."},
	"tip.jack_note": {"en": "Leave physical handover context on this jack", "hu": "Hagyj fizikai átadási megjegyzést ezen az aljzaton"},
	"tip.run_cable": {"en": "Pick the free port on the far end, in this rack or another; dragging between port squares in the rack view works too.", "hu": "Válaszd ki a szabad portot a túloldalon, ebben vagy másik rackben; a rack nézetben a portnégyzetek közti húzás is működik."},
	"ph.filter_chapters": {"en": "filter the chapters", "hu": "fejezetek szűrése"},
	"tip.crew_short_notice": {"en": "It helps a little. It cannot fake months of neglect.", "hu": "Segít egy kicsit. Hónapok elhanyagolását nem tudja eltüntetni."},
	"tip.investigate": {"en": "Counters, logs and asking somebody. Twice and you will know.", "hu": "Számlálók, naplók, és megkérdezni valakit. Kétszer, és tudni fogod."},
	"tip.turn_off": {"en": "Reclaims power, space and addresses. Assuming nothing needed it.", "hu": "Visszaad áramot, helyet és címeket. Feltéve, hogy semminek sem kellett."},
	"tip.support_bundle": {"en": "They will work it, slowly, and they will not push back", "hu": "Foglalkoznak vele, lassan, és nem fognak visszaszólni"},
	"tip.fixed_image": {"en": "A reload. Inside a change window it is routine; outside one it is a decision.", "hu": "Újraindítás. Változtatási ablakban rutin; azon kívül döntés."},
	"tip.auto_renew": {"en": "Auto-renew takes the money when it takes it, whatever else is happening", "hu": "Az automatikus megújítás akkor viszi a pénzt, amikor viszi, bármi történjék is"},
	"tip.second_company": {"en": "A new run in this save slot, one difficulty up, with what this company leaves behind on offer.", "hu": "Új játék ebben a mentési helyen, egy nehézséggel feljebb, azzal, amit ez a cég hátrahagy."},
	"tip.retire": {"en": "Freeze the run and read the report. Your save is not touched.", "hu": "Fagyaszd le a játékot, és olvasd el a jelentést. A mentésed érintetlen marad."},
	"tip.clear_history": {"en": "History is not a save: clearing it costs you nothing but the table.", "hu": "Az előzmény nem mentés: a törlése csak a táblázatba kerül."},
	"tip.cameras": {"en": "They prevent nothing and explain everything.", "hu": "Semmit sem akadályoznak meg, és mindent megmagyaráznak."},
	"tip.call_out": {"en": "The call-out: somebody comes in now and the crew can act on it this cycle", "hu": "A kihívás: valaki most bejön, és a csapat még ebben a ciklusban léphet"},
	"tip.delegate": {"en": "Let the crew keep this one on schedule and bill you for it", "hu": "Hagyd, hogy a csapat ütemezetten tartsa, és kiszámlázza neked"},
	"tip.standing_order": {"en": "Keep the drawer topped up automatically, while there is money to do it", "hu": "A fiók automatikus feltöltése, amíg van rá pénz"},
	"tip.cabling_documented": {"en": "Documented runs label both ends and write themselves up as they go.", "hu": "A dokumentált kábelezés mindkét véget címkézi, és menet közben leírja magát."},
	"tip.redo_leads": {"en": "Proper lengths, out of the drawer. It shows on a tour.", "hu": "Rendes hosszak, a fiókból. Egy bejáráson meglátszik."},
	"tip.order_hardware": {"en": "Vendor tier decides the price and the wait. What turns up is a crate.", "hu": "A szállítói szint dönti el az árat és a várakozást. Ami megérkezik, az egy láda."},
	"tip.check_order": {"en": "Damage and wrong items go back free. Discovered later, they do not.", "hu": "A sérült és téves tételek ingyen mennek vissza. Ha később derül ki, már nem."},
	"tip.rma": {"en": "Ship the dead unit to the vendor. With support cover the replacement comes first.", "hu": "Küldd a halott egységet a szállítónak. Támogatási szerződéssel a csere érkezik előbb."},
	"tip.new_runbook": {"en": "A bounded action, a selector, and a blast radius. Nothing else.", "hu": "Egy korlátos művelet, egy kiválasztó és egy hatókör. Semmi más."},
	"tip.roll_back": {"en": "Put every device it touched back to the configuration it had before", "hu": "Minden érintett eszköz visszakapja a korábbi konfigurációját"},
	"ph.playbook_name": {"en": "playbook name", "hu": "playbook neve"},
	"ph.playbook_commands": {"en": "one command per line, exactly as you would type it at a console", "hu": "soronként egy parancs, pontosan úgy, ahogy a konzolba gépelnéd"},
	"tip.hand_fault": {"en": "Copy the live topology, configs and symptom to the clipboard, or open one somebody sent you", "hu": "Másold a vágólapra az élő topológiát, a konfigurációkat és a tünetet, vagy nyiss meg egyet, amit valaki küldött"},
	"tip.content_workshop": {"en": "Packs are JSON files: what is on the floor, what has to become true, and what happens then.", "hu": "A csomagok JSON fájlok: mi van a padlón, minek kell igazzá válnia, és mi történik utána."},
	"tip.export_topology": {"en": "Mermaid for a picture, plain text for a report. Copied to the clipboard as well.", "hu": "Mermaid a képhez, egyszerű szöveg a jelentéshez. A vágólapra is kerül."},
	"tip.export_clab": {"en": "Writes a .clab.yml plus a startup configuration per device into the game's user folder: RouterOS for PacketTik gear, cEOS for the rest, Linux for servers.", "hu": "Egy .clab.yml fájlt és eszközönként egy indító konfigurációt ír a játék felhasználói mappájába: RouterOS a PacketTik eszközökhöz, cEOS a többihez, Linux a szerverekhez."},
	"tip.challenge_code": {"en": "A drill anybody can reproduce from a short code", "hu": "Egy gyakorlat, amit bárki reprodukálhat egy rövid kódból"},
	"tip.highlight_customer": {"en": "Highlight the live dependencies of one customer.", "hu": "Egy ügyfél élő függőségeinek kiemelése."},
	"tip.teaching_restore": {"en": "Re-enables only the tutorial access port. No customer or topology is deleted.", "hu": "Csak az oktató hozzáférési portot engedélyezi újra. Ügyfél vagy topológia nem törlődik."},
	"tip.keep_world": {"en": "The world stays exactly as it is; nothing new unlocks", "hu": "A világ pontosan így marad; semmi új nem nyílik meg"},
	"tip.chase": {"en": "They pay on the next cycle, and think slightly less of you for it", "hu": "A következő ciklusban fizetnek, és kicsit kevesebbre tartanak érte"},
	"tip.accountant": {"en": "Without one, only half your depreciation allowance is ever claimed.", "hu": "Nélküle az értékcsökkenési kedvezménynek csak a felét érvényesíted."},
	"tip.slash29": {"en": "Eight more addresses. The price goes up every time, because it does.", "hu": "Nyolc további cím. Az ár minden alkalommal emelkedik, mert így megy."},
	"tip.peering": {"en": "Settlement-free peering. It only pays for itself past a certain volume, which is the decision.", "hu": "Elszámolásmentes peering. Csak egy bizonyos forgalom felett éri meg, és ez a döntés."},
	"tip.window": {"en": "Planned downtime in a window is excused by your customers", "hu": "Az ablakban tervezett leállást az ügyfeleid elnézik"},
	"tip.abort_revert": {"en": "Back to what was running when the window opened. A wasted night, and nothing worse.", "hu": "Vissza ahhoz, ami az ablak nyitásakor futott. Egy elvesztegetett éjszaka, és semmi rosszabb."},
	"tip.push_past": {"en": "From here it has to work: there is no going back inside the window.", "hu": "Innentől működnie kell: az ablakon belül nincs visszaút."},
	"tip.change_plan": {"en": "What you are touching, how long you need, and whether there is a backout plan", "hu": "Mihez nyúlsz, mennyi idő kell, és van-e visszalépési terv"},
	"tip.call_somebody_out": {"en": "Phone the best-rested member of the crew and get them in for a cycle. It costs the fee and it costs their morale.", "hu": "Hívd fel a csapat legkipihentebb tagját, és hozd be egy ciklusra. A díjba és a moráljába kerül."},
	"tip.shift": {"en": "Which part of the day they cover. Nights cost a premium.", "hu": "A nap melyik részét fedik le. Az éjszaka felárba kerül."},
	"tip.raise": {"en": "Ten percent. Cheaper than replacing them.", "hu": "Tíz százalék. Olcsóbb, mint pótolni őket."},
	"tip.cancel_circuit": {"en": "Ends the circuit and any cables riding it", "hu": "Megszünteti a vonalat és minden rajta futó kábelt"},
	"tip.sell_company": {"en": "It ends here, with the money and the score you have earned.", "hu": "Itt ér véget, a megkeresett pénzzel és pontszámmal."},
	"tip.turn_down": {"en": "They will compete harder for everything after this.", "hu": "Ezután mindenért keményebben fognak versenyezni."},
	"tip.go_see": {"en": "Some of them turn out to have no budget. That is what qualifying is for.", "hu": "Némelyikükről kiderül, hogy nincs költségvetése. Erre való a minősítés."},
	"tip.price_start": {"en": "A starting point above estimated break-even, not the customer's hidden budget.", "hu": "Kiindulópont a becsült fedezeti pont felett, nem az ügyfél rejtett kerete."},
	"tip.read_notes": {"en": "Notes nobody reads stop being true, and the next shift finds out the hard way.", "hu": "A jegyzet, amit senki sem olvas, nem marad igaz, és a következő műszak a nehezebb úton tudja meg."},
	"tip.triage": {"en": "Pick where to look. Looking in the wrong place costs an afternoon.", "hu": "Válaszd ki, hol nézel. A rossz helyen keresés egy délutánba kerül."},
	"tip.close_it": {"en": "Closing something that is still broken brings it back angrier.", "hu": "Ami még hibás, azt lezárva dühösebben jön vissza."},
	"ph.status_update": {"en": "what is happening, in plain language", "hu": "mi történik, egyszerű nyelven"},
	"tip.replay": {"en": "What the estate looked like either side of it", "hu": "Hogy nézett ki a hálózat előtte és utána"},
	"tip.get_somebody": {"en": "The person carrying the phone if there is one, otherwise whoever is best rested. They will be tired tomorrow.", "hu": "Aki az ügyeleti telefont viszi, ha van ilyen, különben a legkipihentebb. Holnap fáradt lesz."},
	"tip.waits_morning": {"en": "Costs nothing. Whatever it does overnight, it does.", "hu": "Nem kerül semmibe. Amit éjjel művel, azt műveli."},
	"ph.customer_note": {"en": "note about this customer (for you, never read by anything)", "hu": "jegyzet erről az ügyfélről (neked, semmi sem olvassa)"},
	"tip.put_in_writing": {"en": "It does not stop the outage. It decides who wears it.", "hu": "Nem állítja meg a kiesést. Azt dönti el, ki viseli."},
	"tip.their_way": {"en": "Keep the customer happy now.", "hu": "Tartsd elégedetten az ügyfelet most."},
	"tip.hold_firm": {"en": "Refuse. They may walk, and they may have been right.", "hu": "Utasítsd el. Lehet, hogy elmennek, és lehet, hogy igazuk volt."},
	"tip.take_it": {"en": "More money, and more traffic on the same links tonight.", "hu": "Több pénz, és több forgalom ugyanazokon a linkeken ma este."},
	"tip.decline_remember": {"en": "They will remember it at renewal.", "hu": "A megújításkor emlékezni fognak rá."},
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

static func slug(text: String) -> String:
	## "FIRE, SMOKE AND WATER" -> "fire_smoke_and_water": a catalogue key from a heading
	var out := ""
	var last_us := true
	for ch in text.to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			out += ch
			last_us = false
		elif not last_us:
			out += "_"
			last_us = true
	return out.trim_suffix("_")

static var _money_rx: RegEx = null

static func tidy_money(text: String) -> String:
	## "$1,200" is the English layout; Hungarian writes the sign after the
	## number. Resolved on the way to the screen, like the plurals, so the
	## two hundred inline formats in the panels follow the language.
	if language != "hu" or "$" not in text:
		return text
	if _money_rx == null:
		_money_rx = RegEx.new()
		_money_rx.compile("\\$(-?\\d[\\d,]*)")
	var out := text
	for m in _money_rx.search_all(text):
		out = out.replace(m.get_string(0), "%s $" % m.get_string(1))
	return out

static func tidy(text: String) -> String:
	return tidy_money(tidy_plurals(text))

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
