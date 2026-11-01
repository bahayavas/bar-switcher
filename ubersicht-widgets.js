// Übersicht widget'larını gizler/gösterir — silmez, yalnızca "hidden" ayarını değiştirir.
//
//   osascript -l JavaScript ubersicht-widgets.js file <only|except> <klasör> <WidgetSettings.json>
//       Übersicht kapalıyken: ayar dosyasındaki bilinen widget'ları önceden ayarlar (açılışta yanıp sönmesin)
//   osascript -l JavaScript ubersicht-widgets.js live <only|except> <klasör>
//       Übersicht açıkken: AppleScript "hidden" özelliğiyle (Übersicht ayarı kendisi kaydeder)
//
// Widget id'si klasör yolundan türetilir: widgets/simple-bar/index.jsx → "simple-bar-index-jsx".
// "only X": yalnızca X klasöründekiler görünür. "except X": X klasöründekiler gizli, diğerleri görünür.
ObjC.import('Foundation')

function shouldHide(id, mode, folder) {
    const inFolder = id === folder || id.startsWith(folder + '-')
    return mode === 'only' ? !inFolder : inFolder
}

function run(argv) {
    const [where, mode, folder, file] = argv
    if (where === 'file') {
        const data = $.NSString.stringWithContentsOfFileEncodingError(file, $.NSUTF8StringEncoding, null)
        if (data.isNil()) return 'ayar dosyası yok'
        const settings = JSON.parse(data.js)
        let changed = 0
        for (const id of Object.keys(settings)) {
            const hide = shouldHide(id, mode, folder)
            if (settings[id].hidden !== hide) { settings[id].hidden = hide; changed++ }
        }
        if (changed) $(JSON.stringify(settings)).writeToFileAtomicallyEncodingError(file, true, $.NSUTF8StringEncoding, null)
        return `dosya: ${changed} değişti`
    }

    // live: widget'lar sunucu derleyince listede belirir; birkaç saniye bekle
    const app = Application('tracesOf.Uebersicht')
    let out = []
    let passes = 0
    for (let tries = 0; tries < 40; tries++) {
        // widgets() öğeleri doğrudan okunamıyor (-1700); id listesi + byId çalışıyor
        let ids = []
        try { ids = app.widgets.id() } catch (e) { }
        if (ids.length > 0) {
            out = []
            for (const id of ids) {
                const w = app.widgets.byId(id)
                const hide = shouldHide(id, mode, folder)
                if (w.hidden() !== hide) w.hidden = hide
                out.push(`${id}=${hide ? 'gizli' : 'açık'}`)
            }
            // Geç derlenen widget'lar için bir tur daha
            if (++passes >= 2) break
            delay(2)
            continue
        }
        delay(0.5)
    }
    return out.join(' ') || 'widget bulunamadı'
}
