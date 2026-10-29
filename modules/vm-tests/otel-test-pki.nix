# Throwaway certificates for the container tests that run the ingress's
# otlp/mesh receiver: made at test build with openssl, the same P-256 keys
# and usages as the otel-ca and otel-cert generators, so no test reads the
# real vars. The output holds a test CA (`ca.crt`), the ingress's
# certificate (`ingress.{crt,key}`, SAN IP:127.0.0.1, serverAuth and
# clientAuth), an agent's (`agent.{crt,key}`, clientAuth), and a rogue CA
# (`rogue-ca.crt`) with a client certificate it signed (`rogue.{crt,key}`).
{ ... }:
{
  flake.lib.otelTestPki =
    pkgs:
    pkgs.runCommand "otel-test-pki" { nativeBuildInputs = [ pkgs.openssl ]; } ''
      mkdir -p "$out"
      key() { openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "$1"; }
      ca() {
        key "$1.key"
        openssl req -x509 -new -key "$1.key" -sha256 -days 3650 -subj "/CN=$1" \
          -addext "basicConstraints=critical,CA:TRUE" \
          -addext "keyUsage=critical,keyCertSign,cRLSign" -out "$out/$1.crt"
      }
      # issue <ca> <name> <usage> [<san>]
      issue() {
        key "$out/$2.key"
        openssl req -new -key "$out/$2.key" -subj "/CN=$2" -out "$2.csr"
        {
          echo "basicConstraints=critical,CA:FALSE"
          echo "keyUsage=critical,digitalSignature"
          echo "extendedKeyUsage=$3"
          if [ -n "''${4:-}" ]; then echo "subjectAltName=$4"; fi
        } > "$2.ext"
        openssl x509 -req -in "$2.csr" -CA "$out/$1.crt" -CAkey "$1.key" -set_serial "0x$(openssl rand -hex 16)" \
          -sha256 -days 3650 -extfile "$2.ext" -out "$out/$2.crt"
      }
      ca ca
      ca rogue-ca
      issue ca ingress serverAuth,clientAuth IP:127.0.0.1
      issue ca agent clientAuth
      issue rogue-ca rogue clientAuth
      chmod 0444 "$out"/*
    '';
}
