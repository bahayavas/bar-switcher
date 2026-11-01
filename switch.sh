#!/bin/bash
# Bar Switcher — aynı anda yalnızca bir üst bar (status bar) çalıştırır.
#
#   switch.sh <id|none>      diğerlerini kapat, seçileni başlat, menü barı ayarla, seçimi kaydet
#   switch.sh restart <id>   o barı kapatıp yeniden aç (yalnızca aktifse)
#   switch.sh restore        kayıtlı seçimi başlat (login'de uygulama çağırır)
#   switch.sh status         kayıtlı seçim + çalışanlar
#   switch.sh menubar-restore   macOS menü barı ayarını yedekteki değere döndür
#
# Bar listesi: bars.conf (aynı klasör). Ayarlar: ~/.config/bar-switcher/settings.json

set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
CONF="$DIR/bars.conf"
STATE_DIR="$HOME/.config/bar-switcher"
STATE="$STATE_DIR/current"
SETTINGS="$STATE_DIR/settings.json"
MENUBAR_BACKUP="$STATE_DIR/menubar.backup"
LOCK="$STATE_DIR/.lock"
LOG="$STATE_DIR/switch.log"
QUIT_WAIT=3   # normal quit sonrası beklenecek saniye
UB_SETTINGS="$HOME/Library/Application Support/tracesOf.Uebersicht/WidgetSettings.json"

# Uygulamadan (launchd) çağrılınca PATH çıplak gelir; SketchyBar eklentileri brew araçlarını arar
export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export LANG="${LANG:-en_US.UTF-8}"

mkdir -p "$STATE_DIR"

ids=() ; kinds=() ; bids=() ; paths=()
while IFS='|' read -r id name kind bid path cfg badge; do
    [[ -z "$id" || "$id" == \#* ]] && continue
    ids+=("$id"); kinds+=("$kind"); bids+=("$bid"); paths+=("$path")
done < "$CONF"

log() {
    echo "[bar-switcher] $*" >&2
    echo "$(date '+%F %T') $*" >> "$LOG"
}

index_of() {
    local i
    for i in "${!ids[@]}"; do [[ "${ids[$i]}" == "$1" ]] && { echo "$i"; return 0; }; done
    return 1
}

is_ub() { [[ "${kinds[$1]}" == ubersicht* ]]; }

# Yoldaki ASCII dışı harfleri (Ü) ".+" yap: süreç yolu NFD, conf NFC olabilir
path_regex() { LC_ALL=C sed 's/[^ -~][^ -~]*/.+/g' <<< "$1"; }

proc_pattern() { echo "^$(path_regex "${paths[$1]}")/Contents/MacOS/"; }

# Çalışan süreç (aynı uygulamayı paylaşan simple-bar/Übersicht için ikisi de "çalışıyor" der)
proc_running() { pgrep_bar "$1" >/dev/null; }

# Binary barlar süreç adıyla (terminalden `sketchybar` diye açılmış olabilir), uygulamalar yoluyla bulunur
pgrep_bar() {
    if [[ "${kinds[$1]}" == binary ]]; then pgrep -x "$(basename "${paths[$1]}")"; else pgrep -f "$(proc_pattern "$1")"; fi
}
pkill_bar() {   # pkill_bar <i> <TERM|KILL>
    if [[ "${kinds[$1]}" == binary ]]; then pkill "-$2" -x "$(basename "${paths[$1]}")"; else pkill "-$2" -f "$(proc_pattern "$1")"; fi
}

installed() {
    if [[ "${kinds[$1]}" == binary ]]; then [[ -x "${paths[$1]}" ]]; else [[ -d "${paths[$1]}" ]]; fi
}

# Hangi bar aktif? Übersicht çalışıyorsa kayıtlı moda bakılır (simplebar mı ubersicht mi)
active_id() {
    local i saved
    saved="$(cat "$STATE" 2>/dev/null || echo none)"
    for i in "${!ids[@]}"; do
        proc_running "$i" || continue
        if is_ub "$i"; then
            local s; s=$(index_of "$saved") && is_ub "$s" && { echo "$saved"; return; }
        fi
        echo "${ids[$i]}"; return
    done
    echo none
}

stop_bar() {
    local i=$1 t
    proc_running "$i" || return 0
    log "${ids[$i]} kapatılıyor"
    if [[ "${kinds[$i]}" == binary ]]; then
        pkill_bar "$i" TERM          # SketchyBar gibi daemonlar için normal kapanış TERM
    else
        osascript -e "with timeout of $QUIT_WAIT seconds" \
                  -e "tell application id \"${bids[$i]}\" to quit" \
                  -e "end timeout" >/dev/null 2>&1 &
    fi
    for ((t = 0; t < QUIT_WAIT * 4; t++)); do
        proc_running "$i" || break
        sleep 0.25
    done
    if proc_running "$i"; then
        log "${ids[$i]} kapanmadı, TERM"
        pkill_bar "$i" TERM
        for ((t = 0; t < 4; t++)); do
            proc_running "$i" || break
            sleep 0.25
        done
    fi
    if proc_running "$i"; then
        log "${ids[$i]} hâlâ açık, KILL"
        pkill_bar "$i" KILL
    fi
    # Übersicht TERM ile ölünce node widget sunucusu öksüz kalıyor
    if is_ub "$i"; then
        pkill -TERM -f "^$(path_regex "${paths[$i]}")/Contents/Resources/" 2>/dev/null
    fi
    return 0
}

ub_mode() {   # "ubersicht:only=simple-bar" → "only simple-bar"
    local spec="${kinds[$1]#ubersicht:}"
    echo "${spec%%=*} ${spec#*=}"
}

ub_backup_once() {
    [[ -f "$UB_SETTINGS" && ! -f "$STATE_DIR/WidgetSettings.json.orig" ]] && cp "$UB_SETTINGS" "$STATE_DIR/WidgetSettings.json.orig"
}

start_bar() {
    local i=$1
    log "${ids[$i]} başlatılıyor"
    case "${kinds[$i]}" in
        binary)
            # Tamamen ayrılmış başlat: stdout/stderr uygulamanın borusunu açık tutmasın
            ( cd "$HOME" || exit; exec nohup "${paths[$i]}" ) </dev/null >/dev/null 2>&1 &
            ;;
        ubersicht:*)
            ub_backup_once
            # shellcheck disable=SC2046
            osascript -l JavaScript "$DIR/ubersicht-widgets.js" file $(ub_mode "$i") "$UB_SETTINGS" >/dev/null 2>&1
            open -g -a "${paths[$i]}" || return 1
            ub_apply_live "$i"
            ;;
        *)
            open -g -a "${paths[$i]}" || return 1
            ;;
    esac
}

# Açık Übersicht'te widget'ları ayarla (arka planda; widget'lar derlenene kadar bekler)
ub_apply_live() {
    # shellcheck disable=SC2046
    (osascript -l JavaScript "$DIR/ubersicht-widgets.js" live $(ub_mode "$1") >>"$LOG" 2>&1 &)
}

# --- macOS menü barı -------------------------------------------------------

menubar_notify() {
    osascript -l JavaScript -e 'ObjC.import("Foundation");
        $.NSDistributedNotificationCenter.defaultCenter.postNotificationNameObjectUserInfoDeliverImmediately(
            "AppleInterfaceMenuBarHidingChangedNotification", $(), $(), true)' >/dev/null 2>&1
}

manage_menubar() {
    [[ "$(plutil -extract manageMenuBar raw -o - "$SETTINGS" 2>/dev/null)" != false ]]
}

apply_menubar() {
    manage_menubar || return 0
    local want=1 cur
    [[ "$1" == none ]] && want=0
    cur="$(defaults read NSGlobalDomain _HIHideMenuBar 2>/dev/null || echo unset)"
    # İlk dokunuştan önce mevcut değeri yedekle
    [[ -f "$MENUBAR_BACKUP" ]] || echo "$cur" > "$MENUBAR_BACKUP"
    [[ "$cur" == "$want" ]] && return 0
    log "menü barı otomatik gizleme: $([[ $want == 1 ]] && echo açık || echo kapalı)"
    defaults write NSGlobalDomain _HIHideMenuBar -bool "$([[ $want == 1 ]] && echo true || echo false)"
    menubar_notify
}

menubar_restore() {
    [[ -f "$MENUBAR_BACKUP" ]] || { log "menü barı yedeği yok"; return 0; }
    local v; v="$(cat "$MENUBAR_BACKUP")"
    if [[ "$v" == unset ]]; then
        defaults delete NSGlobalDomain _HIHideMenuBar 2>/dev/null
    else
        defaults write NSGlobalDomain _HIHideMenuBar -bool "$([[ $v == 1 ]] && echo true || echo false)"
    fi
    menubar_notify
    rm -f "$MENUBAR_BACKUP"   # yönetim yeniden açılırsa o anki değer yedeklenir
    log "menü barı yedekten geri yüklendi ($v)"
}

# --- geçiş -----------------------------------------------------------------

switch_to() {
    local target="$1" t=-1 i
    if [[ "$target" != none ]]; then
        t=$(index_of "$target") || { log "bilinmeyen bar: $target"; exit 2; }
        installed "$t" || { log "$target kurulu değil (${paths[$t]})"; exit 3; }
    fi

    # Aynı bar zaten açık ve tek başına çalışıyorsa hiçbir şey yapma
    local others=0
    for i in "${!ids[@]}"; do
        [[ $i == "$t" ]] && continue
        (( t >= 0 )) && is_ub "$i" && is_ub "$t" && continue   # aynı Übersicht süreci
        proc_running "$i" && others=1
    done
    if [[ $others -eq 0 ]] && [[ "$(active_id)" == "$target" ]]; then
        echo "$target" > "$STATE"
        apply_menubar "$target"
        log "$target zaten aktif"
        return 0
    fi

    for i in "${!ids[@]}"; do
        [[ $i == "$t" ]] && continue
        (( t >= 0 )) && is_ub "$i" && is_ub "$t" && continue
        stop_bar "$i"
    done

    if (( t >= 0 )); then
        if is_ub "$t" && proc_running "$t"; then
            log "Übersicht açık, widget'lar ${ids[$t]} için ayarlanıyor"
            ub_apply_live "$t"
        elif ! proc_running "$t"; then
            start_bar "$t" || { log "$target açılamadı"; exit 4; }
        fi
    fi
    echo "$target" > "$STATE"
    apply_menubar "$target"
}

restart_bar() {
    local t
    t=$(index_of "$1") || { log "bilinmeyen bar: $1"; exit 2; }
    [[ "$(active_id)" == "$1" ]] || { log "$1 aktif değil, yeniden başlatılmadı"; exit 6; }
    stop_bar "$t"
    start_bar "$t" || { log "$1 açılamadı"; exit 4; }
}

cmd="${1:-}"
case "$cmd" in
    status)
        echo "kayıtlı: $(cat "$STATE" 2>/dev/null || echo none)"
        echo "aktif: $(active_id)"
        for i in "${!ids[@]}"; do
            installed "$i" || echo "kurulu değil: ${ids[$i]}"
            proc_running "$i" && echo "çalışıyor: ${ids[$i]}"
        done
        exit 0 ;;
    restore) cmd="$(cat "$STATE" 2>/dev/null || echo none)" ;;
    restart | menubar-restore) ;;
    "" | -h | --help)
        echo "kullanım: $(basename "$0") <$(IFS='|'; echo "${ids[*]}")|none|restart <id>|restore|status|menubar-restore>" >&2
        exit 1 ;;
esac

# Aynı anda iki geçiş çalışmasın (çift tıklama, kısayol tekrarı…)
if ! mkdir "$LOCK" 2>/dev/null; then
    if (( $(date +%s) - $(stat -f %m "$LOCK" 2>/dev/null || echo 0) > 30 )); then
        rmdir "$LOCK"; mkdir "$LOCK"
    else
        log "başka bir geçiş sürüyor"; exit 5
    fi
fi
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

[[ -f "$LOG" ]] && (( $(wc -l < "$LOG") > 500 )) && tail -200 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"

log "istek: $*"
case "$cmd" in
    restart) restart_bar "${2:-}" ;;
    menubar-restore) menubar_restore ;;
    *) switch_to "$cmd" ;;
esac
