#!/usr/bin/env bash
#
# BPS SH - Cross-platform TCP Connect port scanner for Linux and Git Bash/WSL.
# Use only on systems you own or are explicitly authorized to test.

set -uo pipefail

VERSION="3.0.0"
MAX_CONCURRENCY=1000
MAX_TARGETS_LIMIT=65536
MAX_JOBS=2000000
DELIM=$'\x1f'

PORT_SPEC="common"
EXCLUDE_PORT_SPEC=""
CONCURRENCY=100
RATE=300
TIMEOUT=0.8
RETRIES=0
BANNER=0
BANNER_TIMEOUT=0.4
HTTP_INFO=0
TLS_INFO=0
PROBE_ALL_HTTP=0
PROBE_TIMEOUT=2
REVERSE_DNS=0
INCLUDE_CLOSED=0
MAX_TARGETS=256
ALLOW_LARGE_SCAN=0
PROGRESS=0
FAIL_ON_OPEN=0
QUIET=0
NO_COLOR=0
DRY_RUN=0
JSON_PATH=""
CSV_PATH=""
TXT_PATH=""

declare -a TARGET_SPECS=()
declare -a TARGET_FILES=()
declare -a TARGETS=()
declare -a PORTS=()
declare -a CHILD_PIDS=()
declare -A TARGET_SET=()
declare -A PORT_SET=()
declare -A EXCLUDE_PORT_SET=()

TEMP_DIR=""
RESULTS_RAW=""
RESULTS_SORTED=""
PROGRESS_DONE=""
PROGRESS_PID=""
SCAN_ID=""
STARTED_AT=""

C_RESET=""
C_GREEN=""
C_YELLOW=""
C_RED=""
C_CYAN=""

die() {
  printf 'BPS error: %s\n' "$*" >&2
  exit 2
}

warn() {
  printf 'BPS warning: %s\n' "$*" >&2
}

usage() {
  cat <<'EOF'
BPS SH 3.0 - Linux ve Windows Git Bash/WSL için TCP Connect port tarayıcı

Kullanım:
  ./bps.sh [hedef ...] [seçenekler]

Hedef:
  192.168.1.10
  192.168.1.10,192.168.1.20
  192.168.1.10-192.168.1.30
  192.168.1.0/24
  server.example.local

Temel seçenekler:
  -p, --ports SPEC          Portlar/aralıklar veya preset (varsayılan: common)
      --exclude-ports SPEC  Taramadan çıkarılacak portlar/aralıklar
  -c, --concurrency N       Eşzamanlı tarama sayısı (varsayılan: 100)
      --rate N              Saniyede başlatılacak azami iş; 0 sınırsız
  -t, --timeout SEC         TCP bağlantı zaman aşımı (varsayılan: 0.8)
      --retries N           Timeout için tekrar sayısı, 0-3
      --targets-file FILE   Satır başına hedef içeren dosya

Analiz:
      --banner              Pasif banner satırı oku
      --banner-timeout SEC  Banner zaman aşımı
      --http-info           Bilinen HTTP(S) portlarına HEAD isteği gönder
      --tls-info            Bilinen TLS portlarında TLS/cipher/SHA-256 al
      --probe-all-http      HTTP kontrolünü tüm açık portlarda dene
      --probe-timeout SEC   HTTP/TLS analiz zaman aşımı
      --reverse-dns         Açık hedeflerde PTR/reverse DNS dene

Çıktı:
      --json FILE           JSON raporu
      --csv FILE            Excel uyumlu CSV raporu
      --txt FILE            Metin raporu
      --include-closed      Kapalı/filtreli sonuçları da göster ve kaydet
      --progress SEC        Belirtilen aralıkla canlı ilerleme göster
      --fail-on-open        Açık port varsa 10 çıkış kodu döndür
  -q, --quiet               Başlangıç ve özet bilgilerini gizle
      --no-color            ANSI renklerini kapat

Kapsam:
      --max-targets N       CIDR/IP aralığı hedef sınırı (varsayılan: 256)
      --allow-large-scan    2.000.000 üzerindeki işleri bilinçli onayla
      --dry-run             Hedef/port sayısını göster, tarama yapma

Diğer:
  -h, --help                Yardım
  -V, --version             Sürüm

Preset'ler:
  common, web, database, remote, mail, fileshare, devops, full

Örnek:
  ./bps.sh 192.168.1.10 -p 22,80,443,8000-8100
  ./bps.sh 192.168.1.0/24 -p web --rate 100 --progress 2
  ./bps.sh web.local -p web --http-info --tls-info --json result.json

Yalnızca sahibi olduğunuz veya açık izin aldığınız sistemlerde kullanın.
EOF
}

trim() {
  local value="$*"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

is_uint() {
  [[ ${1:-} =~ ^[0-9]+$ ]]
}

is_number() {
  [[ ${1:-} =~ ^[0-9]+([.][0-9]+)?$ ]]
}

float_between() {
  awk -v value="$1" -v minimum="$2" -v maximum="$3" \
    'BEGIN { exit !(value >= minimum && value <= maximum) }'
}

require_value() {
  [[ $# -ge 2 && -n ${2:-} ]] || die "$1 bir değer gerektiriyor."
}

parse_args() {
  while (($#)); do
    case "$1" in
      -p|--ports)
        require_value "$1" "${2:-}"
        PORT_SPEC="$2"
        shift 2
        ;;
      --exclude-ports)
        require_value "$1" "${2:-}"
        EXCLUDE_PORT_SPEC="$2"
        shift 2
        ;;
      -c|--concurrency)
        require_value "$1" "${2:-}"
        CONCURRENCY="$2"
        shift 2
        ;;
      --rate)
        require_value "$1" "${2:-}"
        RATE="$2"
        shift 2
        ;;
      -t|--timeout)
        require_value "$1" "${2:-}"
        TIMEOUT="$2"
        shift 2
        ;;
      --retries)
        require_value "$1" "${2:-}"
        RETRIES="$2"
        shift 2
        ;;
      --targets-file)
        require_value "$1" "${2:-}"
        TARGET_FILES+=("$2")
        shift 2
        ;;
      --banner)
        BANNER=1
        shift
        ;;
      --banner-timeout)
        require_value "$1" "${2:-}"
        BANNER_TIMEOUT="$2"
        shift 2
        ;;
      --http-info)
        HTTP_INFO=1
        shift
        ;;
      --tls-info)
        TLS_INFO=1
        shift
        ;;
      --probe-all-http)
        PROBE_ALL_HTTP=1
        shift
        ;;
      --probe-timeout)
        require_value "$1" "${2:-}"
        PROBE_TIMEOUT="$2"
        shift 2
        ;;
      --reverse-dns)
        REVERSE_DNS=1
        shift
        ;;
      --include-closed)
        INCLUDE_CLOSED=1
        shift
        ;;
      --max-targets)
        require_value "$1" "${2:-}"
        MAX_TARGETS="$2"
        shift 2
        ;;
      --allow-large-scan)
        ALLOW_LARGE_SCAN=1
        shift
        ;;
      --progress)
        require_value "$1" "${2:-}"
        PROGRESS="$2"
        shift 2
        ;;
      --json)
        require_value "$1" "${2:-}"
        JSON_PATH="$2"
        shift 2
        ;;
      --csv)
        require_value "$1" "${2:-}"
        CSV_PATH="$2"
        shift 2
        ;;
      --txt)
        require_value "$1" "${2:-}"
        TXT_PATH="$2"
        shift 2
        ;;
      --fail-on-open)
        FAIL_ON_OPEN=1
        shift
        ;;
      --dry-run)
        DRY_RUN=1
        shift
        ;;
      -q|--quiet)
        QUIET=1
        shift
        ;;
      --no-color)
        NO_COLOR=1
        shift
        ;;
      -V|--version)
        printf 'bps-sh %s\n' "$VERSION"
        exit 0
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      --)
        shift
        while (($#)); do
          TARGET_SPECS+=("$1")
          shift
        done
        ;;
      -*)
        die "Bilinmeyen seçenek: $1"
        ;;
      *)
        TARGET_SPECS+=("$1")
        shift
        ;;
    esac
  done
}

validate_config() {
  is_uint "$CONCURRENCY" || die "--concurrency tam sayı olmalı."
  ((CONCURRENCY >= 1 && CONCURRENCY <= MAX_CONCURRENCY)) \
    || die "--concurrency 1-$MAX_CONCURRENCY arasında olmalı."
  is_uint "$RATE" || die "--rate 0 veya pozitif tam sayı olmalı."
  ((RATE <= 10000)) || die "--rate en fazla 10000 olabilir."
  is_number "$TIMEOUT" && float_between "$TIMEOUT" 0.05 60 \
    || die "--timeout 0.05-60 arasında olmalı."
  is_uint "$RETRIES" && ((RETRIES <= 3)) || die "--retries 0-3 arasında olmalı."
  is_number "$BANNER_TIMEOUT" && float_between "$BANNER_TIMEOUT" 0.05 10 \
    || die "--banner-timeout 0.05-10 arasında olmalı."
  is_number "$PROBE_TIMEOUT" && float_between "$PROBE_TIMEOUT" 0.1 30 \
    || die "--probe-timeout 0.1-30 arasında olmalı."
  is_number "$PROGRESS" && float_between "$PROGRESS" 0 3600 \
    || die "--progress 0-3600 arasında olmalı."
  is_uint "$MAX_TARGETS" || die "--max-targets tam sayı olmalı."
  ((MAX_TARGETS >= 1 && MAX_TARGETS <= MAX_TARGETS_LIMIT)) \
    || die "--max-targets 1-$MAX_TARGETS_LIMIT arasında olmalı."
  ((PROBE_ALL_HTTP == 0 || HTTP_INFO == 1)) \
    || die "--probe-all-http için --http-info da kullanılmalı."
}

check_runtime() {
  if ((BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 3))); then
    die "BPS Bash 4.3 veya daha yeni sürüm gerektiriyor."
  fi
  local command_name
  for command_name in bash timeout awk sort sed tr cut mktemp date; do
    command -v "$command_name" >/dev/null 2>&1 || die "Gerekli komut bulunamadı: $command_name"
  done
  if ((HTTP_INFO == 1)); then
    command -v curl >/dev/null 2>&1 || die "--http-info için curl gerekli."
  fi
  if ((TLS_INFO == 1)); then
    command -v openssl >/dev/null 2>&1 || die "--tls-info için openssl gerekli."
  fi
}

setup_colors() {
  if [[ -t 1 && $NO_COLOR -eq 0 && -z ${NO_COLOR:-} ]]; then
    C_RESET=$'\033[0m'
    C_GREEN=$'\033[1;32m'
    C_YELLOW=$'\033[1;33m'
    C_RED=$'\033[1;31m'
    C_CYAN=$'\033[1;36m'
  fi
}

preset_spec() {
  case "$1" in
    common)
      printf '%s' '20-23,25,53,67-69,80,88,110-111,119,123,135,137-139,143,161-162,179,389,443,445,465,500,514-515,587,631,636,873,902,989-990,993,995,1080,1433,1521,1723,1883,2049,2181,2375-2376,3000,3306,3389,4369,5000,5432,5672,5900,5985-5986,6379,6443,8000,8080-8081,8443,8888,9000,9090,9200,9418,11211,27017'
      ;;
    web)
      printf '%s' '80,81,443,3000,5000,7001,8000,8008,8080,8081,8088,8443,8888,9000,9090'
      ;;
    database)
      printf '%s' '1433,1521,2181,3306,5432,5672,6379,9042,9200,11211,27017'
      ;;
    remote)
      printf '%s' '22,23,3389,5900,5985,5986'
      ;;
    mail)
      printf '%s' '25,110,143,465,587,993,995'
      ;;
    fileshare)
      printf '%s' '20,21,111,135,139,445,548,873,2049'
      ;;
    devops)
      printf '%s' '22,2375,2376,3000,4369,5000,5672,6379,6443,8080,8443,9000,9090,9200,9418'
      ;;
    full)
      printf '%s' '1-65535'
      ;;
    *)
      return 1
      ;;
  esac
}

add_port_chunk() {
  local chunk="$1"
  local start end port
  if [[ $chunk =~ ^([0-9]+)-([0-9]+)$ ]]; then
    start="${BASH_REMATCH[1]}"
    end="${BASH_REMATCH[2]}"
    ((start >= 1 && end <= 65535 && start <= end)) \
      || die "Geçersiz port aralığı: $chunk"
    for ((port = start; port <= end; port++)); do
      PORT_SET["$port"]=1
    done
  elif [[ $chunk =~ ^[0-9]+$ ]]; then
    port="$chunk"
    ((port >= 1 && port <= 65535)) || die "Geçersiz port: $port"
    PORT_SET["$port"]=1
  else
    die "Geçersiz port bölümü: $chunk"
  fi
}

parse_port_spec_into_main_set() {
  local spec="$1"
  local expanded chunk
  expanded=$(preset_spec "$spec" 2>/dev/null || true)
  [[ -n $expanded ]] && spec="$expanded"
  IFS=',' read -r -a chunks <<< "$spec"
  for chunk in "${chunks[@]}"; do
    chunk=$(trim "$chunk")
    [[ -n $chunk ]] || die "Port listesinde boş bölüm var."
    add_port_chunk "$chunk"
  done
}

parse_exclude_spec() {
  local spec="$1"
  local expanded chunk start end port
  [[ -n $spec ]] || return 0
  expanded=$(preset_spec "$spec" 2>/dev/null || true)
  [[ -n $expanded ]] && spec="$expanded"
  IFS=',' read -r -a chunks <<< "$spec"
  for chunk in "${chunks[@]}"; do
    chunk=$(trim "$chunk")
    if [[ $chunk =~ ^([0-9]+)-([0-9]+)$ ]]; then
      start="${BASH_REMATCH[1]}"
      end="${BASH_REMATCH[2]}"
      ((start >= 1 && end <= 65535 && start <= end)) \
        || die "Geçersiz hariç port aralığı: $chunk"
      for ((port = start; port <= end; port++)); do
        EXCLUDE_PORT_SET["$port"]=1
      done
    elif [[ $chunk =~ ^[0-9]+$ ]]; then
      port="$chunk"
      ((port >= 1 && port <= 65535)) || die "Geçersiz hariç port: $port"
      EXCLUDE_PORT_SET["$port"]=1
    else
      die "Geçersiz hariç port bölümü: $chunk"
    fi
  done
}

build_ports() {
  PORT_SET=()
  EXCLUDE_PORT_SET=()
  parse_port_spec_into_main_set "$PORT_SPEC"
  parse_exclude_spec "$EXCLUDE_PORT_SPEC"
  PORTS=()
  local port
  while IFS= read -r port; do
    [[ -n ${EXCLUDE_PORT_SET[$port]+x} ]] || PORTS+=("$port")
  done < <(printf '%s\n' "${!PORT_SET[@]}" | sort -n)
  ((${#PORTS[@]} > 0)) || die "Taranacak port kalmadı."
}

ipv4_to_int() {
  local ip="$1"
  local a b c d
  IFS='.' read -r a b c d <<< "$ip"
  [[ -n ${a:-} && -n ${b:-} && -n ${c:-} && -n ${d:-} ]] || return 1
  local octet
  for octet in "$a" "$b" "$c" "$d"; do
    [[ $octet =~ ^[0-9]{1,3}$ ]] || return 1
    ((10#$octet <= 255)) || return 1
  done
  REPLY=$(((10#$a << 24) | (10#$b << 16) | (10#$c << 8) | 10#$d))
}

int_to_ipv4() {
  local value="$1"
  REPLY="$(((value >> 24) & 255)).$(((value >> 16) & 255)).$(((value >> 8) & 255)).$((value & 255))"
}

add_target() {
  local target="$1"
  [[ -n ${TARGET_SET[$target]+x} ]] && return 0
  ((${#TARGETS[@]} < MAX_TARGETS)) \
    || die "Hedef sayısı $MAX_TARGETS sınırını aşıyor. Gerekirse --max-targets kullanın."
  TARGET_SET["$target"]=1
  TARGETS+=("$target")
}

expand_ipv4_cidr() {
  local token="$1"
  local base="${token%/*}"
  local prefix="${token#*/}"
  [[ $prefix =~ ^[0-9]+$ ]] && ((prefix >= 0 && prefix <= 32)) \
    || die "Geçersiz IPv4 CIDR: $token"
  ipv4_to_int "$base" || die "Geçersiz IPv4 CIDR: $token"
  local ip_value="$REPLY"
  local mask
  if ((prefix == 0)); then
    mask=0
  else
    mask=$(((0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF))
  fi
  local network=$((ip_value & mask))
  local broadcast=$((network | ((~mask) & 0xFFFFFFFF)))
  local start end value
  if ((prefix == 32)); then
    start="$network"
    end="$network"
  elif ((prefix == 31)); then
    start="$network"
    end="$broadcast"
  else
    start=$((network + 1))
    end=$((broadcast - 1))
  fi
  for ((value = start; value <= end; value++)); do
    int_to_ipv4 "$value"
    add_target "$REPLY"
  done
}

expand_ipv4_range() {
  local start_ip="$1"
  local end_ip="$2"
  ipv4_to_int "$start_ip" || return 1
  local start="$REPLY"
  ipv4_to_int "$end_ip" || return 1
  local end="$REPLY"
  ((start <= end)) || die "IP aralığı ters yazılmış: $start_ip-$end_ip"
  local value
  for ((value = start; value <= end; value++)); do
    int_to_ipv4 "$value"
    add_target "$REPLY"
  done
}

expand_target_spec() {
  local raw="$1"
  local part left right
  IFS=',' read -r -a parts <<< "$raw"
  for part in "${parts[@]}"; do
    part=$(trim "$part")
    [[ -n $part ]] || continue
    if [[ $part == */* ]]; then
      [[ $part != *:* ]] || die "Shell sürümünde IPv6 CIDR desteklenmiyor: $part"
      expand_ipv4_cidr "$part"
    elif [[ $part =~ ^([0-9.]+)-([0-9.]+)$ ]]; then
      left="${BASH_REMATCH[1]}"
      right="${BASH_REMATCH[2]}"
      expand_ipv4_range "$left" "$right" || die "Geçersiz IP aralığı: $part"
    else
      [[ $part =~ ^[A-Za-z0-9._:%-]+$ ]] || die "Geçersiz hedef: $part"
      add_target "$part"
    fi
  done
}

load_targets() {
  local file line spec
  for file in "${TARGET_FILES[@]}"; do
    [[ -r $file ]] || die "Hedef dosyası okunamadı: $file"
    while IFS= read -r line || [[ -n $line ]]; do
      line="${line//$'\r'/}"
      line="${line%%#*}"
      line=$(trim "$line")
      [[ -n $line ]] && TARGET_SPECS+=("$line")
    done < "$file"
  done
  ((${#TARGET_SPECS[@]} > 0)) || die "En az bir hedef veya --targets-file gerekli."
  for spec in "${TARGET_SPECS[@]}"; do
    expand_target_spec "$spec"
  done
  ((${#TARGETS[@]} > 0)) || die "Hiç hedef üretilemedi."
}

service_name() {
  case "$1" in
    20) printf 'ftp-data' ;;
    21) printf 'ftp' ;;
    22) printf 'ssh' ;;
    23) printf 'telnet' ;;
    25) printf 'smtp' ;;
    53) printf 'dns' ;;
    80) printf 'http' ;;
    110) printf 'pop3' ;;
    111) printf 'rpcbind' ;;
    135) printf 'msrpc' ;;
    139) printf 'netbios-ssn' ;;
    143) printf 'imap' ;;
    389) printf 'ldap' ;;
    443) printf 'https' ;;
    445) printf 'microsoft-ds' ;;
    465) printf 'smtps' ;;
    587) printf 'submission' ;;
    631) printf 'ipp' ;;
    636) printf 'ldaps' ;;
    873) printf 'rsync' ;;
    990) printf 'ftps' ;;
    993) printf 'imaps' ;;
    995) printf 'pop3s' ;;
    1080) printf 'socks' ;;
    1433) printf 'mssql' ;;
    1521) printf 'oracle' ;;
    1883) printf 'mqtt' ;;
    2049) printf 'nfs' ;;
    2181) printf 'zookeeper' ;;
    2375) printf 'docker' ;;
    2376) printf 'docker-tls' ;;
    3000) printf 'http-alt' ;;
    3306) printf 'mysql' ;;
    3389) printf 'rdp' ;;
    5000) printf 'http-alt' ;;
    5432) printf 'postgresql' ;;
    5672) printf 'amqp' ;;
    5900) printf 'vnc' ;;
    5985) printf 'winrm-http' ;;
    5986) printf 'winrm-https' ;;
    6379) printf 'redis' ;;
    6443) printf 'kubernetes-api' ;;
    8000|8008|8080|8081|8088|8888|9000|9090) printf 'http-alt' ;;
    8443) printf 'https-alt' ;;
    9200) printf 'elasticsearch' ;;
    9418) printf 'git' ;;
    11211) printf 'memcached' ;;
    27017) printf 'mongodb' ;;
    *) printf 'unknown' ;;
  esac
}

is_http_port() {
  case "$1" in
    80|81|443|3000|5000|5986|6443|7001|8000|8008|8080|8081|8088|8443|8888|9000|9090|9200)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

is_tls_port() {
  case "$1" in
    443|465|636|853|989|990|993|995|2376|5986|6443|8443)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

now_ms() {
  local value
  value=$(date +%s%3N 2>/dev/null || true)
  if [[ $value =~ ^[0-9]+$ ]]; then
    printf '%s' "$value"
  else
    printf '%s000' "$(date +%s)"
  fi
}

sanitize_field() {
  printf '%s' "$1" \
    | tr '\t\r\n' '   ' \
    | tr -cd '[:print:] ' \
    | cut -c1-500
}

tcp_connect() {
  local target="$1"
  local port="$2"
  timeout "$TIMEOUT" bash -c \
    'exec 3<>"/dev/tcp/${1}/${2}"' _ "$target" "$port" \
    >/dev/null 2>&1
}

read_banner() {
  local target="$1"
  local port="$2"
  local value
  value=$(timeout "$BANNER_TIMEOUT" bash -c \
    'exec 3<>"/dev/tcp/${1}/${2}"; IFS= read -r -t "$3" line <&3 || true; printf "%s" "$line"' \
    _ "$target" "$port" "$BANNER_TIMEOUT" 2>/dev/null || true)
  sanitize_field "$value"
}

http_probe() {
  local target="$1"
  local port="$2"
  local scheme="http"
  local url_host="$target"
  is_tls_port "$port" && scheme="https"
  [[ $target == *:* ]] && url_host="[$target]"
  local response
  response=$(curl -k -sS -I \
    --max-time "$PROBE_TIMEOUT" \
    --connect-timeout "$TIMEOUT" \
    --user-agent "BPS-SH/$VERSION" \
    "$scheme://$url_host:$port/" 2>/dev/null || true)
  HTTP_STATUS=$(printf '%s\n' "$response" | tr -d '\r' | awk '/^HTTP\// { print; exit }')
  HTTP_SERVER=$(printf '%s\n' "$response" | tr -d '\r' | awk -F: 'tolower($1) == "server" { sub(/^[[:space:]]+/, "", $2); print $2; exit }')
  HTTP_LOCATION=$(printf '%s\n' "$response" | tr -d '\r' | awk -F: 'tolower($1) == "location" { sub(/^[[:space:]]+/, "", $0); sub(/^[^:]+:[[:space:]]*/, "", $0); print; exit }')
  HTTP_STATUS=$(sanitize_field "$HTTP_STATUS")
  HTTP_SERVER=$(sanitize_field "$HTTP_SERVER")
  HTTP_LOCATION=$(sanitize_field "$HTTP_LOCATION")
}

tls_probe() {
  local target="$1"
  local port="$2"
  local connect_target="$target:$port"
  [[ $target == *:* ]] && connect_target="[$target]:$port"
  local raw
  raw=$(timeout "$PROBE_TIMEOUT" openssl s_client \
    -connect "$connect_target" \
    -servername "$target" \
    -showcerts </dev/null 2>&1 || true)
  TLS_VERSION=$(printf '%s\n' "$raw" | awk -F: '
    /^[[:space:]]*Protocol[[:space:]]*:/ { gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2; exit }
    /^New, TLS/ { split($0, a, ","); gsub(/^[[:space:]]+|[[:space:]]+$/, "", a[2]); print a[2]; exit }
  ')
  TLS_CIPHER=$(printf '%s\n' "$raw" | awk -F: '
    /^[[:space:]]*Cipher[[:space:]]*:/ { gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2; exit }
    /Cipher is/ { sub(/^.*Cipher is[[:space:]]*/, ""); print; exit }
  ')
  TLS_SHA256=$(printf '%s\n' "$raw" \
    | openssl x509 -noout -fingerprint -sha256 2>/dev/null \
    | sed -E 's/^.*=//; s/://g' \
    | tr 'A-F' 'a-f')
  TLS_VERSION=$(sanitize_field "$TLS_VERSION")
  TLS_CIPHER=$(sanitize_field "$TLS_CIPHER")
  TLS_SHA256=$(sanitize_field "$TLS_SHA256")
}

reverse_dns_lookup() {
  local target="$1"
  local value=""
  if command -v getent >/dev/null 2>&1; then
    value=$(getent hosts "$target" 2>/dev/null | awk 'NR == 1 { print $2; exit }')
  elif command -v nslookup >/dev/null 2>&1; then
    value=$(nslookup "$target" 2>/dev/null | awk -F'= ' '/name =/ { print $2; exit }')
  fi
  sanitize_field "$value"
}

append_result() {
  printf '%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s\n' \
    "$1" "$DELIM" "$2" "$DELIM" "$3" "$DELIM" "$4" "$DELIM" "$5" "$DELIM" \
    "$6" "$DELIM" "$7" "$DELIM" "$8" "$DELIM" "$9" "$DELIM" "${10}" "$DELIM" \
    "${11}" "$DELIM" "${12}" "$DELIM" "${13}" "$DELIM" "${14}" "$DELIM" "${15}" \
    >> "$RESULTS_RAW"
}

scan_one() {
  local target="$1"
  local port="$2"
  local service
  service=$(service_name "$port")
  local started ended latency state error rc
  local attempt=0
  local attempts=0
  local banner=""
  local ptr=""
  local HTTP_STATUS=""
  local HTTP_SERVER=""
  local HTTP_LOCATION=""
  local TLS_VERSION=""
  local TLS_CIPHER=""
  local TLS_SHA256=""

  started=$(now_ms)
  state="closed"
  error=""

  while ((attempt <= RETRIES)); do
    attempts=$((attempt + 1))
    tcp_connect "$target" "$port"
    rc=$?
    if ((rc == 0)); then
      state="open"
      error=""
      break
    elif ((rc == 124)); then
      state="filtered"
      error="timeout"
    else
      state="closed"
      error="connect-failed($rc)"
      break
    fi
    attempt=$((attempt + 1))
    ((attempt <= RETRIES)) && sleep 0.05
  done

  if [[ $state == open ]]; then
    ((BANNER == 1)) && banner=$(read_banner "$target" "$port")
    if ((HTTP_INFO == 1)) && { is_http_port "$port" || ((PROBE_ALL_HTTP == 1)); }; then
      http_probe "$target" "$port"
    fi
    if ((TLS_INFO == 1)) && is_tls_port "$port"; then
      tls_probe "$target" "$port"
    fi
    ((REVERSE_DNS == 1)) && ptr=$(reverse_dns_lookup "$target")
  fi

  ended=$(now_ms)
  latency=$((ended - started))
  ((latency >= 0)) || latency=0

  banner=$(sanitize_field "$banner")
  ptr=$(sanitize_field "$ptr")
  error=$(sanitize_field "$error")
  append_result "$target" "$port" "$state" "$service" "$latency" "$attempts" \
    "$banner" "$ptr" "$HTTP_STATUS" "$HTTP_SERVER" "$HTTP_LOCATION" \
    "$TLS_VERSION" "$TLS_CIPHER" "$TLS_SHA256" "$error"

  if [[ $state == open ]]; then
    local detail="${C_GREEN}[OPEN]${C_RESET} $target:$port $service ${latency}ms"
    [[ -n $banner ]] && detail+=" | $banner"
    [[ -n $ptr ]] && detail+=" | PTR=$ptr"
    [[ -n $HTTP_STATUS ]] && detail+=" | $HTTP_STATUS"
    [[ -n $HTTP_SERVER ]] && detail+=" | Server=$HTTP_SERVER"
    [[ -n $HTTP_LOCATION ]] && detail+=" | Location=$HTTP_LOCATION"
    [[ -n $TLS_VERSION ]] && detail+=" | TLS=$TLS_VERSION/$TLS_CIPHER"
    printf '%s\n' "$detail"
  elif ((INCLUDE_CLOSED == 1 && QUIET == 0)); then
    printf '%s[%s]%s %s:%s %s %sms\n' \
      "$C_YELLOW" "${state^^}" "$C_RESET" "$target" "$port" "$service" "$latency"
  fi
}

cleanup() {
  local code=$?
  local pid
  for pid in "${CHILD_PIDS[@]}"; do
    kill "$pid" 2>/dev/null || true
  done
  [[ -n $PROGRESS_PID ]] && kill "$PROGRESS_PID" 2>/dev/null || true
  if [[ -n $TEMP_DIR && -d $TEMP_DIR ]]; then
    rm -rf -- "$TEMP_DIR"
  fi
  return "$code"
}

progress_reporter() {
  local total_jobs="$1"
  local scan_started="$2"
  local done_count open_count now elapsed speed percent
  while [[ ! -f $PROGRESS_DONE ]]; do
    sleep "$PROGRESS"
    [[ -f $PROGRESS_DONE ]] && break
    done_count=$(wc -l < "$RESULTS_RAW" 2>/dev/null || printf '0')
    open_count=$(awk -F "$DELIM" '$3 == "open" { count++ } END { print count + 0 }' "$RESULTS_RAW" 2>/dev/null)
    now=$(now_ms)
    elapsed=$((now - scan_started))
    ((elapsed > 0)) || elapsed=1
    speed=$(awk -v count="$done_count" -v milliseconds="$elapsed" 'BEGIN { printf "%.1f", count * 1000 / milliseconds }')
    percent=$(awk -v count="$done_count" -v total="$total_jobs" 'BEGIN { printf "%.1f", count * 100 / total }')
    printf '[PROGRESS] %s/%s (%s%%) | %s iş/sn | açık=%s\n' \
      "$done_count" "$total_jobs" "$percent" "$speed" "$open_count" >&2
  done
}

prepare_output_path() {
  local path="$1"
  local directory
  directory=$(dirname -- "$path")
  [[ $directory == "." ]] || mkdir -p -- "$directory" || die "Çıktı klasörü oluşturulamadı: $directory"
}

should_include_result() {
  [[ $1 == open || $INCLUDE_CLOSED -eq 1 ]]
}

csv_quote() {
  local value="${1//\"/\"\"}"
  printf '"%s"' "$value"
}

json_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/\\r}"
  value="${value//$'\t'/\\t}"
  printf '%s' "$value"
}

write_csv_report() {
  local path="$1"
  prepare_output_path "$path"
  printf '\xEF\xBB\xBF' > "$path"
  printf '%s\n' 'target,port,state,service,latency_ms,attempts,banner,reverse_dns,http_status,http_server,http_location,tls_version,tls_cipher,tls_sha256,error' >> "$path"
  local target port state service latency attempts banner ptr http_status http_server http_location tls_version tls_cipher tls_sha error
  while IFS="$DELIM" read -r target port state service latency attempts banner ptr http_status http_server http_location tls_version tls_cipher tls_sha error; do
    should_include_result "$state" || continue
    {
      csv_quote "$target"; printf ','
      printf '%s,%s,' "$port" "$state"
      csv_quote "$service"; printf ',%s,%s,' "$latency" "$attempts"
      csv_quote "$banner"; printf ','
      csv_quote "$ptr"; printf ','
      csv_quote "$http_status"; printf ','
      csv_quote "$http_server"; printf ','
      csv_quote "$http_location"; printf ','
      csv_quote "$tls_version"; printf ','
      csv_quote "$tls_cipher"; printf ','
      csv_quote "$tls_sha"; printf ','
      csv_quote "$error"; printf '\n'
    } >> "$path"
  done < "$RESULTS_SORTED"
}

write_txt_report() {
  local path="$1"
  local duration="$2"
  local open_count="$3"
  local total_count="$4"
  prepare_output_path "$path"
  {
    printf 'BPS SH %s TCP Connect Scan\n' "$VERSION"
    printf 'Scan ID: %s\n' "$SCAN_ID"
    printf 'Started: %s\n' "$STARTED_AT"
    printf 'Duration: %s ms\n' "$duration"
    printf 'Summary: total=%s open=%s\n\n' "$total_count" "$open_count"
  } > "$path"
  local target port state service latency attempts banner ptr http_status http_server http_location tls_version tls_cipher tls_sha error
  while IFS="$DELIM" read -r target port state service latency attempts banner ptr http_status http_server http_location tls_version tls_cipher tls_sha error; do
    should_include_result "$state" || continue
    {
      printf '%s:%s %s %s %sms attempts=%s' "$target" "$port" "$state" "$service" "$latency" "$attempts"
      [[ -n $banner ]] && printf ' | banner=%s' "$banner"
      [[ -n $ptr ]] && printf ' | ptr=%s' "$ptr"
      [[ -n $http_status ]] && printf ' | http=%s' "$http_status"
      [[ -n $http_server ]] && printf ' | server=%s' "$http_server"
      [[ -n $http_location ]] && printf ' | location=%s' "$http_location"
      [[ -n $tls_version ]] && printf ' | tls=%s/%s' "$tls_version" "$tls_cipher"
      [[ -n $tls_sha ]] && printf ' | tls_sha256=%s' "$tls_sha"
      [[ -n $error ]] && printf ' | error=%s' "$error"
      printf '\n'
    } >> "$path"
  done < "$RESULTS_SORTED"
}

write_json_report() {
  local path="$1"
  local duration="$2"
  local open_count="$3"
  local total_count="$4"
  prepare_output_path "$path"
  {
    printf '{\n'
    printf '  "tool": "BPS SH",\n'
    printf '  "version": "%s",\n' "$VERSION"
    printf '  "scan_id": "%s",\n' "$(json_escape "$SCAN_ID")"
    printf '  "started_at": "%s",\n' "$(json_escape "$STARTED_AT")"
    printf '  "duration_ms": %s,\n' "$duration"
    printf '  "summary": {"total": %s, "open": %s},\n' "$total_count" "$open_count"
    printf '  "configuration": {"concurrency": %s, "rate": %s, "timeout": %s, "retries": %s},\n' \
      "$CONCURRENCY" "$RATE" "$TIMEOUT" "$RETRIES"
    printf '  "results": [\n'
  } > "$path"

  local first=1
  local target port state service latency attempts banner ptr http_status http_server http_location tls_version tls_cipher tls_sha error
  while IFS="$DELIM" read -r target port state service latency attempts banner ptr http_status http_server http_location tls_version tls_cipher tls_sha error; do
    should_include_result "$state" || continue
    if ((first == 0)); then
      printf ',\n' >> "$path"
    fi
    first=0
    printf '    {"target":"%s","port":%s,"state":"%s","service":"%s","latency_ms":%s,"attempts":%s,"banner":"%s","reverse_dns":"%s","http_status":"%s","http_server":"%s","http_location":"%s","tls_version":"%s","tls_cipher":"%s","tls_sha256":"%s","error":"%s"}' \
      "$(json_escape "$target")" "$port" "$(json_escape "$state")" "$(json_escape "$service")" \
      "$latency" "$attempts" "$(json_escape "$banner")" "$(json_escape "$ptr")" \
      "$(json_escape "$http_status")" "$(json_escape "$http_server")" \
      "$(json_escape "$http_location")" "$(json_escape "$tls_version")" \
      "$(json_escape "$tls_cipher")" "$(json_escape "$tls_sha")" "$(json_escape "$error")" \
      >> "$path"
  done < "$RESULTS_SORTED"
  printf '\n  ]\n}\n' >> "$path"
}

create_scan_id() {
  if command -v uuidgen >/dev/null 2>&1; then
    SCAN_ID=$(uuidgen)
  else
    SCAN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$$-${RANDOM}"
  fi
}

run_scan() {
  local total_jobs=$(( ${#TARGETS[@]} * ${#PORTS[@]} ))
  if ((total_jobs > MAX_JOBS && ALLOW_LARGE_SCAN == 0)); then
    die "Tarama $total_jobs iş içeriyor. Yetkili büyük tarama için --allow-large-scan ekleyin."
  fi
  if ((INCLUDE_CLOSED == 1 && total_jobs > MAX_JOBS)); then
    die "--include-closed çok büyük taramada aşırı çıktı üretir; kapsamı daraltın."
  fi

  create_scan_id
  STARTED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  if ((QUIET == 0)); then
    printf '%sBPS SH %s | TCP Connect Scanner%s\n' "$C_CYAN" "$VERSION" "$C_RESET"
    printf '%sYalnızca sahibi olduğunuz veya açık izin aldığınız sistemleri tarayın.%s\n' "$C_YELLOW" "$C_RESET"
    printf 'Hedef: %s | Port: %s | İş: %s | Eşzamanlılık: %s | Rate: %s/sn\n' \
      "${#TARGETS[@]}" "${#PORTS[@]}" "$total_jobs" "$CONCURRENCY" "$RATE"
    printf 'Scan ID: %s\n\n' "$SCAN_ID"
  fi

  if ((DRY_RUN == 1)); then
    printf 'Dry run: %s hedef x %s port = %s iş\n' "${#TARGETS[@]}" "${#PORTS[@]}" "$total_jobs"
    return 0
  fi

  TEMP_DIR=$(mktemp -d)
  RESULTS_RAW="$TEMP_DIR/results.raw"
  RESULTS_SORTED="$TEMP_DIR/results.sorted"
  PROGRESS_DONE="$TEMP_DIR/progress.done"
  : > "$RESULTS_RAW"
  trap cleanup EXIT
  trap 'exit 130' INT TERM

  local scan_started scan_ended duration
  scan_started=$(now_ms)
  if awk -v value="$PROGRESS" 'BEGIN { exit !(value > 0) }' && ((QUIET == 0)); then
    progress_reporter "$total_jobs" "$scan_started" &
    PROGRESS_PID=$!
  fi

  local active=0
  local target port
  local rate_delay
  rate_delay=$(awk -v rate="$RATE" 'BEGIN { if (rate > 0) printf "%.6f", 1 / rate; else print "0" }')

  for target in "${TARGETS[@]}"; do
    for port in "${PORTS[@]}"; do
      scan_one "$target" "$port" &
      CHILD_PIDS+=("$!")
      active=$((active + 1))
      if ((active >= CONCURRENCY)); then
        wait -n 2>/dev/null || true
        active=$((active - 1))
      fi
      [[ $rate_delay == "0" ]] || sleep "$rate_delay"
    done
  done
  while ((active > 0)); do
    wait -n 2>/dev/null || true
    active=$((active - 1))
  done
  CHILD_PIDS=()

  : > "$PROGRESS_DONE"
  if [[ -n $PROGRESS_PID ]]; then
    wait "$PROGRESS_PID" 2>/dev/null || true
    PROGRESS_PID=""
  fi

  LC_ALL=C sort -t "$DELIM" -k1,1 -k2,2n "$RESULTS_RAW" > "$RESULTS_SORTED"
  scan_ended=$(now_ms)
  duration=$((scan_ended - scan_started))
  ((duration >= 0)) || duration=0

  local total_count open_count closed_count filtered_count
  total_count=$(wc -l < "$RESULTS_SORTED")
  open_count=$(awk -F "$DELIM" '$3 == "open" { count++ } END { print count + 0 }' "$RESULTS_SORTED")
  closed_count=$(awk -F "$DELIM" '$3 == "closed" { count++ } END { print count + 0 }' "$RESULTS_SORTED")
  filtered_count=$(awk -F "$DELIM" '$3 == "filtered" { count++ } END { print count + 0 }' "$RESULTS_SORTED")

  [[ -z $JSON_PATH ]] || write_json_report "$JSON_PATH" "$duration" "$open_count" "$total_count"
  [[ -z $CSV_PATH ]] || write_csv_report "$CSV_PATH"
  [[ -z $TXT_PATH ]] || write_txt_report "$TXT_PATH" "$duration" "$open_count" "$total_count"

  if ((QUIET == 0)); then
    printf '\n%sTamamlandı:%s %s deneme, %s açık port, %sms\n' \
      "$C_CYAN" "$C_RESET" "$total_count" "$open_count" "$duration"
    printf 'Durumlar: open=%s, closed=%s, filtered=%s\n' "$open_count" "$closed_count" "$filtered_count"
    [[ -z $JSON_PATH ]] || printf 'JSON: %s\n' "$JSON_PATH"
    [[ -z $CSV_PATH ]] || printf 'CSV: %s\n' "$CSV_PATH"
    [[ -z $TXT_PATH ]] || printf 'TXT: %s\n' "$TXT_PATH"
  fi

  if ((FAIL_ON_OPEN == 1 && open_count > 0)); then
    return 10
  fi
  return 0
}

main() {
  parse_args "$@"
  validate_config
  check_runtime
  setup_colors
  load_targets
  build_ports
  run_scan
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi
