#!/usr/bin/env bash
# Phase 4: Identity-Aware VPN via EAP-TLS (no RADIUS) – Server setup
# Host: AWS VPN node (Ubuntu 22.04)
# Creates RootCA + AdminCA + BranchCA, server cert, StrongSwan conns, RBAC, and client .p12 bundles

set -euo pipefail

### ========= EDITABLE VARS (if you need) =========
AWS_PUBLIC_IP="23.22.187.122"
AWS_PRIVATE_IP="172.31.87.210"
AWS_SUBNET_CIDR="172.31.0.0/16"
AZURE_SUBNETS=("10.0.0.0/24" "10.1.0.0/24")   # add/remove as needed

ADMIN_POOL="10.99.0.0/29"         # admins pool  (8 IPs: .0-.7)
BRANCH_POOL="10.99.0.128/29"      # branch pool  (8 IPs: .128-.135)

ALICE_P12_PASS="alicepass"
BOB_P12_PASS="bobpass"

# Where to drop the generated client bundles on the server
OUTDIR="$HOME/eaptls_bundles"
### ==============================================

# ---- helpers ----
GREEN="$(tput setaf 2 || true)"; RED="$(tput setaf 1 || true)"; YELLOW="$(tput setaf 3 || true)"; RESET="$(tput sgr0 || true)"
log(){ echo -e "${YELLOW}[INFO]${RESET} $*"; }
ok(){ echo -e "${GREEN}[OK]${RESET} $*"; }
fail(){ echo -e "${RED}[FAIL]${RESET} $*"; exit 1; }
trap 'echo -e "'"${RED}[ERROR]${RESET} Something went wrong. Check output above."'"' ERR

log "Phase 4 (EAP-TLS) starting on AWS VPN node…"

# 0) Pre-flight
log "Verifying we are on Ubuntu and have sudo…"
source /etc/os-release || true
command -v sudo >/dev/null || fail "sudo not found"
ok "Sudo available."

# 1) Packages
log "Installing required packages: strongSwan + PKI + iptables-persistent…"
sudo apt-get update -y
sudo apt-get install -y strongswan strongswan-pki libcharon-extra-plugins iptables-persistent openssl >/dev/null
ok "Packages installed."

# 2) Enable IPv4 forwarding (persist)
log "Enabling IPv4 forwarding…"
sudo bash -c 'cat >/etc/sysctl.d/99-ipsec-eaptls.conf' <<EOF
net.ipv4.ip_forward=1
net.ipv4.conf.all.accept_redirects=0
net.ipv4.conf.all.send_redirects=0
net.ipv4.conf.all.rp_filter=0
EOF
sudo sysctl --system >/dev/null
ok "Kernel forwarding ready."

# 3) PKI: Root CA, AdminCA, BranchCA, Server cert
log "Setting up CAs and server certificate…"
pushd /etc/ipsec.d >/dev/null
sudo mkdir -p private certs cacerts
TMPDIR="$(mktemp -d)"

# RootCA
ipsec pki --gen --outform pem > "$TMPDIR/rootKey.pem"
ipsec pki --self --in "$TMPDIR/rootKey.pem" --dn "CN=Hybrid Root CA" --ca --outform pem > "$TMPDIR/rootCert.pem"
sudo install -m600 "$TMPDIR/rootKey.pem" /etc/ipsec.d/private/rootKey.pem
sudo install -m644 "$TMPDIR/rootCert.pem" /etc/ipsec.d/cacerts/rootCert.pem

# AdminCA
ipsec pki --gen --outform pem > "$TMPDIR/adminCA.key"
ipsec pki --issue --in "$TMPDIR/adminCA.key" --type rsa --cacert "$TMPDIR/rootCert.pem" --cakey "$TMPDIR/rootKey.pem" \
  --dn "CN=Admin CA" --ca --outform pem > "$TMPDIR/adminCA.crt"
sudo install -m600 "$TMPDIR/adminCA.key" /etc/ipsec.d/private/adminCA.key
sudo install -m644 "$TMPDIR/adminCA.crt" /etc/ipsec.d/cacerts/adminCA.crt

# BranchCA
ipsec pki --gen --outform pem > "$TMPDIR/branchCA.key"
ipsec pki --issue --in "$TMPDIR/branchCA.key" --type rsa --cacert "$TMPDIR/rootCert.pem" --cakey "$TMPDIR/rootKey.pem" \
  --dn "CN=Branch CA" --ca --outform pem > "$TMPDIR/branchCA.crt"
sudo install -m600 "$TMPDIR/branchCA.key" /etc/ipsec.d/private/branchCA.key
sudo install -m644 "$TMPDIR/branchCA.crt" /etc/ipsec.d/cacerts/branchCA.crt

# Server cert (CN = AWS public IP)
ipsec pki --gen --outform pem > "$TMPDIR/serverKey.pem"
ipsec pki --pub --in "$TMPDIR/serverKey.pem" | ipsec pki --issue --cacert "$TMPDIR/rootCert.pem" --cakey "$TMPDIR/rootKey.pem" \
  --dn "CN=$AWS_PUBLIC_IP" --san "$AWS_PUBLIC_IP" --flag serverAuth --outform pem > "$TMPDIR/serverCert.pem"
sudo install -m600 "$TMPDIR/serverKey.pem" /etc/ipsec.d/private/serverKey.pem
sudo install -m644 "$TMPDIR/serverCert.pem" /etc/ipsec.d/certs/serverCert.pem
ok "PKI created (RootCA, AdminCA, BranchCA, server cert)."

# 4) StrongSwan profiles (append role conns) – backup first
log "Backing up /etc/ipsec.conf and writing role-based EAP-TLS connections…"
sudo cp -a /etc/ipsec.conf /etc/ipsec.conf.bak.$(date +%s)
sudo awk -v pub="$AWS_PUBLIC_IP" -v admin_pool="$ADMIN_POOL" -v branch_pool="$BRANCH_POOL" '
  BEGIN{printed=0}
  {print}
  END{
    print "";
    print "# ---- BEGIN EAP-TLS ROLE CONNS (generated) ----";
    print "conn rw-admins";
    print "  keyexchange=ikev2";
    print "  auto=add";
    print "  left=%any";
    print "  leftid=" pub;
    print "  leftauth=pubkey";
    print "  leftcert=/etc/ipsec.d/certs/serverCert.pem";
    print "  leftsubnet=0.0.0.0/0";
    print "  right=%any";
    print "  rightauth=eap-tls";
    print "  rightca=/etc/ipsec.d/cacerts/adminCA.crt";
    print "  rightsourceip=" admin_pool;
    print "  ike=aes256-sha256-modp2048!";
    print "  esp=aes256-sha256!";
    print "  dpdaction=clear";
    print "  dpddelay=30s";
    print "";
    print "conn rw-branch";
    print "  keyexchange=ikev2";
    print "  auto=add";
    print "  left=%any";
    print "  leftid=" pub;
    print "  leftauth=pubkey";
    print "  leftcert=/etc/ipsec.d/certs/serverCert.pem";
    print "  leftsubnet=0.0.0.0/0";
    print "  right=%any";
    print "  rightauth=eap-tls";
    print "  rightca=/etc/ipsec.d/cacerts/branchCA.crt";
    print "  rightsourceip=" branch_pool;
    print "  ike=aes256-sha256-modp2048!";
    print "  esp=aes256-sha256!";
    print "  dpdaction=clear";
    print "  dpddelay=30s";
    print "# ---- END EAP-TLS ROLE CONNS (generated) ----";
  }' /etc/ipsec.conf | sudo tee /etc/ipsec.conf >/dev/null
ok "StrongSwan EAP-TLS profiles added (rw-admins/rw-branch)."

# 5) RBAC via iptables (pools -> allowed CIDRs)
log "Applying RBAC firewall rules (iptables)…"
# allow established
sudo iptables -C FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || \
sudo iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT

# Admin pool full access
sudo iptables -C FORWARD -s "$ADMIN_POOL" -j ACCEPT 2>/dev/null || \
sudo iptables -A FORWARD -s "$ADMIN_POOL" -j ACCEPT

# Branch pool limited access
for cidr in "$AWS_SUBNET_CIDR" "${AZURE_SUBNETS[@]}"; do
  sudo iptables -C FORWARD -s "$BRANCH_POOL" -d "$cidr" -j ACCEPT 2>/dev/null || \
  sudo iptables -A FORWARD -s "$BRANCH_POOL" -d "$cidr" -j ACCEPT
done
sudo iptables -C FORWARD -s "$BRANCH_POOL" -j DROP 2>/dev/null || \
sudo iptables -A FORWARD -s "$BRANCH_POOL" -j DROP

# persist
sudo netfilter-persistent save >/dev/null || sudo sh -c 'iptables-save > /etc/iptables/rules.v4'
ok "RBAC rules installed and persisted."

# 6) Restart StrongSwan
log "Restarting strongSwan…"
sudo systemctl restart strongswan
sleep 1
sudo ipsec statusall | sed -n '1,120p' || true
ok "strongSwan restarted."

# 7) Generate client bundles (.p12) for Alice(admin) and Bob(branch)
log "Generating client .p12 bundles for alice (AdminCA) and bob (BranchCA)…"
mkdir -p "$OUTDIR"

# Alice (admin)
ipsec pki --gen --outform pem > "$TMPDIR/alice.key"
ipsec pki --pub --in "$TMPDIR/alice.key" | ipsec pki --issue \
  --cacert /etc/ipsec.d/cacerts/adminCA.crt --cakey /etc/ipsec.d/private/adminCA.key \
  --dn "CN=alice, OU=admins" --outform pem > "$TMPDIR/alice.crt"
openssl pkcs12 -export -inkey "$TMPDIR/alice.key" -in "$TMPDIR/alice.crt" -certfile /etc/ipsec.d/cacerts/adminCA.crt \
  -name alice -passout pass:"$ALICE_P12_PASS" -out "$OUTDIR/alice.p12" >/dev/null

# Bob (branch)
ipsec pki --gen --outform pem > "$TMPDIR/bob.key"
ipsec pki --pub --in "$TMPDIR/bob.key" | ipsec pki --issue \
  --cacert /etc/ipsec.d/cacerts/branchCA.crt --cakey /etc/ipsec.d/private/branchCA.key \
  --dn "CN=bob, OU=branch" --outform pem > "$TMPDIR/bob.crt"
openssl pkcs12 -export -inkey "$TMPDIR/bob.key" -in "$TMPDIR/bob.crt" -certfile /etc/ipsec.d/cacerts/branchCA.crt \
  -name bob -passout pass:"$BOB_P12_PASS" -out "$OUTDIR/bob.p12" >/dev/null

# Export CA certs for clients
cp /etc/ipsec.d/cacerts/adminCA.crt "$OUTDIR/adminCA.crt"
cp /etc/ipsec.d/cacerts/branchCA.crt "$OUTDIR/branchCA.crt"
ok "Client bundles created in: $OUTDIR"

popd >/dev/null

# 8) Final summary
echo
ok "PHASE 4 (EAP-TLS) – SERVER SETUP COMPLETE ✅"
echo -e "${YELLOW}Next steps on the CLIENT (Azure branch node)${RESET}"
cat <<NEXT

1) Copy the needed files from the AWS VPN node to your client:
   - For ADMIN user (alice):
       scp $OUTDIR/alice.p12 adminCA.crt ubuntu@<AZURE_BRANCH_PUBLIC_IP>:/home/ubuntu/
       (password for alice.p12 = "$ALICE_P12_PASS")
   - For BRANCH user (bob):
       scp $OUTDIR/bob.p12   branchCA.crt ubuntu@<AZURE_BRANCH_PUBLIC_IP>:/home/ubuntu/
       (password for bob.p12   = "$BOB_P12_PASS")

2) Then run the client-side script (I’ll paste it below) on the Azure branch node,
   choosing either 'admin' (alice) or 'branch' (bob).
NEXT
