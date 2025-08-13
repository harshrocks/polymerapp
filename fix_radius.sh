#!/usr/bin/env bash
# FreeRADIUS + EAP + LDAP one-shot fixer

LDAP_SERVER="127.0.0.1"
LDAP_BASE_DN="dc=ec2,dc=internal"
LDAP_BIND_DN="cn=admin,dc=ec2,dc=internal"
LDAP_BIND_PASS="admin123"

TEST_USER1_CN="alice"
TEST_USER1_PASS="Alice@123"
TEST_USER2_CN="bob"
TEST_USER2_PASS="Bob@123"

set -u
FAIL=0
LOG="/tmp/freeradius_fix_$(date +%Y%m%d_%H%M%S).log"

green() { printf "\033[32m%s\033[0m\n" "$*"; }
red()   { printf "\033[31m%s\033[0m\n" "$*"; }
yellow(){ printf "\033[33m%s\033[0m\n" "$*"; }

run_step() {
  local title="$1"
  shift
  echo "----------------------------------------------------------------" | tee -a "$LOG"
  echo "STEP: $title" | tee -a "$LOG"
  bash -c "$@" >>"$LOG" 2>&1
  local rc=$?
  if [ $rc -eq 0 ]; then
    green "OK: $title"
  else
    red   "FAILED ($rc): $title"
    yellow "See log: $LOG"
    FAIL=1
  fi
  return $rc
}

echo "FreeRADIUS EAP+LDAP fixer started at $(date)" >"$LOG"

run_step "Stop FreeRADIUS" "sudo systemctl stop freeradius || true"
run_step "Backup /etc/freeradius/3.0" 'sudo mkdir -p /root/radius-backup && sudo cp -a /etc/freeradius/3.0 /root/radius-backup/3.0.$(date +%s)'
run_step "apt update" "sudo apt-get update -y"
run_step "Reinstall freeradius-config" "sudo apt-get --reinstall install -y freeradius-config"
run_step "Install core packages" "sudo apt-get install -y freeradius freeradius-ldap freeradius-utils ssl-cert"
run_step "Set module libdir" "sudo sed -i 's|^#\\?libdir =.*|libdir = /usr/lib/freeradius/3.0|' /etc/freeradius/3.0/radiusd.conf"
run_step "Check rlm_update exists" "test -f /usr/lib/freeradius/3.0/rlm_update.so"
run_step "Enable stock sites (default, inner-tunnel)" '
  sudo rm -f /etc/freeradius/3.0/sites-enabled/* &&
  sudo ln -s /etc/freeradius/3.0/sites-available/default     /etc/freeradius/3.0/sites-enabled/default &&
  sudo ln -s /etc/freeradius/3.0/sites-available/inner-tunnel /etc/freeradius/3.0/sites-enabled/inner-tunnel &&
  grep -n "Auth-Type EAP" /etc/freeradius/3.0/sites-available/default /etc/freeradius/3.0/sites-available/inner-tunnel >/dev/null
'
run_step "Enable EAP module" "sudo ln -sf /etc/freeradius/3.0/mods-available/eap /etc/freeradius/3.0/mods-enabled/eap"
run_step "Set EAP default to TTLS" "sudo sed -i 's/^\\s*default_eap_type\\s*=.*/        default_eap_type = ttls/' /etc/freeradius/3.0/mods-available/eap"
run_step "Ensure EAP TLS cert paths" '
  sudo sed -i "s|^\\s*#\\s*tls\\s*{|        tls {|" /etc/freeradius/3.0/mods-available/eap &&
  sudo sed -i "s|^\\s*#\\s*private_key_password =.*|        private_key_password = whatever|" /etc/freeradius/3.0/mods-available/eap &&
  sudo sed -i "s|^\\s*#\\s*private_key_file =.*|        private_key_file = /etc/ssl/private/ssl-cert-snakeoil.key|" /etc/freeradius/3.0/mods-available/eap &&
  sudo sed -i "s|^\\s*#\\s*certificate_file =.*|        certificate_file = /etc/ssl/certs/ssl-cert-snakeoil.pem|" /etc/freeradius/3.0/mods-available/eap &&
  sudo sed -i "s|^\\s*#\\s*ca_file =.*|        ca_file = /etc/ssl/certs/ca-certificates.crt|" /etc/freeradius/3.0/mods-available/eap
'
run_step "Write LDAP module config" "
  sudo tee /etc/freeradius/3.0/mods-available/ldap >/dev/null <<'EOF'
ldap {
        server   = \"$LDAP_SERVER\"
        identity = \"$LDAP_BIND_DN\"
        password = $LDAP_BIND_PASS
        base_dn  = \"$LDAP_BASE_DN\"
        user {
                filter = \"(cn=%{%{Stripped-User-Name}:-%{User-Name}})\"
        }
        update {
                control:Password-With-Header := \"userPassword\"
        }
        group {
                base_dn = \"ou=groups,$LDAP_BASE_DN\"
                name_attribute = cn
                membership_attribute = member
        }
}
EOF
"
run_step "Enable LDAP module" "sudo ln -sf /etc/freeradius/3.0/mods-available/ldap /etc/freeradius/3.0/mods-enabled/ldap"
run_step "DEFAULT: add ldap to authorize" '
  sudo awk '\''BEGIN{done=0}
    {print}
    /authorize *\{/ && !done {print "        ldap"; done=1}
  '\'' /etc/freeradius/3.0/sites-available/default | sudo tee /etc/freeradius/3.0/sites-available/default >/dev/null
'
run_step "DEFAULT: ensure Auth-Type LDAP block" '
  sudo awk '\''BEGIN{in_auth=0;have=0}
    /authenticate *\{/ {in_auth=1}
    in_auth && /Auth-Type LDAP/ {have=1}
    {print}
    in_auth && /^\}/ && !have {print "        Auth-Type LDAP {\n                ldap\n        }"; have=1; in_auth=0}
  '\'' /etc/freeradius/3.0/sites-available/default | sudo tee /etc/freeradius/3.0/sites-available/default >/dev/null
'
run_step "INNER-TUNNEL: add ldap to authorize" '
  sudo awk '\''BEGIN{done=0}
    {print}
    /authorize *\{/ && !done {print "        ldap"; done=1}
  '\'' /etc/freeradius/3.0/sites-available/inner-tunnel | sudo tee /etc/freeradius/3.0/sites-available/inner-tunnel >/dev/null
'
run_step "INNER-TUNNEL: ensure Auth-Type LDAP block" '
  sudo awk '\''BEGIN{in_auth=0;have=0}
    /authenticate *\{/ {in_auth=1}
    in_auth && /Auth-Type LDAP/ {have=1}
    {print}
    in_auth && /^\}/ && !have {print "        Auth-Type LDAP {\n                ldap\n        }"; have=1; in_auth=0}
  '\'' /etc/freeradius/3.0/sites-available/inner-tunnel | sudo tee /etc/freeradius/3.0/sites-available/inner-tunnel >/dev/null
'
run_step "Validate with freeradius -CX" "sudo freeradius -CX"
run_step "Start FreeRADIUS" "sudo systemctl restart freeradius"
run_step "Service status" "sudo systemctl status freeradius --no-pager"
run_step "RADIUS test: $TEST_USER1_CN" "echo 'User-Name = $TEST_USER1_CN, User-Password = $TEST_USER1_PASS' | radclient -sx 127.0.0.1 auth testing123 >/dev/null"
run_step "RADIUS test: $TEST_USER2_CN" "echo 'User-Name = $TEST_USER2_CN, User-Password = $TEST_USER2_PASS' | radclient -sx 127.0.0.1 auth testing123 >/dev/null"

echo "----------------------------------------------------------------" | tee -a "$LOG"
if [ $FAIL -eq 0 ]; then
  green "🎉 CONGRATULATIONS: Script completed without errors."
  echo "Log: $LOG"
  exit 0
else
  red "Some steps failed. Please check the log: $LOG"
  echo "Tip: run 'sudo freeradius -X' to see live debug after fixing."
  exit 1
fi
