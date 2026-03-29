#!/usr/bin/env python3
"""Download geological memoirs/notices for map sheets.

Supported sources:
  - Belgium (Wallonie): Carte Géologique de Wallonie 1:25,000 notices
  - France (BRGM): Notices explicatives 1:50,000
  - Canada (Vancouver): GSC Bulletin 481

Usage:
  python memoir_downloader.py --list belgium
  python memoir_downloader.py --download belgium 53-7-8
  python memoir_downloader.py --download belgium all
  python memoir_downloader.py --download france 670
  python memoir_downloader.py --download canada vancouver
"""

import argparse
import os
import sys
import urllib.request
import urllib.error

# Default download directory
DEFAULT_DIR = os.path.join(
    os.path.expanduser("~"),
    "Library", "Application Support", "MapsPersonal", "Memoirs",
)

# ---------------------------------------------------------------------------
# Belgium — Carte Géologique de Wallonie (1:25,000)
# Source: geologie.wallonie.be
# ---------------------------------------------------------------------------
BELGIUM_BASE_URL = "https://geologie.wallonie.be/files/ressources/geologie/notices"

BELGIUM_NOTICES = {
    "29-5-6_37-1-2": "Mouscron - Zwevegem, Templeuve - Pecq",
    "29-7-8_37-3-4": "Avelgem - Ronse, Celles - Frasnes-lez-Anvaing",
    "32-5-6": "Duisburg - Hamme-Mille",
    "32-7-8": "Meldert - Tienen",
    "33-5_41-1-2": "Landen - Hannut - Montenaken",
    "34-5-6": "Tongeren - Herderen",
    "34-7-8": "Visé - St Martens-Voeren",
    "37-5-6": "Hertain - Tournai",
    "37-7-8": "Antoing - Leuze",
    "38-5-6": "Blicquy - Ath",
    "38-7-8": "Lens - Soignies",
    "39-1-2": "Rebecq - Ittre",
    "39-5-6": "Braine-le-Comte - Feluy",
    "39-7-8": "Nivelles - Genappe",
    "40-1-2": "Wavre - Chaumont-Gistoux",
    "40-3-4": "Jodoigne - Jauche",
    "40-5-6": "Chastre - Gembloux",
    "40-7-8": "Perwez - Eghezée",
    "41-5-6": "Wasseiges - Braives",
    "42-3-4": "Dalhem - Herve",
    "42-7-8": "Fléron - Verviers",
    "46-1-2": "Le Roeulx - Seneffe",
    "46-3-4": "Gouy-lez-Piéton - Gosselies",
    "46-5-6": "Binche - Morlanwelz",
    "46-7-8": "Fontaine-l'Evêque - Charleroi",
    "47-1-2": "Fleurus - Spy",
    "47-3-4": "Namur - Champion",
    "47-5-6": "Tamines - Fosses-la-Ville",
    "47-7-8": "Malonne - Naninne",
    "48-1-2": "Andenne - Couthuin",
    "48-3-4": "Huy - Nandrin",
    "48-5-6": "Gesves - Ohey",
    "48-7-8": "Modave - Clavier",
    "49-1-2": "Tavier - Esneux",
    "52-1-2": "Merbes-le-Château - Thuin",
    "52-3-4": "Gozée - Nalinnes",
    "52-5-6": "Grandrieu - Beaumont",
    "52-7-8": "Silenrieux - Walcourt",
    "53-1-2": "Biesme - Mettet",
    "53-3-4": "Bioul - Yvoir",
    "53-5-6": "Philippeville - Rosée",
    "53-7-8": "Hastière - Dinant",
    "54-1-2": "Natoye - Ciney",
    "54-3-4": "Maffe - Grandhan",
    "54-5-6": "Achêne - Leignon",
    "54-7-8": "Aye - Marche-en-Famenne",
    "55-3-4": "Bra - Lierneux",
    "55-5-6": "Hotton - Dochamps",
    "57-1-2": "Sivry - Rance",
    "57-3-4": "Froidchapelle - Senzeille",
    "57-5-6": "Momignies - Seloignes",
    "57-7-8": "Chimay - Couvin",
    "58-1-2": "Sautour - Surice",
    "58-3-4": "Agimont - Beauraing",
    "58-5-6": "Olloy - Treignes",
    "58-7-8": "Felenne - Vencimont",
    "59-3-4": "Rochefort - Nassogne",
    "59-5-6": "Pondrôme - Wellin",
    "59-7-8": "Grupont - Saint-Hubert",
    "60-1-2": "Champlon - La Roche-en-Ardenne",
    "60-3-4": "Wibrin - Houffalize",
    "60-5-6": "Amberloup - Flamierge",
    "64-5-6": "Vivy - Paliseul",
    "65-1-2": "Saint-Marie-Chevigny - Sibret",
    "65-5-6": "Neufchâteau - Juseret",
    "67-3-4": "Herbeumont - Suxy",
    "68-1-2": "Assenois - Anlier",
    "68-3-4": "Nobressart - Attert",
    "68-5-6": "Tintigny - Etalle",
    "71-1-2": "Meix-devant-Virton - Virton",
    "71-5-6": "Lamorteau - Ruette",
}

# Filename mapping (sheet_id -> filename on server)
BELGIUM_FILES = {
    "29-5-6_37-1-2": "29-5-6_37-1-2_Templeuve_Pecq.pdf",
    "29-7-8_37-3-4": "29-7-8_37-3-4_Celles_FrasneslezAnvaing.pdf",
    "32-5-6": "32-5-6_Duisburg_Hamme-Mille.pdf",
    "32-7-8": "32-7-8_Meldert_Tienen.pdf",
    "33-5_41-1-2": "33-5_41-1-2_Landen_Hannut_Montenaken.pdf",
    "34-5-6": "34-5-6_Tongeren_Herderen.pdf",
    "34-7-8": "34-7-8_Vise_StMartensVoeren.pdf",
    "37-5-6": "37-5-6_Hertain_Tournai.pdf",
    "37-7-8": "37-7-8_Antoing_Leuze.pdf",
    "38-5-6": "38-5-6_Blicquy_Ath.pdf",
    "38-7-8": "38-7-8_Lens_Soignies.pdf",
    "39-1-2": "39-1-2_Rebecq_Ittre.pdf",
    "39-5-6": "39-5-6_BraineLeComte_Feluy.pdf",
    "39-7-8": "39-7-8_Nivelles_Genappe.pdf",
    "40-1-2": "40-1-2_Wavre_Chaumont.pdf",
    "40-3-4": "40-3-4_Jodoigne_Jauche.pdf",
    "40-5-6": "40-5-6_Chastre_Gembloux.pdf",
    "40-7-8": "40-7-8_Perwez_Eghezee.pdf",
    "41-5-6": "41-5-6_Wasseiges_Braives.pdf",
    "42-3-4": "42-3-4_Dalhem_Herve.pdf",
    "42-7-8": "42-7-8_Fleron_Verviers.pdf",
    "46-1-2": "46-1-2_LeRoeulx_Seneffe.pdf",
    "46-3-4": "46-3-4_Gouy_Gosselies.pdf",
    "46-5-6": "46-5-6_Binche_Morlanwez.pdf",
    "46-7-8": "46-7-8_Fontaine_Charleroi.pdf",
    "47-1-2": "47-1-2_Fleurus_Spy.pdf",
    "47-3-4": "47-3-4_Namur_Champion.pdf",
    "47-5-6": "47-5-6_Tamines_FosseslaVille.pdf",
    "47-7-8": "47-7-8_Malonne_Naninne.pdf",
    "48-1-2": "48-1-2_Andenne_Couthuin.pdf",
    "48-3-4": "48-3-4_Huy_Nandrin.pdf",
    "48-5-6": "48-5-6_Gesves_Ohey.pdf",
    "48-7-8": "48-7-8_Modave_Clavier.pdf",
    "49-1-2": "49-1-2_Tavier_Esneux.pdf",
    "52-1-2": "52-1-2_Merbes_Thuin.pdf",
    "52-3-4": "52-3-4_Gozee_Nalinnes.pdf",
    "52-5-6": "52-5-6_Grandrieu_Beaumont.pdf",
    "52-7-8": "52-7-8_Silenrieux_Walcourt.pdf",
    "53-1-2": "53-1-2_Biesme_Mettet.pdf",
    "53-3-4": "53-3-4_Bioul_Yvoir.pdf",
    "53-5-6": "53-5-6_Philippeville_Rosee.pdf",
    "53-7-8": "53-7-8_Hastiere_Dinant.pdf",
    "54-1-2": "54-1-2_Natoye_Ciney.pdf",
    "54-3-4": "54-3-4_Maffe_Grandhan.pdf",
    "54-5-6": "54-5-6_Achene_Leignon.pdf",
    "54-7-8": "54-7-8_Aye_MarcheenFamenne.pdf",
    "55-3-4": "55-3-4_Bra_Lierneux.pdf",
    "55-5-6": "55-5-6_Hotton_Dochamps.pdf",
    "57-1-2": "57-1-2_Sivry_Rance.pdf",
    "57-3-4": "57-3-4_Froidchapelle_Senzeille.pdf",
    "57-5-6": "57-5-6_Momignies_Seloignes.pdf",
    "57-7-8": "57-7-8_Chimay_Couvin.pdf",
    "58-1-2": "58-1-2_Sautour_Surice.pdf",
    "58-3-4": "58-3-4_Agimont_Beauraing.pdf",
    "58-5-6": "58-5-6_Olloy_Treignes.pdf",
    "58-7-8": "58-7-8_Felenne_Vencimont.pdf",
    "59-3-4": "59-3-4_Rochefort_Nassogne.pdf",
    "59-5-6": "59-5-6_Pondrome_Wellin.pdf",
    "59-7-8": "59-7-8_Grupont_St-Hubert.pdf",
    "60-1-2": "60-1-2_Champlon_LaRocheenArdenne.pdf",
    "60-3-4": "60-3-4_Wibrin_Houffalize.pdf",
    "60-5-6": "60-5-6_Amberloup-Flamierge.pdf",
    "64-5-6": "64-5-6_Vivy_Paliseul.pdf",
    "65-1-2": "65-1-2_Sainte-Marie-Chevigny_Sibret.pdf",
    "65-5-6": "65-5-6_Neufchateau_Juseret.pdf",
    "67-3-4": "67-3-4_Herbeumont_Suxy.pdf",
    "68-1-2": "68-1-2_Assenois_Anlier.pdf",
    "68-3-4": "68-3-4_Nobressart_Attert.pdf",
    "68-5-6": "68-5-6_Tintigny_Etalle.pdf",
    "71-1-2": "71-1-2_MeixdevantVirton_Virton.pdf",
    "71-5-6": "71-5-6_Lamorteau_Ruette.pdf",
}

# ---------------------------------------------------------------------------
# France — BRGM Notices explicatives (1:50,000)
# Source: ficheinfoterre.brgm.fr
# Pattern: http://ficheinfoterre.brgm.fr/Notices/{NNNN}N.pdf
# ---------------------------------------------------------------------------
FRANCE_BASE_URL = "http://ficheinfoterre.brgm.fr/Notices"

# ---------------------------------------------------------------------------
# Canada — GSC Bulletin 481 (Vancouver region geology)
# ---------------------------------------------------------------------------
CANADA_MEMOIRS = {
    "vancouver-geomap": {
        "name": "GeoMap Vancouver — geological map of the metro area (2.6 MB)",
        "url": "http://www.gac-cs.ca/publications/JohnArmstrong_VancouverGeology.pdf",
        "filename": "canada_vancouver_geomap.pdf",
    },
    "vancouver": {
        "name": "GSC Bulletin 481 — Geology & hazards of Vancouver (316 pp, 84 MB) [MANUAL DOWNLOAD]",
        "url": "https://publications.gc.ca/site/eng/9.939178/publication.html",
        "filename": "canada_vancouver_gsc_bulletin_481.pdf",
        "manual": True,
    },
}


def ensure_dir(path):
    os.makedirs(path, exist_ok=True)


def download_file(url, dest_path):
    """Download a file with progress indication."""
    if os.path.exists(dest_path):
        print(f"  Already exists: {os.path.basename(dest_path)}")
        return True
    print(f"  Downloading: {url}")
    try:
        req = urllib.request.Request(url, headers={
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                          "AppleWebKit/537.36 (KHTML, like Gecko) "
                          "Chrome/120.0.0.0 Safari/537.36",
            "Accept": "application/pdf,*/*",
        })
        with urllib.request.urlopen(req, timeout=300) as resp:
            content_type = resp.headers.get("Content-Type", "")
            data = resp.read()
            if len(data) < 1000 or b"<!DOCTYPE" in data[:500]:
                print(f"  WARNING: received HTML instead of PDF ({len(data)} bytes)")
                return False
            with open(dest_path, "wb") as f:
                f.write(data)
            size_kb = len(data) / 1024
            print(f"  Saved: {os.path.basename(dest_path)} ({size_kb:.0f} KB)")
            return True
    except (urllib.error.URLError, urllib.error.HTTPError, OSError) as e:
        print(f"  ERROR: {e}")
        return False


def list_sheets(country):
    """List available sheets for a country."""
    if country == "belgium":
        print(f"\nBelgium — Carte Géologique de Wallonie (1:25,000)")
        print(f"{'Sheet':<20} {'Name'}")
        print("-" * 60)
        for sheet_id, name in sorted(BELGIUM_NOTICES.items()):
            print(f"{sheet_id:<20} {name}")
        print(f"\nTotal: {len(BELGIUM_NOTICES)} notices")
    elif country == "france":
        print("\nFrance — BRGM Notices explicatives (1:50,000)")
        print("Sheet numbers are 3-4 digit codes (e.g., 670, 854, 899)")
        print(f"URL pattern: {FRANCE_BASE_URL}/{{NNNN}}N.pdf")
        print("Use --download france <number> to download a specific sheet")
        print("Find sheet numbers at: https://infoterre.brgm.fr/")
    elif country == "canada":
        print("\nCanada — Available geological memoirs")
        for key, info in CANADA_MEMOIRS.items():
            print(f"  {key}: {info['name']}")
    else:
        print(f"Unknown country: {country}")
        print("Available: belgium, france, canada")


def download_belgium(sheet_id, output_dir):
    """Download Belgian geological notice(s)."""
    dest_dir = os.path.join(output_dir, "belgium")
    ensure_dir(dest_dir)

    if sheet_id == "all":
        sheets = list(BELGIUM_FILES.keys())
    else:
        sheets = [sheet_id]

    ok, fail = 0, 0
    for sid in sheets:
        if sid not in BELGIUM_FILES:
            print(f"  Unknown sheet: {sid}")
            print(f"  Use --list belgium to see available sheets")
            fail += 1
            continue
        filename = BELGIUM_FILES[sid]
        url = f"{BELGIUM_BASE_URL}/{filename}"
        dest = os.path.join(dest_dir, filename)
        if download_file(url, dest):
            ok += 1
        else:
            fail += 1

    print(f"\nBelgium: {ok} downloaded, {fail} errors")


def download_france(sheet_number, output_dir):
    """Download French BRGM geological notice."""
    dest_dir = os.path.join(output_dir, "france")
    ensure_dir(dest_dir)

    if sheet_number == "all":
        print("France 'all' not supported — too many sheets.")
        print("Use specific sheet numbers (e.g., 670, 854)")
        return

    # Pad to 4 digits
    padded = sheet_number.zfill(4)
    url = f"{FRANCE_BASE_URL}/{padded}N.pdf"
    dest = os.path.join(dest_dir, f"france_brgm_{padded}.pdf")
    download_file(url, dest)


def download_canada(memoir_id, output_dir):
    """Download Canadian geological memoir."""
    dest_dir = os.path.join(output_dir, "canada")
    ensure_dir(dest_dir)

    if memoir_id not in CANADA_MEMOIRS:
        print(f"Unknown memoir: {memoir_id}")
        print(f"Available: {', '.join(CANADA_MEMOIRS.keys())}")
        return

    info = CANADA_MEMOIRS[memoir_id]
    if info.get("manual"):
        print(f"  {info['name']}")
        print(f"  This document requires manual download from a browser:")
        print(f"  {info['url']}")
        print(f"  Save as: {os.path.join(dest_dir, info['filename'])}")
        return

    dest = os.path.join(dest_dir, info["filename"])
    print(f"  {info['name']}")
    download_file(info["url"], dest)


def main():
    parser = argparse.ArgumentParser(
        description="Download geological memoirs/notices for map sheets"
    )
    parser.add_argument(
        "--list", dest="list_country", metavar="COUNTRY",
        help="List available sheets (belgium, france, canada)"
    )
    parser.add_argument(
        "--download", nargs=2, metavar=("COUNTRY", "SHEET"),
        help="Download memoir: --download belgium 53-7-8"
    )
    parser.add_argument(
        "--output", default=DEFAULT_DIR,
        help=f"Output directory (default: {DEFAULT_DIR})"
    )

    args = parser.parse_args()

    if args.list_country:
        list_sheets(args.list_country)
    elif args.download:
        country, sheet = args.download
        ensure_dir(args.output)
        print(f"Output directory: {args.output}")

        if country == "belgium":
            download_belgium(sheet, args.output)
        elif country == "france":
            download_france(sheet, args.output)
        elif country == "canada":
            download_canada(sheet, args.output)
        else:
            print(f"Unknown country: {country}")
            print("Available: belgium, france, canada")
    else:
        parser.print_help()


if __name__ == "__main__":
    main()
