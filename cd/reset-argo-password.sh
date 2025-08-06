#!/bin/bash
# Generate bcrypt password
# https://github.com/argoproj/argo-cd/blob/master/docs/faq.md#i-forgot-the-admin-password-how-do-i-reset-it

INPUT="$1"

[ -n "$INPUT" ] || { echo "Usage: $0 <password>"; exit 1; }
export INPUT

if [ -x "$(command -v argocd)" ]; then
  PASSWORD=$(argocd account bcrypt --password $INPUT)
else
  cat > pass.py <<EOF
import getpass
import bcrypt
import os

# password = getpass.getpass("password: ")
password = os.getenv("INPUT")
hashed_password = bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt())
print(hashed_password.decode())
EOF
  PASSWORD=$(python pass.py)
  rm pass.py
fi

kubectl -n argocd patch secret argocd-secret -p '
{
  "stringData": {
    "admin.password": "'$PASSWORD'",
    "admin.passwordMtime": "'$(date +%FT%T%Z)'"
  }
}'
