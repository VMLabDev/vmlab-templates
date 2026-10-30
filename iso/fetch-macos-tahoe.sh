#!/usr/bin/env bash
# Fetch the macOS Tahoe (26) Intel recovery image — the install media macOS
# vmlab templates boot — from Apple's Internet Recovery service, verify it
# against Apple's RSA-signed chunklist, and convert it to the raw disk QEMU
# attaches. macOS Tahoe 26 is the final Intel macOS.
#
# Outputs beside this script (gitignored, /iso/*):
#   macos-tahoe-recovery.dmg         Apple recovery image (~900 MB)
#   macos-tahoe-recovery.chunklist   Apple chunklist (per-chunk sha256 + RSA)
#   macos-tahoe-recovery.img         QEMU-bootable raw image (~2.5 GB;
#                                    skipped with NO_IMG=1)
#
# Tahoe's recovery is keyed to board-id Mac-CFF7D910A743CAAF. PRODUCT_PIN
# fixes which recovery build a fresh fetch accepts, since os=latest drifts
# as Apple ships updates: on a product mismatch the script prints what Apple
# served — bump the pin (and delete the cached dmg/chunklist) to adopt it.
# Set PRODUCT_PIN=any to accept whatever is served. Set NO_IMG=1 to skip
# the raw conversion: the macos-tahoe template boots the DMG itself through
# OpenCore and runs this with it.
#
# Chunklist verifier vendored from OpenCorePkg Utilities/macrecovery
# (vit9696), https://github.com/acidanthera/OpenCorePkg — stdlib Python.
#
# Needs: curl, openssl, python3, qemu-img. No Mac, no auth, no root.
set -euo pipefail
cd "$(dirname "$0")"
OUT_DIR="${OUT_DIR:-.}"

BOARD="Mac-CFF7D910A743CAAF"
OS_TYPE="latest"
PRODUCT_PIN="${PRODUCT_PIN:-140-93589}"   # Tahoe 26.7-era recovery
UA="InternetRecovery/1.0"

DMG="$OUT_DIR/macos-tahoe-recovery.dmg"
CNK="$OUT_DIR/macos-tahoe-recovery.chunklist"
IMG="$OUT_DIR/macos-tahoe-recovery.img"

verify_chunklist() {
    python3 - "$1" "$2" <<'PY'
import hashlib
import struct
import sys

# Apple EFI ROM public key — from OpenCorePkg macrecovery:
# https://gist.github.com/MCJack123/943eaca762730ca4b7ae460b731b68e7
Apple_EFI_ROM_public_key_1 = 0xC3E748CAD9CD384329E10E25A91E43E1A762FF529ADE578C935BDDF9B13F2179D4855E6FC89E9E29CA12517D17DFA1EDCE0BEBF0EA7B461FFE61D94E2BDF72C196F89ACD3536B644064014DAE25A15DB6BB0852ECBD120916318D1CCDEA3C84C92ED743FC176D0BACA920D3FCF3158AFF731F88CE0623182A8ED67E650515F75745909F07D415F55FC15A35654D118C55A462D37A3ACDA08612F3F3F6571761EFCCBCC299AEE99B3A4FD6212CCFFF5EF37A2C334E871191F7E1C31960E010A54E86FA3F62E6D6905E1CD57732410A3EB0C6B4DEFDABE9F59BF1618758C751CD56CEF851D1C0EAA1C558E37AC108DA9089863D20E2E7E4BF475EC66FE6B3EFDCF

ChunkListHeader = struct.Struct('<4sIBBBxQQQ')
assert ChunkListHeader.size == 0x24
Chunk = struct.Struct('<I32s')
assert Chunk.size == 0x24

def verify_chunklist(cnkpath):
    with open(cnkpath, 'rb') as f:
        hash_ctx = hashlib.sha256()
        data = f.read(ChunkListHeader.size)
        hash_ctx.update(data)
        magic, header_size, file_version, chunk_method, signature_method, chunk_count, chunk_offset, signature_offset = ChunkListHeader.unpack(data)
        assert magic == b'CNKL'
        assert header_size == ChunkListHeader.size
        assert file_version == 1
        assert chunk_method == 1
        assert signature_method in [1, 2]
        assert chunk_count > 0
        assert chunk_offset == 0x24
        assert signature_offset == chunk_offset + Chunk.size * chunk_count
        for _ in range(chunk_count):
            data = f.read(Chunk.size)
            hash_ctx.update(data)
            chunk_size, chunk_sha256 = Chunk.unpack(data)
            yield chunk_size, chunk_sha256
        digest = hash_ctx.digest()
        if signature_method == 1:
            data = f.read(256)
            assert len(data) == 256
            signature = int.from_bytes(data, 'little')
            plaintext = int(f'0x1{"f"*404}003031300d060960864801650304020105000420{"0"*64}', 16) | int.from_bytes(digest, 'big')
            assert pow(signature, 0x10001, Apple_EFI_ROM_public_key_1) == plaintext
        elif signature_method == 2:
            data = f.read(32)
            assert data == digest
            raise RuntimeError('Chunklist missing digital signature')
        else:
            raise NotImplementedError
        assert f.read(1) == b''

dmgpath, cnkpath = sys.argv[1], sys.argv[2]
with open(dmgpath, 'rb') as dmgf:
    for cnkcount, (cnksize, cnkhash) in enumerate(verify_chunklist(cnkpath), 1):
        cnk = dmgf.read(cnksize)
        assert len(cnk) == cnksize, f'chunk {cnkcount} short read'
        assert hashlib.sha256(cnk).digest() == cnkhash, f'chunk {cnkcount} hash mismatch'
    assert dmgf.read(1) == b'', 'image larger than chunklist'
print(f'VERIFIED: {cnkcount} chunks hash-match; chunklist RSA signature is valid Apple')
PY
}

if [[ -s "$DMG" && -s "$CNK" ]] && verify_chunklist "$DMG" "$CNK" 2>/dev/null; then
    echo "cached recovery still verifies against its Apple chunklist"
else
    echo "querying Apple Internet Recovery (board $BOARD, os=$OS_TYPE)..."
    SESS=$(curl -s -D - -o /dev/null -H "User-Agent: $UA" \
        http://osrecovery.apple.com/ | grep -io 'session=[^;]*' | head -1 | tr -d '\r')
    CID=$(openssl rand -hex 8 | tr a-f A-F)
    K=$(openssl rand -hex 32 | tr a-f A-F)
    FG=$(openssl rand -hex 32 | tr a-f A-F)
    payload=$(mktemp)
    trap 'rm -f "$payload"' EXIT
    printf 'cid=%s\nsn=00000000000000000\nbid=%s\nk=%s\nfg=%s\nos=%s\n' \
        "$CID" "$BOARD" "$K" "$FG" "$OS_TYPE" > "$payload"

    RESP=$(curl -fsS -H "User-Agent: $UA" -H "Cookie: $SESS" \
        -H 'Content-Type: text/plain' --data-binary @"$payload" \
        http://osrecovery.apple.com/InstallationPayload/RecoveryImage)

    get() { echo "$RESP" | grep "^$1: " | cut -d' ' -f2; }
    AP=$(get AP); DMG_URL=$(get AU); DMG_TOK=$(get AT); CNK_URL=$(get CU); CNK_TOK=$(get CT)
    echo "Apple served recovery product $AP"

    if [[ "$PRODUCT_PIN" != any && "$AP" != "$PRODUCT_PIN" ]]; then
        { echo "product mismatch: pinned $PRODUCT_PIN, Apple served $AP."
          echo "To adopt the new one: bump PRODUCT_PIN in $0 and delete"
          echo "  $CNK"
          echo "  $DMG"
          echo "(a fresh ~900 MB download follows)." ; } >&2
        exit 1
    fi

    curl -fS --retry 3 -H "User-Agent: $UA" -H "Cookie: AssetToken=$CNK_TOK" \
        -o "$CNK" "$CNK_URL"
    curl -fS --retry 3 -H "User-Agent: $UA" -H "Cookie: AssetToken=$DMG_TOK" \
        -o "$DMG" "$DMG_URL"
    verify_chunklist "$DMG" "$CNK"
fi

if [[ "${NO_IMG:-0}" == 1 ]]; then
    ls -la "$DMG" "$CNK"
    exit 0
fi

if [[ ! -s "$IMG" ]]; then
    echo "converting DMG -> raw image (qemu-img reads Apple DMGs natively)..."
    qemu-img convert -O raw "$DMG" "$IMG"
fi

echo
ls -la "$DMG" "$CNK" "$IMG"
echo "ready: $IMG is the QEMU attach media (boots via OpenCore; see"
echo "../macos-tahoe/README.md for the boot chain)"
