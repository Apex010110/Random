"""Configure manual code signing for the Runner target in the Xcode project (used by CI).

Usage:
  python3 ios_signing.py <project.pbxproj> --bundle-id com.you.cartcloser --team ABCDE12345 \
      --profile "CartCloser Dev" --identity "Apple Development"

Only the Runner app target is changed (RunnerTests is left alone). Nothing personal is
committed: CI passes these values from GitHub secrets at build time.
"""
import argparse
import re
import sys

DEFAULT_BUNDLE = "pk.cartcloser.cartcloserAi"


def configure(text: str, bundle: str, team: str, profile: str, identity: str) -> tuple[str, int]:
    pattern = re.compile(rf"(\n(\s*)PRODUCT_BUNDLE_IDENTIFIER = {re.escape(DEFAULT_BUNDLE)};)")
    count = 0

    def repl(m: re.Match) -> str:
        nonlocal count
        count += 1
        ind = m.group(2)
        return (
            f"\n{ind}PRODUCT_BUNDLE_IDENTIFIER = {bundle};"
            f"\n{ind}CODE_SIGN_STYLE = Manual;"
            f"\n{ind}DEVELOPMENT_TEAM = {team};"
            f'\n{ind}PROVISIONING_PROFILE_SPECIFIER = "{profile}";'
            f'\n{ind}"CODE_SIGN_IDENTITY[sdk=iphoneos*]" = "{identity}";'
        )

    text = pattern.sub(repl, text)
    # The tests target keeps the default prefix but must follow the new bundle id root.
    text = text.replace(f"{DEFAULT_BUNDLE}.RunnerTests", f"{bundle}.RunnerTests")
    return text, count


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("pbxproj")
    ap.add_argument("--bundle-id", required=True)
    ap.add_argument("--team", required=True)
    ap.add_argument("--profile", required=True)
    ap.add_argument("--identity", default="Apple Development")
    a = ap.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9.-]+", a.bundle_id) or not re.fullmatch(r"[A-Z0-9]{10}", a.team):
        print("invalid bundle id or team id", file=sys.stderr)
        return 2
    with open(a.pbxproj, encoding="utf-8") as f:
        text = f.read()
    text, n = configure(text, a.bundle_id, a.team, a.profile, a.identity)
    if n != 3:  # Debug, Release, Profile
        print(f"expected 3 Runner build configurations, found {n}", file=sys.stderr)
        return 1
    with open(a.pbxproj, "w", encoding="utf-8") as f:
        f.write(text)
    print(f"Configured manual signing for {a.bundle_id} (team {a.team}, profile '{a.profile}') in {n} configurations")
    return 0


if __name__ == "__main__":
    sys.exit(main())
