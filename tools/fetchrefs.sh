#!/bin/sh
# Downloads external reference files into tests/refs and verifies SHA-256.
set -e
cd "$(dirname "$0")/.."
mkdir -p tests/refs
fetch() { # url file sha256
  if [ ! -f "tests/refs/$2" ] || [ "$(shasum -a 256 "tests/refs/$2" | cut -d' ' -f1)" != "$3" ]; then
    curl -sSfL -m 120 -o "tests/refs/$2" "$1"
  fi
  got=$(shasum -a 256 "tests/refs/$2" | cut -d' ' -f1)
  if [ "$got" != "$3" ]; then echo "checksum mismatch for $2: $got" >&2; exit 1; fi
}
fetch https://speleotrove.com/decimal/dectest.zip dectest.zip b70a224cd52e82b7a8150aedac5efa2d0cb3941696fd829bdbe674f9f65c3926
fetch https://www.angio.net/pi/digits/10000.txt pi10000.txt 1f08958df70c30bbf3f7205ad5f9b2b9430e3378b4e4e6300063bd9fbd83d6e3
fetch https://oeis.org/A000796/b000796.txt b000796.txt f8772370d624d403f056e3e3d4aadb15fec135d5075b5506053eb86460f4e20b
fetch https://oeis.org/A000142/b000142.txt b000142.txt 9d872b96c262cc2fe3f854e1b06d6624d7b8fe2f5666ce37f98acb7f523289c3
fetch https://oeis.org/A001147/b001147.txt b001147.txt 3bdf1d3bf0bb5046308f5f496552d9d8f21280bb354d480c21f625e7925ab222
fetch https://oeis.org/A000984/b000984.txt b000984.txt 4f911fe749c2ceb35425d1dbdfd12a6c0ac68f24fddea021339dddcf54bb09d7
fetch https://oeis.org/A000108/b000108.txt b000108.txt 5623739c73b08deddc3cc2e9c670e231a56194eecabb88199a1cf4f0a0989e18
fetch https://oeis.org/A000040/b000040.txt b000040.txt ef3beecd3bca4a02ca5053e5a3afc3e0d69e43b49b9aaa91073fc4fb9e4d50de
if [ ! -d tests/refs/dectest ]; then
  mkdir -p tests/refs/dectest
  unzip -oq tests/refs/dectest.zip -d tests/refs/dectest
fi
echo "refs ok"
