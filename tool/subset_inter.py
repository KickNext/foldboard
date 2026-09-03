"""Rebuild the bundled Inter subset in assets/fonts.

CanvasKit ignores system font names, so an unbundled theme silently renders in
Roboto fetched from fonts.gstatic.com — and Cyrillic text pulls further Noto
files from the same CDN. Bundling a Latin+Cyrillic subset removes both requests
and makes the app render identically offline and on every OS.

    python -m pip install fonttools brotli
    python tool/subset_inter.py path/to/Inter-4.1.zip

Inter is licensed under the SIL Open Font License; assets/fonts/Inter-OFL.txt
ships with the subset and must stay next to it.
"""

import os
import subprocess
import sys
import zipfile

WEIGHTS = {"Regular": 400, "SemiBold": 600, "Bold": 700}

# Latin, Latin Extended, punctuation, currency, arrows, box drawing, Cyrillic.
UNICODES = ",".join(
    [
        "U+0000-00FF",
        "U+0100-017F",
        "U+0180-024F",
        "U+0259",
        "U+2000-206F",
        "U+2070-209F",
        "U+20A0-20BF",
        "U+2116",
        "U+2122",
        "U+2190-21BB",
        "U+2212",
        "U+2500-2503",
        "U+25A0-25FF",
        "U+2600-26FF",
        "U+0400-045F",
        "U+0490-0491",
        "U+04B0-04B1",
    ]
)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "fonts")


def main(archive):
    os.makedirs(OUT, exist_ok=True)
    with zipfile.ZipFile(archive) as z:
        for name, weight in WEIGHTS.items():
            source = os.path.join(OUT, f".Inter-{name}.full.ttf")
            with z.open(f"extras/ttf/Inter-{name}.ttf") as src:
                with open(source, "wb") as dst:
                    dst.write(src.read())
            target = os.path.join(OUT, f"Inter-{name}.ttf")
            subprocess.run(
                [
                    sys.executable,
                    "-m",
                    "fontTools.subset",
                    source,
                    f"--unicodes={UNICODES}",
                    "--layout-features=kern,liga,calt,ccmp,locl,mark,mkmk,tnum",
                    "--name-IDs=1,2,3,4,5,6",
                    "--no-hinting",
                    "--desubroutinize",
                    f"--output-file={target}",
                ],
                check=True,
            )
            os.remove(source)
            size = os.path.getsize(target) // 1024
            print(f"Inter-{name}.ttf  weight {weight}  {size} KB")
        with z.open("LICENSE.txt") as src:
            with open(os.path.join(OUT, "Inter-OFL.txt"), "wb") as dst:
                dst.write(src.read())
    print("Wrote", OUT)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("usage: python tool/subset_inter.py path/to/Inter-4.1.zip")
    main(sys.argv[1])
