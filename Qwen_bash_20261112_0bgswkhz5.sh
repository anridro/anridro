#!/bin/bash
#################### x-ui-pro-refactor @ github.com/mozaroc #############################
[[ $EUID -ne 0 ]] && { echo "Run as root: sudo bash $0"; exit 1; }
# ─── Output helpers ──────────────────────────────────────────────────────────
msg_ok()  { echo -e "\e[1;42m $1 \e[0m"; }
msg_err() { echo -e "\e[1;41m $1 \e[0m"; }
msg_inf() { echo -e "\e[1;34m$1\e[0m"; }
echo; msg_inf '           ___    _   _   _  '
msg_inf      ' \/ __ | |  | __ |_) |_) / \ '
msg_inf      ' /\    |_| _|_   |   | \ \_/ '; echo
# ─── Pre-flight checks ───────────────────────────────────────────────────────
check_os() {
local os_id os_version
os_id=$(grep -oP '(?<=^ID=).+' /etc/os-release 2>/dev/null | tr -d '"')
os_version=$(grep -oP '(?<=^VERSION_ID=").+(?=")' /etc/os-release 2>/dev/null)
case "${os_id}" in
ubuntu)
[[ "$os_version" == "24.04" || "$os_version" == "26.04" ]] && return 0
;;
debian)
[[ "$os_version" == "12" || "$os_version" == "13" ]] && return 0
;;
esac
msg_err "Unsupported OS: ${os_id} ${os_version}"
echo -e "
This script supports:
Ubuntu 24.04 / 26.04
Debian 12 / 13"
exit 1
}
check_cpu() {
local cpu_model
cpu_model=$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2-)
if echo "$cpu_model" | grep -qi 'QEMU'; then
msg_err "QEMU virtual CPU detected!"
echo -e "Your VPS is running with an emulated QEMU processor."
echo -e "Please contact your hosting provider and ask them to switch the CPU type"
echo -e "to \e[1;33mhost-passthrough\e[0m (expose real CPU model to the VM)."
exit 1
fi
}
check_os
check_cpu
# ─── Constants ───────────────────────────────────────────────────────────────
XUIDB="/etc/x-ui/x-ui.db"
GITHUB_RAW="https://raw.githubusercontent.com/mozaroc/3x-ui-pro/main"
FAKE_SITE_COUNT=50
# ─── Default argument values ─────────────────────────────────────────────────
domain=""
reality_domain=""
UNINSTALL="x"
INSTALL="y"
AUTODOMAIN="n"
CFALLOW="n"
# ─── Stop & clean previous install ───────────────────────────────────────────
clean_previous_install() {
systemctl stop x-ui 2>/dev/null || true
rm -rf /etc/systemd/system/x-ui.service
rm -rf /usr/local/x-ui
rm -rf /etc/x-ui
rm -rf /etc/nginx/sites-enabled/*
rm -rf /etc/nginx/sites-available/*
rm -rf /etc/nginx/stream-enabled/*
}
# ─── Port / path generators ──────────────────────────────────────────────────
get_port() {
echo $(( ((RANDOM<<15)|RANDOM) % 49152 + 10000 ))
}
gen_random_string() {
local length="$1"
head -c 4096 /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c "$length"
echo
}
gen_group_id() {
head -c 4096 /dev/urandom | tr -dc 'a-z0-9' | head -c 16
echo
}
check_free() {
nc -z 127.0.0.1 "$1" &>/dev/null
return $?
}
make_port() {
while true; do
local PORT
PORT=$(get_port)
if ! check_free "$PORT"; then
echo "$PORT"
break
fi
done
}
# ─── Generate ports & paths ──────────────────────────────────────────────────
sub_port=$(make_port)
panel_port=$(make_port)
ws_port=$(make_port)
trojan_port=$(make_port)
hysteria2_port=$(make_port)
sub_path=$(gen_random_string 10)
json_path=$(gen_random_string 10)
panel_path=$(gen_random_string 10)
ws_path=$(gen_random_string 10)
trojan_path=$(gen_random_string 10)
xhttp_path=$(gen_random_string 10)
config_username=$(gen_random_string 10)
config_password=$(gen_random_string 10)
diag_path="/net-$(gen_random_string 12)/"
diag_token=$(gen_random_string 16)
mtr_backend_port=$(make_port)
hysteria2_password=$(gen_random_string 16)
hysteria2_obfs_password=$(gen_random_string 32)
# ─── Client names ────────────────────────────────────────────────────────────
CLIENT_NAMES=(
"s24" "S1" "i77700" "tab" "i14600" "tosha" "x3" "x4" "oculus"
"danil" "danil_pc" "vadim" "vadim_pc" "lilia" "artem" "artem_pc"
"art_x3" "art_x3_2" "sveta" "viktor" "viktor_pc" "victor_tab"
)
# ─── Argument parsing ────────────────────────────────────────────────────────
while [ "$#" -gt 0 ]; do
case "$1" in
-install)          INSTALL="$2";           shift 2 ;;
-subdomain)        domain="$2";            shift 2 ;;
-reality_domain)   reality_domain="$2";    shift 2 ;;
-ONLY_CF_IP_ALLOW) CFALLOW="$2";           shift 2 ;;
-version)          PANEL_VERSION="$2";     shift 2 ;;
-uninstall)        UNINSTALL="$2";         shift 2 ;;
*)                 shift 1 ;;
esac
done
# ─── Detect package manager ───────────────────────────────────────────────────
Pak=$(type apt &>/dev/null && echo "apt" || echo "yum")
# ─── UNINSTALL ───────────────────────────────────────────────────────────────
uninstall_xui() {
printf 'y\n' | x-ui uninstall 2>/dev/null || true
rm -rf /etc/x-ui/ /usr/local/x-ui/
rm -f  /usr/bin/x-ui
$Pak -y remove nginx nginx-common nginx-core nginx-full python3-certbot-nginx
$Pak -y purge  nginx nginx-common nginx-core nginx-full python3-certbot-nginx
$Pak -y autoremove
$Pak -y autoclean
rm -rf /var/www/html/ /var/www/diagnostics/ /var/www/subpage/ /etc/nginx/ /usr/share/nginx/
systemctl stop mtr-backend 2>/dev/null || true
systemctl disable mtr-backend 2>/dev/null || true
rm -f /etc/systemd/system/mtr-backend.service
rm -rf /usr/local/lib/3x-ui-pro/
systemctl daemon-reload 2>/dev/null || true
}
if [[ ${UNINSTALL} == *"y"* ]]; then
uninstall_xui
clear && msg_ok "Completely Uninstalled!" && exit 0
fi
# ─── GET SERVER IP ───────────────────────────────────────────────────────────
IP4_REGEX="^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$"
IP4=$(ip route get 8.8.8.8 2>&1 | grep -Po -- 'src \K\S*')
[[ $IP4 =~ $IP4_REGEX ]] || IP4=$(curl -s ipv4.icanhazip.com | tr -d '[:space:]')
# ─── DOMAIN VALIDATION ───────────────────────────────────────────────────────
validate_domains() {
while true; do
[[ -n "$domain" ]] && break
echo -en "Enter available subdomain (sub.domain.tld): " && read -r domain
done
domain=$(echo "$domain" | tr -d '[:space:]')
while true; do
[[ -n "$reality_domain" ]] && break
echo -en "Enter available subdomain for REALITY (sub.domain.tld): " && read -r reality_domain
done
reality_domain=$(echo "$reality_domain" | tr -d '[:space:]')
if [[ "$domain" == "$reality_domain" ]]; then
msg_err "Panel domain and REALITY domain must be different!"
exit 1
fi
}
# ─── INSTALL PACKAGES ────────────────────────────────────────────────────────
install_packages() {
ufw disable 2>/dev/null || true
if [[ ${INSTALL} == *"y"* ]]; then
$Pak -y update
$Pak -y install curl wget jq bash sudo nginx-full certbot python3-certbot-nginx sqlite3 ufw netcat-openbsd mtr python3 libcap2-bin
systemctl daemon-reload && systemctl enable --now nginx
fi
apt-get install -yqq --no-install-recommends ca-certificates
}
# ─── SSL CERTIFICATES ────────────────────────────────────────────────────────
get_ssl_certs() {
systemctl stop nginx 2>/dev/null || true
fuser -k 80/tcp 80/udp 443/tcp 443/udp 2>/dev/null || true
certbot certonly --standalone --non-interactive --agree-tos \
--register-unsafely-without-email -d "$domain"
if [[ ! -d "/etc/letsencrypt/live/${domain}/" ]]; then
systemctl start nginx >/dev/null 2>&1
msg_err "$domain SSL could not be generated!" && exit 1
fi
certbot certonly --standalone --non-interactive --agree-tos \
--register-unsafely-without-email -d "$reality_domain"
if [[ ! -d "/etc/letsencrypt/live/${reality_domain}/" ]]; then
systemctl start nginx >/dev/null 2>&1
msg_err "$reality_domain SSL could not be generated!" && exit 1
fi
mkdir -p /root/cert/${domain}
chmod 755 /root/cert/*
ln -sf /etc/letsencrypt/live/${domain}/fullchain.pem /root/cert/${domain}/fullchain.pem
ln -sf /etc/letsencrypt/live/${domain}/privkey.pem   /root/cert/${domain}/privkey.pem
}
# ─── CONFIGURE NGINX ─────────────────────────────────────────────────────────
configure_nginx() {
mkdir -p /etc/nginx/stream-enabled /etc/nginx/snippets
local ngx_ver http2_listen="" http2_on=""
ngx_ver=$(nginx -v 2>&1 | grep -oP '[0-9]+\.[0-9]+\.[0-9]+' || echo 0)
if [[ "$(printf '%s\n' 1.25.1 "$ngx_ver" | sort -V | head -1)" == "1.25.1" ]]; then
http2_on="http2 on;"
else
http2_listen=" http2"
fi
cat > /etc/nginx/stream-enabled/stream.conf <<EOF
map \$ssl_preread_server_name \$sni_name {
hostnames;
${reality_domain}    xray;
${domain}            www;
default              xray;
}
upstream xray { server 127.0.0.1:8443; }
upstream www  { server 127.0.0.1:7443; }
server {
proxy_protocol on;
set_real_ip_from unix:;
listen     443;
listen     [::]:443;
proxy_pass \$sni_name;
ssl_preread on;
}
EOF
grep -xqFR "stream { include /etc/nginx/stream-enabled/*.conf; }" /etc/nginx/* \
|| echo "stream { include /etc/nginx/stream-enabled/*.conf; }" >> /etc/nginx/nginx.conf
grep -xqFR "load_module modules/ngx_stream_module.so;" /etc/nginx/* \
|| sed -i '1s/^/load_module \/usr\/lib\/nginx\/modules\/ngx_stream_module.so; /' /etc/nginx/nginx.conf
grep -xqFR "worker_rlimit_nofile 16384;" /etc/nginx/* \
|| echo "worker_rlimit_nofile 16384;" >> /etc/nginx/nginx.conf
sed -i "/worker_connections/c\worker_connections 4096;" /etc/nginx/nginx.conf
cat > /etc/nginx/sites-available/80.conf <<EOF
server {
listen 80;
server_name ${domain} ${reality_domain};
return 301 https://\$host\$request_uri;
}
EOF
cat > /etc/nginx/snippets/includes.conf <<EOF
location /${sub_path}/ {
if (\$hack = 1) { return 404; }
proxy_redirect off;
proxy_set_header Host \$host;
proxy_set_header X-Real-IP \$remote_addr;
proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
proxy_pass https://127.0.0.1:${sub_port};
}
location = /${sub_path} {
if (\$hack = 1) { return 404; }
proxy_redirect off;
proxy_set_header Host \$host;
proxy_set_header X-Real-IP \$remote_addr;
proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
proxy_pass https://127.0.0.1:${sub_port};
}
location ~ ^/${sub_path}/(?<clash_sub_id>[^/]+)$ {
if (\$hack = 1) { return 404; }
if (\$serve_clash_yaml = 1) { rewrite ^ /__clash_api?sub_id=\$clash_sub_id last; }
proxy_redirect off;
proxy_set_header Host \$host;
proxy_set_header X-Real-IP \$remote_addr;
proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
proxy_pass https://127.0.0.1:${sub_port};
}
location /assets  { proxy_pass https://127.0.0.1:${sub_port}; }
location /assets/ { proxy_pass https://127.0.0.1:${sub_port}; }
location /${json_path} {
if (\$hack = 1) { return 404; }
proxy_redirect off;
proxy_set_header Host \$host;
proxy_set_header X-Real-IP \$remote_addr;
proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
proxy_pass https://127.0.0.1:${sub_port};
}
location /${json_path}/ {
if (\$hack = 1) { return 404; }
proxy_redirect off;
proxy_set_header Host \$host;
proxy_set_header X-Real-IP \$remote_addr;
proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
proxy_pass https://127.0.0.1:${sub_port};
}
location /${xhttp_path} {
grpc_pass grpc://unix:/dev/shm/uds2023.sock;
grpc_buffer_size      16k;
grpc_socket_keepalive on;
grpc_read_timeout     1h;
grpc_send_timeout     1h;
grpc_set_header Connection        "";
grpc_set_header X-Forwarded-For   \$proxy_add_x_forwarded_for;
grpc_set_header X-Forwarded-Proto \$scheme;
grpc_set_header X-Forwarded-Port  \$server_port;
grpc_set_header Host              \$host;
grpc_set_header X-Forwarded-Host  \$host;
}
location ~ ^/(?<fwdport>\d+)/(?<fwdpath>.*)\$ {
if (\$hack = 1) { return 404; }
client_max_body_size 0;
client_body_timeout 1d;
grpc_read_timeout 1d;
grpc_socket_keepalive on;
proxy_read_timeout 1d;
proxy_http_version 1.1;
proxy_buffering off;
proxy_request_buffering off;
proxy_socket_keepalive on;
proxy_set_header Upgrade \$http_upgrade;
proxy_set_header Connection "upgrade";
proxy_set_header Host \$host;
proxy_set_header X-Real-IP \$remote_addr;
proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
if (\$content_type ~* "GRPC") {
grpc_pass grpc://127.0.0.1:\$fwdport\$is_args\$args;
break;
}
if (\$http_upgrade ~* "(WEBSOCKET|WS)") {
proxy_pass http://127.0.0.1:\$fwdport\$is_args\$args;
break;
}
if (\$request_method ~* ^(PUT|POST|GET)\$) {
proxy_pass http://127.0.0.1:\$fwdport\$is_args\$args;
break;
}
}
location / { try_files \$uri \$uri/ =404; }
EOF
cat > /etc/nginx/sites-available/00-maps.conf <<EOF
map \$http_user_agent \$is_clash_ua {
~*(clash|clashx|clashn|mihomo|stash|surfboard)  1;
default                                          0;
}
map "\$is_clash_ua:\$arg_provider" \$serve_clash_yaml {
"1:"    1;
default 0;
}
EOF
cat > "/etc/nginx/sites-available/${domain}" <<EOF
limit_req_zone  \$binary_remote_addr zone=diag_api:10m  rate=6r/m;
limit_req_zone  \$binary_remote_addr zone=diag_page:10m rate=30r/m;
limit_conn_zone \$binary_remote_addr zone=per_ip:10m;
map \$cookie_diag_key \$diag_auth {
"${diag_token}" 1;
default          0;
}
server {
server_tokens off;
server_name ${domain};
listen 7443 ssl${http2_listen} proxy_protocol;
listen [::]:7443 ssl${http2_listen} proxy_protocol;
${http2_on}
index index.html index.htm index.php;
root /var/www/html/;
real_ip_header proxy_protocol;
set_real_ip_from 127.0.0.1;
absolute_redirect off;
http2_body_preread_size 128k;
client_body_buffer_size 512k;
ssl_protocols TLSv1.2 TLSv1.3;
ssl_ciphers HIGH:!aNULL:!eNULL:!MD5:!DES:!RC4:!ADH:!SSLv3:!EXP:!PSK:!DSS;
ssl_certificate     /etc/letsencrypt/live/${domain}/fullchain.pem;
ssl_certificate_key /etc/letsencrypt/live/${domain}/privkey.pem;
if (\$host !~* ^(.+\.)?${domain}\$)            { return 444; }
if (\$scheme ~* https)                          { set \$safe 1; }
if (\$ssl_server_name !~* ^(.+\.)?${domain}\$) { set \$safe "\${safe}0"; }
if (\$safe = 10)                                { return 444; }
if (\$request_uri ~ "(\"|'|\`|~|,|:|;|%|\\$|&&|\?\?|0x00|0X00|\||\\|\{|\}|\[|\]|<|>|\.\.\.|\.\.\/|\/\/\/)") { set \$hack 1; }
error_page 400 401 402 403 500 501 502 503 504 =404 /404;
proxy_intercept_errors on;
location /${panel_path}/ {
proxy_http_version 1.1;
proxy_set_header Upgrade \$http_upgrade;
proxy_set_header Connection "upgrade";
proxy_set_header Host \$host;
proxy_set_header X-Real-IP \$remote_addr;
proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto https;
proxy_read_timeout 3600s;
proxy_send_timeout 3600s;
proxy_pass https://127.0.0.1:${panel_port};
}
location /${panel_path} {
proxy_http_version 1.1;
proxy_set_header Upgrade \$http_upgrade;
proxy_set_header Connection "upgrade";
proxy_set_header Host \$host;
proxy_set_header X-Real-IP \$remote_addr;
proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto https;
proxy_read_timeout 3600s;
proxy_send_timeout 3600s;
proxy_pass https://127.0.0.1:${panel_port};
}
location = /${panel_path}/diag {
auth_request /__diag_auth;
error_page 401 403 = @diag_login;
try_files /__nonexistent @diag_sso_ok;
}
location @diag_login { return 302 /${panel_path}/; }
location @diag_sso_ok {
add_header Set-Cookie "diag_key=${diag_token}; Path=${diag_path}; Secure; HttpOnly; SameSite=Lax; Max-Age=604800";
return 302 ${diag_path};
}
location = /__diag_auth {
internal;
proxy_pass https://127.0.0.1:${panel_port}/${panel_path}/panel/;
proxy_http_version 1.1;
proxy_set_header Host \$host;
proxy_set_header X-Requested-With XMLHttpRequest;
proxy_pass_request_body off;
proxy_set_header Content-Length "";
proxy_intercept_errors on;
error_page 300 301 302 303 304 305 307 308 400 401 402 403 404 405 500 501 502 503 504 =401 @diag_denied;
}
location @diag_denied { return 401; }
location ^~ ${diag_path} {
if (\$diag_auth = 0) { return 302 /${panel_path}/diag; }
limit_req  zone=diag_page burst=10 nodelay;
limit_conn per_ip 5;
alias /var/www/diagnostics/;
index index.html;
try_files \$uri \$uri/ /index.html;
add_header Set-Cookie "diag_key=${diag_token}; Path=${diag_path}; Secure; HttpOnly; SameSite=Lax; Max-Age=604800" always;
add_header Cache-Control "no-store" always;
add_header X-Robots-Tag "noindex, nofollow" always;
}
location ^~ ${diag_path}api/mtr {
if (\$diag_auth = 0) { return 404; }
limit_req  zone=diag_api burst=2 nodelay;
limit_conn per_ip 2;
proxy_pass         http://127.0.0.1:${mtr_backend_port}/api/mtr;
proxy_http_version 1.1;
proxy_set_header   X-Real-IP       \$remote_addr;
proxy_set_header   X-Forwarded-For \$proxy_add_x_forwarded_for;
proxy_read_timeout 120s;
proxy_send_timeout 120s;
proxy_intercept_errors off;
}
location ^~ ${diag_path}api/st/up {
if (\$diag_auth = 0) { return 404; }
access_log              off;
limit_conn              per_ip 8;
proxy_pass              http://127.0.0.1:${mtr_backend_port}/api/st/up;
proxy_http_version      1.1;
proxy_set_header        X-Real-IP       \$remote_addr;
proxy_request_buffering off;
client_max_body_size    64m;
proxy_read_timeout      60s;
proxy_send_timeout      60s;
add_header              Cache-Control "no-store" always;
}
location = ${diag_path}api/st/ping {
if (\$diag_auth = 0) { return 404; }
access_log off;
limit_conn per_ip 8;
add_header Cache-Control "no-store" always;
default_type text/plain;
return 200 "";
}
location = ${diag_path}api/st/getip {
if (\$diag_auth = 0) { return 404; }
proxy_pass          http://127.0.0.1:${mtr_backend_port}/api/st/getip;
proxy_http_version  1.1;
proxy_set_header    X-Real-IP \$remote_addr;
add_header          Cache-Control "no-store" always;
}
location ^~ ${diag_path}testfiles/ {
if (\$diag_auth = 0) { return 404; }
alias      /var/www/diagnostics/testfiles/;
access_log off;
add_header Cache-Control "no-store, no-cache, must-revalidate" always;
add_header Content-Disposition "attachment" always;
}
location = /__clash_api {
internal;
proxy_pass          http://127.0.0.1:${mtr_backend_port}/api/clash\$is_args\$args;
proxy_http_version  1.1;
proxy_set_header    X-Real-IP \$remote_addr;
}
include /etc/nginx/snippets/includes.conf;
}
EOF
cat > "/etc/nginx/sites-available/${reality_domain}" <<EOF
server {
server_tokens off;
server_name ${reality_domain};
listen 9443 ssl${http2_listen};
listen [::]:9443 ssl${http2_listen};
${http2_on}
index index.html index.htm index.php;
root /var/www/html/;
ssl_protocols TLSv1.2 TLSv1.3;
ssl_ciphers HIGH:!aNULL:!eNULL:!MD5:!DES:!RC4:!ADH:!SSLv3:!EXP:!PSK:!DSS;
ssl_certificate     /etc/letsencrypt/live/${reality_domain}/fullchain.pem;
ssl_certificate_key /etc/letsencrypt/live/${reality_domain}/privkey.pem;
if (\$host !~* ^(.+\.)?${reality_domain}\$)            { return 444; }
if (\$scheme ~* https)                                  { set \$safe 1; }
if (\$ssl_server_name !~* ^(.+\.)?${reality_domain}\$) { set \$safe "\${safe}0"; }
if (\$safe = 10)                                        { return 444; }
if (\$request_uri ~ "(\"|'|\`|~|,|:|;|%|\\$|&&|\?\?|0x00|0X00|\||\\|\{|\}|\[|\]|<|>|\.\.\.|\.\.\/|\/\/\/)") { set \$hack 1; }
error_page 400 401 402 403 500 501 502 503 504 =404 /404;
proxy_intercept_errors on;
location /${panel_path}/ {
proxy_redirect off;
proxy_set_header Host \$host;
proxy_set_header X-Real-IP \$remote_addr;
proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
proxy_pass http://127.0.0.1:${panel_port};
}
location /${panel_path} {
proxy_redirect off;
proxy_set_header Host \$host;
proxy_set_header X-Real-IP \$remote_addr;
proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
proxy_pass http://127.0.0.1:${panel_port};
}
include /etc/nginx/snippets/includes.conf;
}
EOF
if [[ -f "/etc/nginx/sites-available/${domain}" ]]; then
rm -f /etc/nginx/sites-enabled/default /etc/nginx/sites-available/default
ln -sf "/etc/nginx/sites-available/00-maps.conf"       /etc/nginx/sites-enabled/
ln -sf "/etc/nginx/sites-available/${domain}"          /etc/nginx/sites-enabled/
ln -sf "/etc/nginx/sites-available/${reality_domain}"  /etc/nginx/sites-enabled/
ln -sf "/etc/nginx/sites-available/80.conf"            /etc/nginx/sites-enabled/
else
msg_err "${domain} nginx config not found!" && exit 1
fi
if [[ $(nginx -t 2>&1 | grep -o 'successful') != "successful" ]]; then
msg_err "nginx config check failed!" && exit 1
fi
systemctl start nginx
}
# ─── INSTALL PANEL (3x-ui) ───────────────────────────────────────────────────
_arch() {
case "$(uname -m)" in
x86_64|x64|amd64)          echo 'amd64'  ;;
i*86|x86)                  echo '386'    ;;
armv8*|armv8|arm64|aarch64) echo 'arm64' ;;
armv7*|armv7|arm)          echo 'armv7'  ;;
armv6*|armv6)              echo 'armv6'  ;;
armv5*|armv5)              echo 'armv5'  ;;
s390x)                     echo 's390x'  ;;
*) echo "Unsupported CPU architecture!" && exit 1 ;;
esac
}
_panel_initial_config() {
/usr/local/x-ui/x-ui setting -username "asdfasdf" -password "asdfasdf" -port "2096" -webBasePath "asdfasdf"
/usr/local/x-ui/x-ui migrate
}
install_panel() {
local tag_version
apt-get update && apt-get install -y -q wget curl tar tzdata
cd /usr/local/
if [[ -n "$PANEL_VERSION" ]]; then
tag_version="v${PANEL_VERSION#v}"
else
tag_version=$(curl -Ls "https://api.github.com/repos/MHSanaei/3x-ui/releases/latest" \
| grep -m1 '"tag_name":' | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/')
fi
echo "Installing 3x-ui ${tag_version} ..."
wget -N -O /usr/local/x-ui-linux-$(_arch).tar.gz \
"https://github.com/MHSanaei/3x-ui/releases/download/${tag_version}/x-ui-linux-$(_arch).tar.gz"
[[ $? -ne 0 ]] && echo "Download failed." && exit 1
wget -O /usr/bin/x-ui-temp https://raw.githubusercontent.com/MHSanaei/3x-ui/main/x-ui.sh
[[ -d /usr/local/x-ui/ ]] && systemctl stop x-ui 2>/dev/null; rm -rf /usr/local/x-ui/
tar zxvf x-ui-linux-$(_arch).tar.gz
rm -f x-ui-linux-$(_arch).tar.gz
cd x-ui
chmod +x x-ui x-ui.sh
if [[ $(_arch) == "armv5" || $(_arch) == "armv6" || $(_arch) == "armv7" ]]; then
mv bin/xray-linux-$(_arch) bin/xray-linux-arm
chmod +x bin/xray-linux-arm
fi
chmod +x bin/xray-linux-$(_arch)
mv -f /usr/bin/x-ui-temp /usr/bin/x-ui
chmod +x /usr/bin/x-ui
_panel_initial_config
cp -f x-ui.service.debian /etc/systemd/system/x-ui.service
systemctl daemon-reload
systemctl enable x-ui
systemctl start x-ui
msg_ok "3x-ui ${tag_version} installed."
}
# ─── CONFIGURE X-UI DATABASE ─────────────────────────────────────────────────
configure_xui_db() {
if [[ ! -f $XUIDB ]]; then
msg_err "x-ui.db not found — panel may not be installed." && exit 1
fi
x-ui stop 2>/dev/null || true
local output private_key public_key emoji_flag xray_bin
xray_bin="/usr/local/x-ui/bin/xray-linux-$(_arch)"
[[ -f "$xray_bin" ]] || xray_bin="/usr/local/x-ui/bin/xray-linux-arm"
output=$("$xray_bin" x25519)
private_key=$(echo "$output" | grep "^PrivateKey:" | awk '{print $2}')
public_key=$(echo "$output"  | grep "^PublicKey:" | awk '{print $2}')

declare -A client_uuids
for client_name in "${CLIENT_NAMES[@]}"; do
client_uuids[$client_name]=$(cat /proc/sys/kernel/random/uuid)
done

local vless_clients_json="["
local first=true
for client_name in "${CLIENT_NAMES[@]}"; do
[[ "$first" == "true" ]] && first=false || vless_clients_json+=","
vless_clients_json+="{\"id\": \"${client_uuids[$client_name]}\", \"flow\": \"xtls-rprx-vision\", \"email\": \"${client_name}\", \"limit\": 0, \"expiryTime\": 0, \"enable\": true, \"tgId\": \"\", \"subId\": \"${client_name}\", \"reset\": 0}"
done
vless_clients_json+="]"

local trojan_clients_json="["
first=true
for client_name in "${CLIENT_NAMES[@]}"; do
[[ "$first" == "true" ]] && first=false || trojan_clients_json+=","
trojan_clients_json+="{\"password\": \"${client_uuids[$client_name]}\", \"flow\": \"\", \"email\": \"${client_name}\", \"limit\": 0, \"expiryTime\": 0, \"enable\": true, \"tgId\": \"\", \"subId\": \"${client_name}\", \"reset\": 0}"
done
trojan_clients_json+="]"

local hysteria_clients_json="["
first=true
for client_name in "${CLIENT_NAMES[@]}"; do
[[ "$first" == "true" ]] && first=false || hysteria_clients_json+=","
hysteria_clients_json+="{\"auth\": \"${client_uuids[$client_name]}\", \"email\": \"${client_name}\"}"
done
hysteria_clients_json+="]"

local gid_col="" gid_reality="" gid_ws="" gid_xhttp="" gid_trojan="" gid_hysteria=""
if sqlite3 "$XUIDB" "PRAGMA table_info(hosts);" | grep -qw "group_id"; then
gid_col='"group_id",'
gid_reality="'$(gen_group_id)',"
gid_ws="'$(gen_group_id)',"
gid_xhttp="'$(gen_group_id)',"
gid_trojan="'$(gen_group_id)',"
gid_hysteria="'$(gen_group_id)',"
fi

emoji_flag=$(LC_ALL=en_US.UTF-8 curl -s --max-time 10 https://ipwho.is/ | jq -r '.flag.emoji' 2>/dev/null)
[[ -z "$emoji_flag" || "$emoji_flag" == "null" ]] && emoji_flag="🌐"
local sub_uri="https://${domain}/${sub_path}/"
local json_uri="https://${domain}/${json_path}?name="
local shor
shor=($(openssl rand -hex 8) $(openssl rand -hex 8) $(openssl rand -hex 8) $(openssl rand -hex 8) \
$(openssl rand -hex 8) $(openssl rand -hex 8) $(openssl rand -hex 8) $(openssl rand -hex 8))

sqlite3 $XUIDB <<EOF
DELETE FROM "settings" WHERE "key" IN ("webCertFile","webKeyFile");
INSERT INTO "settings" ("key","value") VALUES ("subPort", '${sub_port}');
UPDATE "settings" SET "value" = '/${sub_path}/' WHERE "key" = 'subPath';
INSERT INTO "settings" ("key","value") VALUES ("subURI", '${sub_uri}');
UPDATE "settings" SET "value" = '/${json_path}/' WHERE "key" = 'subJsonPath';
INSERT INTO "settings" ("key","value") VALUES ("subJsonURI", '${json_uri}');
INSERT INTO "settings" ("key","value") VALUES ("subClashEnable", 'false');
INSERT INTO "settings" ("key","value") VALUES ("subEnableRouting", 'false');
INSERT INTO "settings" ("key","value") VALUES ("subEnable", 'true');
INSERT INTO "settings" ("key","value") VALUES ("webListen", '');
INSERT INTO "settings" ("key","value") VALUES ("webDomain", '');
INSERT INTO "settings" ("key","value") VALUES ("webCertFile", '');
INSERT INTO "settings" ("key","value") VALUES ("webKeyFile", '');
INSERT INTO "settings" ("key","value") VALUES ("sessionMaxAge", '60');
INSERT INTO "settings" ("key","value") VALUES ("pageSize", '50');
INSERT INTO "settings" ("key","value") VALUES ("expireDiff", '0');
INSERT INTO "settings" ("key","value") VALUES ("trafficDiff", '0');
INSERT INTO "settings" ("key","value") VALUES ("remarkModel", '-ieo');
INSERT INTO "settings" ("key","value") VALUES ("tgBotEnable", 'false');
INSERT INTO "settings" ("key","value") VALUES ("tgBotToken", '');
INSERT INTO "settings" ("key","value") VALUES ("tgBotProxy", '');
INSERT INTO "settings" ("key","value") VALUES ("tgBotAPIServer", '');
INSERT INTO "settings" ("key","value") VALUES ("tgBotChatId", '');
INSERT INTO "settings" ("key","value") VALUES ("tgRunTime", '@daily');
INSERT INTO "settings" ("key","value") VALUES ("tgBotBackup", 'false');
INSERT INTO "settings" ("key","value") VALUES ("tgBotLoginNotify", 'true');
INSERT INTO "settings" ("key","value") VALUES ("tgCpu", '80');
INSERT INTO "settings" ("key","value") VALUES ("tgLang", 'en-US');
INSERT INTO "settings" ("key","value") VALUES ("timeLocation", 'Europe/Moscow');
INSERT INTO "settings" ("key","value") VALUES ("secretEnable", 'false');
INSERT INTO "settings" ("key","value") VALUES ("subDomain", '');
INSERT INTO "settings" ("key","value") VALUES ("subCertFile", '');
INSERT INTO "settings" ("key","value") VALUES ("subKeyFile", '');
INSERT INTO "settings" ("key","value") VALUES ("subUpdates", '12');
INSERT INTO "settings" ("key","value") VALUES ("subEncrypt", 'true');
INSERT INTO "settings" ("key","value") VALUES ("subShowInfo", 'true');
INSERT INTO "settings" ("key","value") VALUES ("subJsonFragment", '');
INSERT INTO "settings" ("key","value") VALUES ("subJsonNoises", '');
INSERT INTO "settings" ("key","value") VALUES ("subJsonMux", '');
INSERT INTO "settings" ("key","value") VALUES ("subJsonRules", '');
INSERT INTO "settings" ("key","value") VALUES ("datepicker", 'gregorian');

INSERT INTO "inbounds" ("user_id","up","down","total","remark","enable","expiry_time","listen","port","protocol","settings","stream_settings","tag","sniffing")
VALUES ('1','0','0','0','${emoji_flag} reality','1','0','','8443','vless',
'{"clients": ${vless_clients_json}, "decryption": "none", "fallbacks": []}',
'{"network": "tcp", "security": "reality", "realitySettings": {"show": false, "xver": 0, "target": "127.0.0.1:9443", "serverNames": ["${reality_domain}"], "privateKey": "${private_key}", "minClient": "", "maxClient": "", "maxTimediff": 0, "shortIds": ["${shor[0]}","${shor[1]}","${shor[2]}","${shor[3]}","${shor[4]}","${shor[5]}","${shor[6]}","${shor[7]}"], "settings": {"publicKey": "${public_key}", "fingerprint": "chrome", "serverName": "", "spiderX": "/"}}, "tcpSettings": {"acceptProxyProtocol": true, "header": {"type":"none"}}}',
'inbound-8443',
'{"enabled":false,"destOverride":["http","tls","quic","fakedns"],"metadataOnly":false,"routeOnly":false}');

INSERT INTO "inbounds" ("user_id","up","down","total","remark","enable","expiry_time","listen","port","protocol","settings","stream_settings","tag","sniffing")
VALUES ('1','0','0','0','${emoji_flag} ws','1','0','','${ws_port}','vless',
'{"clients": ${vless_clients_json}, "decryption": "none", "fallbacks": []}',
'{"network": "ws", "security": "none", "wsSettings": {"acceptProxyProtocol": false, "path": "/${ws_port}/${ws_path}", "host": "${domain}", "headers": {}}}',
'inbound-${ws_port}',
'{"enabled":false,"destOverride":["http","tls","quic","fakedns"],"metadataOnly":false,"routeOnly":false}');

INSERT INTO "inbounds" ("user_id","up","down","total","remark","enable","expiry_time","listen","port","protocol","settings","stream_settings","tag","sniffing")
VALUES ('1','0','0','0','${emoji_flag} xhttp','0','0','/dev/shm/uds2023.sock,0666','0','vless',
'{"clients": ${vless_clients_json}, "decryption": "none", "fallbacks": []}',
'{"network": "xhttp", "security": "none", "xhttpSettings": {"path": "/${xhttp_path}", "host": "${domain}", "headers": {}, "scMaxBufferedPosts": 30, "scMaxEachPostBytes": "1000000", "noSSEHeader": false, "xPaddingBytes": "100-1000", "mode": "packet-up"}, "sockopt": {"acceptProxyProtocol": false, "tcpFastOpen": true, "mark": 0, "tproxy": "off", "tcpMptcp": true, "tcpNoDelay": true, "domainStrategy": "UseIP", "tcpMaxSeg": 1440, "dialerProxy": "", "tcpKeepAliveInterval": 0, "tcpKeepAliveIdle": 300, "tcpUserTimeout": 10000, "tcpcongestion": "bbr", "V6Only": false, "tcpWindowClamp": 600, "interface": ""}}',
'inbound-/dev/shm/uds2023.sock,0666:0|',
'{"enabled":true,"destOverride":["http","tls","quic","fakedns"],"metadataOnly":false,"routeOnly":false}');

INSERT INTO "inbounds" ("user_id","up","down","total","remark","enable","expiry_time","listen","port","protocol","settings","stream_settings","tag","sniffing")
VALUES ('1','0','0','0','${emoji_flag} trojan-grpc','1','0','','${trojan_port}','trojan',
'{"clients": ${trojan_clients_json}, "fallbacks": []}',
'{"network": "grpc", "security": "none", "grpcSettings": {"serviceName": "/${trojan_port}/${trojan_path}", "authority": "${domain}", "multiMode": false}}',
'inbound-${trojan_port}',
'{"enabled":false,"destOverride":["http","tls","quic","fakedns"],"metadataOnly":false,"routeOnly":false}');

INSERT INTO "inbounds" ("user_id","up","down","total","remark","enable","expiry_time","listen","port","protocol","settings","stream_settings","tag","sniffing")
VALUES ('1','0','0','0','${emoji_flag} hysteria2','1','0','','${hysteria2_port}','hysteria',
'{"version": 2, "clients": ${hysteria_clients_json}}',
'{"network": "hysteria", "security": "tls", "tlsSettings": {"certificates": [{"certificateFile": "/etc/letsencrypt/live/${domain}/fullchain.pem", "keyFile": "/etc/letsencrypt/live/${domain}/privkey.pem"}]}, "hysteriaSettings": {"version": 2, "masquerade": {"type": "file", "dir": "/var/www/html"}}, "finalmask": {"udp": [{"type": "salamander", "settings": {"password": "${hysteria2_obfs_password}"}}]}}',
'inbound-${hysteria2_port}',
'{"enabled":true,"destOverride":["http","tls","quic","fakedns"],"metadataOnly":false,"routeOnly":false}');

INSERT INTO "hosts" ("inbound_id",${gid_col}"sort_order","remark","address","port","security","fingerprint","alpn")
VALUES
((SELECT id FROM inbounds WHERE tag='inbound-8443'), ${gid_reality} 0, 'reality', '${domain}', 443, 'same', '', '[]'),
((SELECT id FROM inbounds WHERE tag='inbound-${ws_port}'), ${gid_ws} 0, 'ws', '${domain}', 443, 'tls', 'chrome', '["h2","http/1.1"]'),
((SELECT id FROM inbounds WHERE tag='inbound-/dev/shm/uds2023.sock,0666:0|'), ${gid_xhttp} 0, 'xhttp', '${domain}', 443, 'tls', 'chrome', '["h2","http/1.1"]'),
((SELECT id FROM inbounds WHERE tag='inbound-${trojan_port}'), ${gid_trojan} 0, 'trojan', '${domain}', 443, 'tls', 'chrome', '["h2","http/1.1"]'),
((SELECT id FROM inbounds WHERE tag='inbound-${hysteria2_port}'), ${gid_hysteria} 0, 'hysteria2', '${domain}', ${hysteria2_port}, 'tls', 'chrome', '["h3"]');
EOF
/usr/local/x-ui/x-ui setting \
-username  "${config_username}" \
-password  "${config_password}" \
-port      "${panel_port}"      \
-webBasePath "${panel_path}"
/usr/local/x-ui/x-ui cert \
-webCert    "/root/cert/${domain}/fullchain.pem" \
-webCertKey "/root/cert/${domain}/privkey.pem"
x-ui start
}
# ─── INSTALL FAKE SITE & DIAGNOSTICS ─────────────────────────────────────────
install_clash_sub() {
local clash_dir="/var/www/subpage"
mkdir -p "${clash_dir}"
if curl -fsSL "${GITHUB_RAW}/assets/clash/clash.yaml" -o "${clash_dir}/clash.yaml.tpl"; then
sed -i "s|\${DOMAIN}|${domain}|g" "${clash_dir}/clash.yaml.tpl"
sed -i "s|\${SUB_PATH}|${sub_path}|g" "${clash_dir}/clash.yaml.tpl"
chown -R www-data:www-data "${clash_dir}" 2>/dev/null || true
chmod 644 "${clash_dir}/clash.yaml.tpl"
msg_ok "Clash subscription template installed."
fi
}
install_fake_site() {
local idx=$(( (RANDOM % FAKE_SITE_COUNT) + 1 ))
local site_id=$(printf "site-%02d" "$idx")
mkdir -p /var/www/html
if curl -fsSL "${GITHUB_RAW}/assets/fake-sites/${site_id}/index.html" -o /var/www/html/index.html; then
chown -R www-data:www-data /var/www/html 2>/dev/null || true
chmod 644 /var/www/html/index.html
msg_ok "Fake cover site '${site_id}' installed."
fi
}
install_diagnostics() {
local diag_webroot="/var/www/diagnostics"
local backend_script="/usr/local/lib/3x-ui-pro/mtr-backend.py"
mkdir -p "${diag_webroot}"
curl -fsSL "${GITHUB_RAW}/assets/diagnostics/index.html" -o "${diag_webroot}/index.html"
sed -i -e "s|__DIAG_PATH__|${diag_path}|g" -e "s|__SERVER_DOMAIN__|${domain}|g" -e "s|__SERVER_IP__|${IP4}|g" "${diag_webroot}/index.html"
curl -fsSL "${GITHUB_RAW}/assets/diagnostics/librespeed/speedtest.js" -o "${diag_webroot}/speedtest.js"
curl -fsSL "${GITHUB_RAW}/assets/diagnostics/librespeed/speedtest_worker.js" -o "${diag_webroot}/speedtest_worker.js"
local testfiles="${diag_webroot}/testfiles"
mkdir -p "${testfiles}"
[[ -f "${testfiles}/test-15k.bin"  ]] || dd if=/dev/zero bs=1024    count=15   of="${testfiles}/test-15k.bin"  status=none
[[ -f "${testfiles}/test-17k.bin"  ]] || dd if=/dev/zero bs=1024    count=17   of="${testfiles}/test-17k.bin"  status=none
[[ -f "${testfiles}/test-100m.bin" ]] || dd if=/dev/zero bs=1048576 count=100  of="${testfiles}/test-100m.bin" status=none
[[ -f "${testfiles}/test-1g.bin"   ]] || dd if=/dev/zero bs=1048576 count=1024 of="${testfiles}/test-1g.bin"   status=none
chown -R www-data:www-data "${diag_webroot}" 2>/dev/null || true
mkdir -p "$(dirname "${backend_script}")"
curl -fsSL "${GITHUB_RAW}/assets/diagnostics/mtr-backend.py" -o "${backend_script}"
chmod 755 "${backend_script}"
command -v setcap &>/dev/null && setcap cap_net_raw+ep "$(command -v mtr)"        2>/dev/null || true
command -v setcap &>/dev/null && setcap cap_net_raw+ep "$(command -v mtr-packet)" 2>/dev/null || true
id mtr-backend &>/dev/null || useradd --system --no-create-home --shell /usr/sbin/nologin mtr-backend
cat > /etc/systemd/system/mtr-backend.service <<EOF
[Unit]
Description=3x-ui-pro MTR diagnostics backend
After=network.target
[Service]
Type=simple
User=mtr-backend
Group=mtr-backend
ExecStart=/usr/bin/python3 ${backend_script} --port ${mtr_backend_port}
Restart=on-failure
RestartSec=5s
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=strict
ProtectHome=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectControlGroups=yes
RestrictAddressFamilies=AF_INET AF_INET6 AF_NETLINK
RestrictNamespaces=yes
LockPersonality=yes
MemoryDenyWriteExecute=yes
RestrictRealtime=yes
RestrictSUIDSGID=yes
RemoveIPC=yes
AmbientCapabilities=CAP_NET_RAW
CapabilityBoundingSet=CAP_NET_RAW
StandardOutput=journal
StandardError=journal
SyslogIdentifier=mtr-backend
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable mtr-backend
systemctl restart mtr-backend
msg_ok "Network diagnostics installed at https://${domain}/${panel_path}/diag"
}
# ─── SYSTEM TUNING ───────────────────────────────────────────────────────────
tune_system() {
local params=("net.core.default_qdisc=fq" "net.ipv4.tcp_congestion_control=bbr" "fs.file-max=2097152" "net.ipv4.tcp_timestamps=1" "net.ipv4.tcp_sack=1" "net.ipv4.tcp_window_scaling=1" "net.core.rmem_max=16777216" "net.core.wmem_max=16777216" "net.ipv4.tcp_rmem=4096 87380 16777216" "net.ipv4.tcp_wmem=4096 65536 16777216")
for p in "${params[@]}"; do
grep -qxF "$p" /etc/sysctl.conf || echo "$p" >> /etc/sysctl.conf
done
sysctl -p
}
# ─── CRON JOBS ───────────────────────────────────────────────────────────────
setup_cron() {
crontab -l 2>/dev/null | grep -v "certbot\|x-ui\|cloudflareips" | crontab -
(crontab -l 2>/dev/null; echo '@daily   x-ui restart > /dev/null 2>&1 && nginx -s reload') | crontab -
(crontab -l 2>/dev/null; echo '@monthly certbot renew --non-interactive --pre-hook "systemctl stop nginx" --post-hook "systemctl start nginx" > /dev/null 2>&1') | crontab -
}
# ─── FIREWALL ────────────────────────────────────────────────────────────────
setup_firewall() {
ufw disable
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 443/udp
ufw allow ${hysteria2_port}/udp
ufw --force enable
}
# ─── SHOW RESULTS ────────────────────────────────────────────────────────────
show_results() {
clear
if systemctl is-active --quiet x-ui; then
printf '0\n' | x-ui | grep --color=never -i ':'
msg_inf "────────────────────────────────────────────────────────────────────────────────"
msg_inf "X-UI Secure Panel: https://${domain}/${panel_path}/"
echo -e "Username:  ${config_username}\nPassword:  ${config_password}"
msg_inf "────────────────────────────────────────────────────────────────────────────────"
msg_inf "Created 22 clients with Flow xtls-rprx-vision:"
for client_name in "${CLIENT_NAMES[@]}"; do
echo -e "  ${client_name}: ${client_uuids[$client_name]}"
done
msg_inf "────────────────────────────────────────────────────────────────────────────────"
msg_inf "Hysteria2 Configuration:"
echo -e "Port:      ${hysteria2_port}/udp\nPassword:  ${hysteria2_password}\nObfs:      salamander\nObfs Pass: ${hysteria2_obfs_password}\nSNI:       ${domain}"
msg_inf "────────────────────────────────────────────────────────────────────────────────"
msg_inf "Network Diagnostics: https://${domain}/${panel_path}/diag"
msg_inf "Please save this screen!"
else
nginx -t
printf '0\n' | x-ui | grep --color=never -i ':'
msg_err "x-ui or nginx check failed."
fi
}
# ─── MAIN ────────────────────────────────────────────────────────────────────
main() {
validate_domains
clean_previous_install
install_packages
get_ssl_certs
if systemctl is-active --quiet x-ui; then
x-ui restart
else
install_panel
fi
configure_nginx
configure_xui_db
install_clash_sub
install_fake_site
install_diagnostics
tune_system
setup_cron
setup_firewall
systemctl daemon-reload && systemctl enable x-ui.service
x-ui restart
show_results
}
main