#!/usr/bin/env bash
#
# check_doh.sh —— 测一批 DoH 端点在本机是否可达，并对比解析结果
#
# 用法：
#   ./check_doh.sh                                  # 默认 example.com / A
#   ./check_doh.sh -d img.picacomic.com             # 指定域名
#   ./check_doh.sh -d picaapi.part26.art -r HTTPS   # 查 HTTPS 记录（看有没有 ech=）
#   ./check_doh.sh -p                               # 走环境变量里的代理再测（对比用）
#   ./check_doh.sh -t 3                             # 单次超时 3 秒
#
# 判读：
#   200/400/403  = 端点活着（400 通常是「不支持 JSON 接口」，TLS 是通的）
#   000          = 没连上（超时 / TLS 被 RST / DNS 失败）
#   耗时接近超时 = 被黑洞
#
# 默认 --noproxy '*'，测的是「直连可用性」；加 -p 则走 $HTTPS_PROXY / $ALL_PROXY。

set -u

TIMEOUT=5
USE_PROXY=0
DOMAIN="example.com"
RTYPE="A"

usage() {
  sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
}

while getopts ":t:d:r:ph" opt; do
  case "$opt" in
    t) TIMEOUT="$OPTARG" ;;
    d) DOMAIN="$OPTARG" ;;
    r) RTYPE="$OPTARG" ;;
    p) USE_PROXY=1 ;;
    h) usage ;;
    *) echo "未知参数: -$OPTARG（-h 看用法）" >&2; exit 2 ;;
  esac
done

CURL_OPTS=(-s -m "$TIMEOUT" -H 'accept: application/dns-json')
if [ "$USE_PROXY" -eq 0 ]; then
  CURL_OPTS+=(--noproxy '*')
fi

# 标签|基址|--resolve 参数（空 = 走系统 DNS 解析主机名）
ENDPOINTS=(
  "AliDNS 223.6.6.6|https://dns.alidns.com/dns-query|dns.alidns.com:443:223.6.6.6"
  "AliDNS 223.5.5.5|https://dns.alidns.com/dns-query|dns.alidns.com:443:223.5.5.5"
  "doh.pub 1.12.12.12|https://doh.pub/dns-query|doh.pub:443:1.12.12.12"
  "doh.pub 120.53.53.53|https://doh.pub/dns-query|doh.pub:443:120.53.53.53"
  "Cloudflare 1.1.1.1|https://cloudflare-dns.com/dns-query|cloudflare-dns.com:443:1.1.1.1"
  "Cloudflare 1.0.0.1|https://cloudflare-dns.com/dns-query|cloudflare-dns.com:443:1.0.0.1"
  "Google 8.8.8.8|https://dns.google/resolve|dns.google:443:8.8.8.8"
  "Quad9 9.9.9.9|https://dns.quad9.net/dns-query|dns.quad9.net:443:9.9.9.9"
  "AdGuard 94.140.14.14|https://dns.adguard-dns.com/dns-query|dns.adguard-dns.com:443:94.140.14.14"
  "DNS.SB 185.222.222.222|https://doh.dns.sb/dns-query|doh.dns.sb:443:185.222.222.222"
  "ControlD 76.76.2.0|https://freedns.controld.com/p0|freedns.controld.com:443:76.76.2.0"
  "Mullvad 194.242.2.2|https://dns.mullvad.net/dns-query|dns.mullvad.net:443:194.242.2.2"
  "NextDNS 45.90.28.0|https://dns.nextdns.io|dns.nextdns.io:443:45.90.28.0"
  "IIJ 103.2.57.5|https://public.dns.iij.jp/dns-query|public.dns.iij.jp:443:103.2.57.5"
  "LibreDNS 116.202.176.26|https://doh.libredns.gr/dns-query|doh.libredns.gr:443:116.202.176.26"
  "TiarApp 103.16.102.35|https://doh.tiar.app/dns-query|doh.tiar.app:443:103.16.102.35"
)

BODY="$(mktemp 2>/dev/null || echo "/tmp/check_doh_body.$$")"
trap 'rm -f "$BODY"' EXIT

if [ "$USE_PROXY" -eq 1 ]; then
  MODE="走代理（${HTTPS_PROXY:-${ALL_PROXY:-未设置}}）"
else
  MODE="直连（--noproxy '*'）"
fi

printf '域名: %s   类型: %s   超时: %ss   模式: %s\n\n' "$DOMAIN" "$RTYPE" "$TIMEOUT" "$MODE"
printf '%-24s %-7s %-10s %s\n' "ENDPOINT" "STATUS" "TIME" "ANSWERS"
printf '%s\n' "-------------------------------------------------------------------------"

REACHABLE=0
TOTAL=0
ANSWERS=""

for entry in "${ENDPOINTS[@]}"; do
  IFS='|' read -r label base resolve <<< "$entry"
  TOTAL=$((TOTAL + 1))
  url="${base}?name=${DOMAIN}&type=${RTYPE}"

  args=("${CURL_OPTS[@]}" -o "$BODY" -w '%{http_code} %{time_total}')
  [ -n "$resolve" ] && args+=(--resolve "$resolve")

  out="$(curl "${args[@]}" "$url" 2>/dev/null || true)"
  code="$(printf '%s' "$out" | awk '{print $1}')"
  secs="$(printf '%s' "$out" | awk '{print $2}')"
  [ -z "$code" ] && code="000"
  [ -z "$secs" ] && secs="-"

  answer="-"
  if [ "$code" != "000" ]; then
    REACHABLE=$((REACHABLE + 1))
    answer="$(grep -o '"data"[[:space:]]*:[[:space:]]*"[^"]*"' "$BODY" 2>/dev/null \
      | sed 's/.*"\([^"]*\)"$/\1/' | sort -u | paste -sd, -)"
    [ -z "$answer" ] && answer="-"
    ANSWERS="${ANSWERS}${answer}|${label}"$'\n'
  fi

  printf '%-24s %-7s %-10s %s\n' "$label" "$code" "${secs}s" "$answer"
done

printf '\n可达: %d / %d\n' "$REACHABLE" "$TOTAL"

# 答案对比：同一域名不同解析器给出的结果不一致，基本就是被投毒了。
if [ -n "$ANSWERS" ]; then
  printf '\n答案对比（同一答案的端点归为一组）：\n'
  printf '%s' "$ANSWERS" | awk -F'|' '$1 != "-" { print $1 "\t" $2 }' \
    | sort | awk -F'\t' '
      { if ($1 != prev) { if (prev != "") printf "  %-44s <- %s\n", prev, list; prev = $1; list = $2 }
        else list = list ", " $2 }
      END { if (prev != "") printf "  %-44s <- %s\n", prev, list }'
  printf '\n注：AliDNS 不支持 JSON 接口（状态 400、答案显示 -），要对比它的答案请用 wireformat：\n'
  printf "  curl -s --resolve dns.alidns.com:443:223.6.6.6 -H 'accept: application/dns-message' 'https://dns.alidns.com/dns-query?dns=<base64url>'\n"
  printf '（国内解析器对同一域名给出不同答案 = 递归层被投毒，DoH 也救不了）\n'
fi
