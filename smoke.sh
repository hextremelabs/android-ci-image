#!/bin/sh
# Verifies the image contract. EXPECT_PLATFORM is required; EXPECT_JDK defaults to 21.
set -eu

fail() { echo "smoke: FAIL - $1" >&2; exit 1; }
pass() { echo "smoke: ok   - $1"; }

# Image delta

# apk-tools 3 exits successfully for a missing exact package, so verify its output as well.
if apk info -e definitely-not-an-installed-package 2>/dev/null | grep -q .; then
    fail "apk info -e prints output for absent packages"
fi

for p in fontconfig freetype libstdc++ font-dejavu-core; do
    apk info -e "$p" 2>/dev/null | grep -q . || fail "package not installed: $p"
done
pass "packages installed"

# Kotlin/Native needs libstdc++ to be discoverable by soname, not merely present on disk.
libstdcxx=$(ldconfig -p 2>/dev/null | awk '/libstdc\+\+\.so\.6/ { print $NF; exit }')
[ -n "$libstdcxx" ] ||
    libstdcxx=$(find /usr/lib -name libstdc++.so.6 -print -quit 2>/dev/null || true)
[ -n "$libstdcxx" ] || fail "libstdc++.so.6 is not visible to the loader"
ldd "$libstdcxx" >/dev/null 2>&1 || fail "libstdc++.so.6 dependencies do not resolve"
pass "libstdc++ links"

# Exercise both easylauncher's file-backed font path and fontconfig's logical-font path.
ttf=$(find /usr/share/fonts -name 'DejaVuSans.ttf' -print -quit 2>/dev/null || true)
[ -n "$ttf" ] || ttf=$(find /usr/share/fonts -name '*.ttf' -print -quit 2>/dev/null || true)
[ -n "$ttf" ] || fail "no TrueType font installed"

work=$(mktemp -d)
[ -d "$work" ] || fail "mktemp -d failed"
trap 'rm -rf "$work"' EXIT
cat >"$work/FontCheck.java" <<'JAVA'
import java.awt.Font;
import java.awt.Graphics2D;
import java.awt.image.BufferedImage;
import java.io.File;

public class FontCheck {
    private static void assertRenders(Font font, String label) {
        BufferedImage image = new BufferedImage(64, 24, BufferedImage.TYPE_INT_ARGB);
        Graphics2D graphics = image.createGraphics();
        try {
            graphics.setFont(font);
            if (graphics.getFontMetrics().stringWidth("ok") <= 0) {
                throw new IllegalStateException(label + " produced no glyph width");
            }
            graphics.drawString("ok", 2, 16);
        } finally {
            graphics.dispose();
        }

        for (int y = 0; y < image.getHeight(); y++) {
            for (int x = 0; x < image.getWidth(); x++) {
                if ((image.getRGB(x, y) >>> 24) != 0) {
                    return;
                }
            }
        }
        throw new IllegalStateException(label + " painted no pixels");
    }

    public static void main(String[] args) throws Exception {
        Font bundled = Font.createFont(Font.TRUETYPE_FONT, new File(args[0])).deriveFont(12f);
        assertRenders(bundled, "file-backed font");
        assertRenders(new Font(Font.SANS_SERIF, Font.PLAIN, 12), "logical sans-serif");
    }
}
JAVA
java -Djava.awt.headless=true "$work/FontCheck.java" "$ttf" || fail "AWT cannot render text"
pass "AWT renders file-backed and logical fonts"

# Consumer contract

actual_jdk=$(java -XshowSettings:properties -version 2>&1 |
    sed -n 's/^ *java\.specification\.version = \([0-9][0-9]*\).*/\1/p')
[ -n "$actual_jdk" ] || fail "could not determine the JDK version"
[ "$actual_jdk" = "${EXPECT_JDK:-21}" ] || fail "expected JDK ${EXPECT_JDK:-21}, found $actual_jdk"
pass "JDK ${EXPECT_JDK:-21}"

[ -n "${ANDROID_HOME:-}" ] || fail "ANDROID_HOME is not set"
[ -d "$ANDROID_HOME/platforms/${EXPECT_PLATFORM:?EXPECT_PLATFORM must be set}" ] ||
    fail "platform ${EXPECT_PLATFORM} missing from $ANDROID_HOME/platforms"
pass "platform ${EXPECT_PLATFORM}"

aapt2=$(find "$ANDROID_HOME/build-tools" -name aapt2 -print -quit 2>/dev/null || true)
[ -n "$aapt2" ] || fail "no aapt2 under $ANDROID_HOME/build-tools"
"$aapt2" version >/dev/null || fail "aapt2 is present but will not execute"
pass "aapt2 executes"

command -v bash >/dev/null || fail "bash is missing"
bash -c 'x=(a b); [ "${#x[@]}" -eq 2 ] && n=x && [ -n "${!n+set}" ]' || fail "bash lacks required features"
pass "bash usable"

command -v git >/dev/null || fail "git is missing"
[ "$(printf 'secret' | base64 | base64 -d)" = "secret" ] || fail "base64 round trip failed"
[ "$(printf 'tellerpoint' | awk '{print toupper(substr($0, 1, 1)) substr($0, 2)}')" = "Tellerpoint" ] ||
    fail "awk does not capitalise as expected"
pass "shell tooling behaves"

echo "smoke: image verified"
