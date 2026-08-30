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
	"title.tagline": {
		"en": "Build the network. Win the contract. Survive the traffic.",
		"hu": "Építsd meg a hálózatot. Nyerd el a szerződést. Bírd a forgalmat."},
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
	"title.settings.sub": {"en": "Scale, speed, colour", "hu": "Méret, sebesség, szín"},
	"title.quit": {"en": "Quit", "hu": "Kilépés"},
	"settings.fullscreen": {"en": "Fullscreen", "hu": "Teljes képernyő"},
	"settings.sound": {"en": "Sound", "hu": "Hang"},
	"settings.colourblind": {"en": "Colourblind-friendly status colours",
		"hu": "Színtévesztő-barát állapotszínek"},
	"settings.motion": {"en": "Reduce motion", "hu": "Kevesebb mozgás"},
	"settings.toolbox": {"en": "Show the full toolbox from the start",
		"hu": "Mutasd a teljes eszköztárat az elejétől"},
	"settings.language": {"en": "Language", "hu": "Nyelv"},
	"settings.scale": {"en": "Interface scale", "hu": "Felület mérete"},
	"title.esc": {"en": "ESC returns to this briefing.",
		"hu": "Az ESC visszavisz ehhez az eligazításhoz."},
	"settings.again": {"en": "You can change these again from the in-game menu.",
		"hu": "Ezeket a játékon belüli menüből is átállíthatod."},
	"welcome.title": {
		"en": "Welcome to the floor",
		"hu": "Üdv a gépteremben"},
	"welcome.body": {
		"en": "You have a corner of somebody else's colo, a little money, and a list of jobs. Rack something, cable it, and make it answer.",
		"hu": "Kaptál egy sarkot valaki más kolokációjában, egy kis pénzt és egy feladatlistát. Rakj be valamit, kábelezd be, és érd el, hogy válaszoljon."},
	"welcome.hint": {
		"en": "Q selects, R places a rack, and every device has a working console.",
		"hu": "Q kiválaszt, R rakot helyez el, és minden eszköznek van működő konzolja."},
	"welcome.shift": {
		"en": "SHIFT 01  /  LEGACY COLO  /  02:13",
		"hu": "01. MŰSZAK  /  RÉGI KOLOKÁCIÓ  /  02:13"},
	"welcome.lede": {
		"en": "One borrowed cage. Questionable wiring. Enough cash for one rack. Turn this forgotten corner into a network people can depend on.",
		"hu": "Egy kölcsönkapott ketrec. Kétes kábelezés. Pénz pontosan egy rakra. Csinálj ebből az elfeledett sarokból olyan hálózatot, amire számítani lehet."},
	"welcome.module1.title": {"en": "READ THE ROOM", "hu": "OLVASD A TERMET"},
	"welcome.module1.body": {
		"en": "Drag to pan. Scroll to zoom. Every cable and blinking port is part of the simulation.",
		"hu": "Húzással mozgatsz, görgetéssel nagyítasz. Minden kábel és villogó port a szimuláció része."},
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
		"en": "CLOCK IN  ·  OPEN FIRST CONTRACT",
		"hu": "MŰSZAK KEZDÉSE  ·  ELSŐ SZERZŐDÉS"},
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
		"en": "Welcome to your corner of the colo floor! Buy a rack (toolbar or R, click a floor tile), open it and install one switch and two servers, then cable both servers to the switch (click a server port, then 'Run cable…').",
		"hu": "Üdv a kolokáció saját sarkodban! Vegyél egy rakot (eszköztár vagy R, majd kattints egy padlócsempére), nyisd ki, építs bele egy switchet és két szervert, végül kösd mindkét szervert a switchre (kattints a szerver portjára, majd a „Kábel húzása…” lehetőségre)."},
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
		text = pseudo(String(entry.get(FALLBACK, id)))
	for key: String in args:
		text = text.replace("{%s}" % key, str(args[key]))
	return text

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
