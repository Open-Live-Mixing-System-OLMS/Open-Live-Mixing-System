#!/bin/bash
# OLMS STABILITY ANALYZER - v1.4.1 (STABLE UI FIX)
# Fix: Silenziamento job control e raggruppamento print per evitare drift.

set -e

# --- CONFIGURAZIONE ---
export TARGET_USER="francesco_ssh"
export BIN_JACK_DELAY="/usr/bin/jack_delay"
export J_ENV="XDG_RUNTIME_DIR=/run/user/1000 JACK_DEFAULT_SERVER=olms JACK_PROMISCUOUS_SERVER=1"
export J_CMD="sudo -u $TARGET_USER env $J_ENV"

# PORTE
GEN_OUT="jack_delay:out"
ARDOUR_IN="ardour:Audio 1/audio_in 1"

# Default duration
DURATION=60

# Parsing argomenti
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --s) DURATION="$2"; shift ;;
        *) echo "Parametro sconosciuto: $1"; exit 1 ;;
    esac
    shift
done

# --- COLORI ---
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
NC='\033[0m'

# --- LOGGING ---
LOG_FILE="/tmp/olms_stability_test_$(date +%Y%m%d_%H%M%S).log"

log_to_file() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# --- CLEANUP ---
cleanup() {
    local cleanup_time=$(date '+%Y-%m-%d %H:%M:%S')
    log_to_file "CLEANUP STARTED at $cleanup_time"
    
    tput cnorm # Ripristina cursore
    echo ""
    echo -e "${YELLOW}[CLEANUP]${NC} Arresto generatore e pulizia..."

    if [ ! -z "$ARDOUR_IN" ]; then
        echo -e "${YELLOW}[CLEANUP]${NC} Disconnessione porte audio..."
        log_to_file "Disconnecting audio ports: $GEN_OUT -> $ARDOUR_IN"
        $J_CMD jack_disconnect "$GEN_OUT" "$ARDOUR_IN" 2>/dev/null || true
    fi

    # Kill più specifico e sicuro
    echo -e "${YELLOW}[CLEANUP]${NC} Ricerca processo jack_delay..."
    log_to_file "Searching for jack_delay process"
    JACK_DELAY_PIDS=$(pgrep -f "jack_delay" 2>/dev/null)
    if [ ! -z "$JACK_DELAY_PIDS" ]; then
        echo -e "${YELLOW}[CLEANUP]${NC} Trovati processi jack_delay: $JACK_DELAY_PIDS"
        log_to_file "Found jack_delay processes: $JACK_DELAY_PIDS"
        
        # Gestisci ogni PID individualmente
        echo "$JACK_DELAY_PIDS" | while read -r pid; do
            if [ ! -z "$pid" ]; then
                echo -e "${YELLOW}[CLEANUP]${NC} Uccisione processo jack_delay (PID: $pid)..."
                log_to_file "Killing jack_delay process (PID: $pid)"
                sudo -u $TARGET_USER kill -TERM $pid 2>/dev/null || true
                sleep 1
                # Se ancora attivo, usa SIGKILL
                if kill -0 $pid 2>/dev/null; then
                    echo -e "${YELLOW}[CLEANUP]${NC} Forzatura terminazione con SIGKILL (PID: $pid)..."
                    log_to_file "Force killing jack_delay process with SIGKILL (PID: $pid)"
                    sudo -u $TARGET_USER kill -KILL $pid 2>/dev/null || true
                fi
            fi
        done
    else
        echo -e "${YELLOW}[CLEANUP]${NC} Nessun processo jack_delay trovato"
        log_to_file "No jack_delay process found"
    fi
    
    local cleanup_end_time=$(date '+%Y-%m-%d %H:%M:%S')
    log_to_file "CLEANUP COMPLETED at $cleanup_end_time"
    log_to_file "Log file: $LOG_FILE"
}

handle_signal() {
    echo -e "\n${RED}[SIGNAL]${NC} Ricevuto segnale, terminazione forzata..."
    cleanup
    exit 1
}

trap cleanup EXIT
trap handle_signal INT TERM

# --- FUNZIONI AGGIUNTIVE ---
get_xruns_with_timeout() {
    local stats=$(timeout 2 $J_CMD jack_lsp -p 2>/dev/null)
    if [ -z "$stats" ]; then
        echo "0"
    else
        local result=$(echo "$stats" | grep "xruns" | head -n1 | awk -F'xruns: ' '{print $2}' | awk '{print $1}' | tr -dc '0-9')
        echo "${result:-0}"
    fi
}

get_cpu_load_with_timeout() {
    timeout 2 $J_CMD jack_cpu_load 2>/dev/null | head -n1 | awk '{printf "%.1f%%", $1}' || echo "0.0%"
}

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_err()  { echo -e "${RED}[ERROR]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

format_time() {
    local t=$1
    printf "%02d:%02d" $((t/60)) $((t%60))
}

# --- MAIN ---
clear
tput civis 
echo "=================================================="
echo "    OLMS STABILITY TEST - v1.4.1 (FIXED UI)"
echo "=================================================="

if ! pgrep -f "jackd.*olms" > /dev/null; then
    log_err "JACK server non attivo."
    exit 1
fi

log_info "Avvio generatore impulsi (background)..."
# Evita messaggi "Killed" della shell
{ $J_CMD "$BIN_JACK_DELAY" > /dev/null 2>&1 & } 2>/dev/null
GEN_PID=$!
sleep 2

if ! ps -p $GEN_PID > /dev/null; then
    log_err "Il generatore è crashato."
    exit 1
fi

log_info "Tentativo di routing: $GEN_OUT -> $ARDOUR_IN"
CONN_MSG="In attesa..."

if $J_CMD jack_connect "$GEN_OUT" "$ARDOUR_IN" 2>/dev/null; then
    CONN_MSG="${GREEN}AUDIO OK (Segnale Attivo)${NC}"
    log_info "Routing stabilito con successo."
else
    POSSIBLE_PORT=$($J_CMD jack_lsp | grep "ardour" | grep "in 1" | head -n 1)
    if [ ! -z "$POSSIBLE_PORT" ]; then
        log_info "Trovata porta alt: $POSSIBLE_PORT"
        $J_CMD jack_connect "$GEN_OUT" "$POSSIBLE_PORT" 2>/dev/null
        CONN_MSG="${GREEN}AUDIO OK (Porta Alt)${NC}"
        ARDOUR_IN=$POSSIBLE_PORT
    else
        CONN_MSG="${RED}NO AUDIO (Routing Error)${NC}"
        log_err "Connessione audio fallita."
    fi
fi

echo -e "${CYAN}[INFO]${NC} Avvio monitoraggio passivo..."
START_XRUNS=$(get_xruns_with_timeout)
echo -e "${CYAN}[INFO]${NC} XRUN iniziali: $START_XRUNS"

log_info "Inizio test reale tra 2 secondi..."
sleep 2

END_TIME=$(( $(date +%s) + DURATION ))

# Prepariamo lo spazio per la dashboard (9 righe vuote)
echo ""
echo "--- AVVIO DASHBOARD ---"
for i in {1..9}; do echo ""; done

# 4. CICLO PRINCIPALE
output_counter=0
while [ $(date +%s) -lt $END_TIME ]; do
    NOW=$(date +%s)
    REMAINING=$(( END_TIME - NOW ))
    
    CURRENT_XRUNS_RAW=$(get_xruns_with_timeout)
    DELTA=$(( CURRENT_XRUNS_RAW - START_XRUNS ))
    [ "$DELTA" -lt 0 ] && DELTA=0
    
    if [ "$DELTA" -eq 0 ]; then STATUS_COLOR="$GREEN"; else STATUS_COLOR="$RED"; fi
    
    DSP_LOAD=$(get_cpu_load_with_timeout)
    
    # Calcolo Barra
    total_width=30
    elapsed=$(( DURATION - REMAINING ))
    if [ "$DURATION" -gt 0 ]; then filled=$(( (elapsed * total_width) / DURATION )); else filled=$total_width; fi
    bar=$(printf "%0.s█" $(seq 1 $filled 2>/dev/null || echo 0))
    empty=$(printf "%0.s-" $(seq 1 $(( total_width - filled )) 2>/dev/null || echo 0))
    
    TIMER_STR=$(format_time $REMAINING)
    output_counter=$((output_counter + 1))

    # Redraw ogni secondo per fluidità, ma solo se non ci sono intoppi
    if [ $((output_counter % 1)) -eq 0 ]; then
        # Torna su di 10 righe ed elimina tutto quello che c'è sotto
        echo -en "\033[10A\033[J"
        
        # Costruiamo la dashboard in un unico blocco
        DASHBOARD="${WHITE}==================================================${NC}\n"
        DASHBOARD+="   ${BOLD}TEMPO RIMASTO${NC} :  [ ${CYAN}${TIMER_STR}${NC} ]\n"
        DASHBOARD+="   ${BOLD}PROGRESSO${NC}     :  [${GREEN}${bar}${NC}${empty}]\n"
        DASHBOARD+="${WHITE}--------------------------------------------------${NC}\n"
        DASHBOARD+="   ${BOLD}XRUN COUNT${NC}    :  ${STATUS_COLOR}${BOLD}${DELTA}${NC}\n"
        DASHBOARD+="   ${BOLD}DSP LOAD${NC}      :  ${YELLOW}${DSP_LOAD}${NC}\n"
        DASHBOARD+="${WHITE}==================================================${NC}\n"
        DASHBOARD+="   STATO CONNESSIONE : $CONN_MSG\n"
        DASHBOARD+="${YELLOW}[INFO]${NC} Monitoraggio in corso...\n"
        
        echo -e "$DASHBOARD"
    fi
    
    sleep 1
done

# --- FINE ---
tput cnorm
echo ""
echo "=================================================="
echo "              TEST COMPLETATO"
echo "=================================================="
if [ "$DELTA" -eq 0 ]; then
    echo -e "    RISULTATO: ${GREEN}PASSATO (Stabile)${NC}"
else
    echo -e "    RISULTATO: ${RED}FALLITO ($DELTA XRUNS)${NC}"
fi
echo "=================================================="