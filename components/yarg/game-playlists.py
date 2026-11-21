#!/usr/bin/env python3
"""Writes YARG playlists: one per Guitar Hero / Rock Band game, plus
"Songs with Videos" and "Músicas Nacionais" (Brazilian songs).

The Clone Hero library keeps each game's setlist in its own folder
(Songs/[GUITAR HERO]/[GUITAR HERO III], Songs/[ROCK BAND]/[ROCK BAND 2], ...).
Each of those becomes a playlist, and "Guitar Hero (All)" / "Rock Band (All)"
hold every game of the franchise together. The packs in a "- DLC" folder join their
game's playlist (Guitar Hero III DLC goes into Guitar Hero III, after the
game's own songs). Tutorial, demo and prototype folders are left out.

Songs that dedupe-songs.py moved out of a game folder still count: moved.tsv
says which chart was kept instead, and the playlist points at that one.

"Songs with Videos" holds every song in the library (--library, default the
YARG song folders) with a background video YARG plays: bg/background/video
(optionally _clean/_explicit) .mp4/.mov/.webm/.mkv, or the song.ini "video"
file. "Músicas Nacionais" holds songs whose artist is on BRAZILIAN_ARTISTS or
whose genre is a Brazilian one (MPB, forró, sertanejo, Brazilian rock, ...).
Plain "samba"/"bossa nova" genres don't count: non-Brazilian charts use them.

YARG names a song by the SHA-1 of its chart file (notes.mid, else
notes.midi, else notes.chart), which is what goes in the playlist. Playlists
this tool wrote carry Author "omarchy" and are replaced on every run; other
playlists are never touched. YARG reads playlists at start, so close it first.

  game-playlists.py [--dry-run] [--songs DIR] [--moved TSV] [--library DIR]... [--dest PLAYLISTS_DIR]...
"""
import argparse
import glob
import hashlib
import json
import os
import re
import sys
import unicodedata
import uuid

SONGS = "/wdblack_4TB/Games/CloneHero-Drive/Songs"
MOVED = "/wdblack_4TB/Games/CloneHero-Duplicates/moved.tsv"
LIBRARY = [
    "/wdblack_4TB/Games/YARC/Songs-UltimateREpack",
    "/wdblack_4TB/Games/CloneHero-Drive/Songs",
    "/wdblack_4TB/Games/CloneHero-Drive/[CHORUS]",
    "/wdblack_4TB/Games/CloneHero-Drive/[VOCAL ONLY]",
]
VIDEO_PLAYLIST = "Songs with Videos"
BRAZIL_PLAYLIST = "Músicas Nacionais"
VIDEO_FILE = re.compile(r"^(bg|background|video)(_clean|_explicit)?\.(mp4|mov|webm|mkv)$")
BRAZILIAN_GENRE = re.compile(
    r"^(mpb|forr[oó]|sertanejo|ax[eé]|pagode|samba rock|funk (brasileiro|carioca)|brega funk|"
    r"brazil+ian (rock|indie|pop|metal|punk|hardcore)|rock (nacional|brasileiro))\b", re.I)
# Matched against the whole artist field, or its first name before feat./,/&/" e ".
# Generic names (Viper, Shaman, Gloria, Hangar, ...) are here because the charts
# by those names in this library are the Brazilian bands; check new ones before adding.
BRAZILIAN_ARTISTS = """
14 Bis; Alceu Valença; Aldo Sena; Almah; Alok; Ana Carolina; Andre Matos; Andre Teclas; Angra;
Aquiles Priester; Armandinho; Arnaldo Antunes; Attomica; Aviões do Forró; Bad Luv; Baianasystem;
Banda Calypso; Banda Eva; Barão Vermelho; Barões da Pisadinha; Belchior; Beth Carvalho; Bezerra da Silva;
Bidê ou Balde; Biquini Cavadão; Bison e Comassetto; Black Pantera; Boogarins; Bruno & Marrone;
Cachorro Grande; Caetano Veloso; Camisa de Vênus; Canto dos Malditos na Terra do Nunca; Cap'tão Caverna;
Capital Inicial; Cartola; Cássia Eller; Cazuza; Charlie Brown Jr; Charlie Brown Jr.; Chico Buarque;
Chico César; Chico Science & Nação Zumbi; Chitãozinho & Xororó; Cidade Dormitório; Cine; Claudinho & Buchecha;
Claustrofobia; Clube da Esquina; Cólera; Comunidade Nin-Jitsu; CPM 22; Criolo; Crypta; Cueio Limão;
Daniela Mercury; Dead Fish; Detonautas; Detonautas Roque Clube; Djavan; Djonga; Dominguinhos;
Dorsal Atlântica; Dr. Sin; E a Terra Nunca Me Pareceu Tão Distante; Edu Falaschi; Ego Kill Talent;
Elba Ramalho; Electric Mob; Elis Regina; Eminence; Emicida; Engenheiros do Hawaii; Erasmo Carlos;
Exaltasamba; Fábio Lima; Fafá de Belém; Fagner; Falamansa; Falcão; Far From Alaska; Fernanda Abreu;
Forfun; Frejat; Fresno; Fruto Sagrado; Fundo de Quintal; Gabriel o Pensador; Gal Costa; Garage Fuzz;
Garotos Podres; Gilberto Gil; Gloria; Glória; Gloria Groove; Graforréia Xilarmônica; Gusttavo Lima;
Hangar; Hardneja Sertacore; Hateen; Hellish War; Henrique & Juliano; Hevo84; Hibria; Inocentes; Ira!;
Israel & Rodolffo; Ivete Sangalo; Jão; João Brasil; João Gilberto; João Gomes; João Gordo; Jorge & Mateus;
Jorge Ben; Jorge Ben Jor; Jota Quest; Kid Abelha; Kiko Loureiro; Korzus; Krisiun; Lagum; Lauana Prado;
Leandro & Leonardo; Legião Urbana; Lenine; Lô Borges; Lobão; Los Hermanos; Luan Santana; Ludmilla;
Luísa Sonza; Luiz Gonzaga; Lulu Santos; Mady e seus Namorados; Mallu Magalhães; Mamonas Assassinas;
Manuel Gomes; Marcelo D2; Maria Bethânia; Marília Mendonça; Mario Zan; Marisa Monte; Massacration;
Mastruz com Leite; Matanza; Mateus Asato; Matuê; Melim; Michel Teló; Milton Nascimento; Mukeka di Rato;
Naiara Azevedo; Nando Reis; Nação Zumbi; Natiruts; Nenhum de Nós; Nervosa; Ney Matogrosso; Noturnall;
Novos Baianos; NX Zero; O Rappa; O Terno; Oficina G3; Os Bastiões; Os Mutantes; Os Paralamas do Sucesso;
Ovelha; Pabllo Vittar; Paralamas do Sucesso; Pato Fu; Paula Fernandes; Pedro Sampaio; Pense; Pequeno Cidadão;
Pitty; Planet Hemp; Plebe Rude; Plutão Já Foi Planeta; Project46; Raça Negra; Racionais MC's; Raimundos;
Ratos de Porão; Raul Seixas; Resgate; Restart; Rita Lee; Roberto Carlos; Rosa de Saron; Roupa Nova; RPM;
Sá, Rodrix & Guarabyra; Sabotage; Sambô; Sandy & Junior; Scalene; Secos & Molhados; Selvagens à Procura de Lei;
Semblant; Sepultura; Seu Jorge; Seu Pereira e Coletivo 401; Shaman; Skank; Sorriso Maroto; Supercombo; Supla;
Tequila Baby; Terno Rei; Thiaguinho; Tiago Iorc; Tihuana; Tim Maia; Titãs; Tom Jobim; Torture Squad; Tribalistas;
Tribo de Jah; Trovão; Tuatha de Danann; Ultraje a Rigor; Vanessa da Mata; Vinicius de Moraes; Viper;
Vitor Kley; Wagner Nascimento; Walter Wanderly; Wesley Safadão; Xuxa; Yasmin Santos; Zé Ramalho;
Zeca Baleiro; Zeca Pagodinho; Zequinha de Abreu; Zezé Di Camargo & Luciano
"""
FRANCHISES = ["[GUITAR HERO]", "[ROCK BAND]"]
CHARTS = ["notes.mid", "notes.midi", "notes.chart"]  # YARG's own order
SKIP = re.compile(r"tutorial|demo|prototype", re.I)
AUTHOR = "omarchy"
NAMESPACE = uuid.UUID("5d3c1f0e-8f5a-4f61-9a43-3c2b9a3e7a10")
KEEP_UPPER = {"I", "II", "III", "IV", "V", "VR", "TV", "DLC", "ACDC", "GHWT", "GHM", "DJ", "LEGO", "80S"}
ALIASES = {
    "GHM": "Guitar Hero Metallica",
    "GHWT": "Guitar Hero World Tour",
    "Guitar Hero Wor": "Guitar Hero Warriors of Rock",
    "Guitar Hero I$": "Guitar Hero",
    "Guitar Hero - ": "Guitar Hero ",
    "Rock Band - Network": "Rock Band Network",
}
PREFIX_DIRS = [
    "~/.local/share/omarchy-yarg/proton/pfx/drive_c/users/steamuser/AppData/LocalLow/YARC/YARG/*",
    "~/.config/unity3d/YARC/YARG/*",
]


def display_name(folder):
    words = folder.strip("[]").replace("VAN HALLEN", "VAN HALEN").split()
    out = []
    for w in words:
        if w in KEEP_UPPER:
            out.append("80s" if w == "80S" else w)
        elif w == "-":
            out.append(w)
        else:
            out.append(w.capitalize())
    name = " ".join(out).replace("ACDC", "AC/DC")
    name = re.sub(r"\b(Of|The)\b", lambda m: m.group(1).lower(), name)
    name = re.sub(r" - DLC$", " DLC", name)
    for short, full in ALIASES.items():
        name = re.sub(rf"^{short}\b", full, name)
    return name


def playlist_folders(songs):
    """Yields (franchise, name, folder) for every game, and every pack in a DLC folder."""
    for franchise in FRANCHISES:
        root = os.path.join(songs, franchise)
        if not os.path.isdir(root):
            continue
        for game in sorted(os.listdir(root)):
            path = os.path.join(root, game)
            if not os.path.isdir(path):
                continue
            if "DLC" in game.upper():
                for pack in sorted(os.listdir(path)):
                    if os.path.isdir(os.path.join(path, pack)):
                        yield franchise, display_name(pack), os.path.join(path, pack)
            else:
                yield franchise, display_name(game), path


def chart_of(song_dir):
    try:
        files = {f.lower(): f for f in os.listdir(song_dir)}
    except OSError:
        return None
    if "song.ini" not in files:
        return None
    for name in CHARTS:
        if name in files:
            return os.path.join(song_dir, files[name])
    return None


def sha1_hex(path):
    h = hashlib.sha1()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest().upper()


def song_dirs(folder, moved):
    """Song folders of a game, in path order, with moved ones swapped for the kept copy."""
    found = []
    for dp, dirs, _files in os.walk(folder):
        dirs[:] = sorted(d for d in dirs if not SKIP.search(d))
        if chart_of(dp):
            found.append((dp, dp))
    prefix = folder.rstrip("/") + "/"
    for original, kept in moved.items():
        if original.startswith(prefix):
            rel = original[len(prefix):]
            if not any(SKIP.search(part) for part in rel.split("/")):
                found.append((original, kept))
    found.sort(key=lambda pair: pair[0].lower())
    return [kept for _orig, kept in found]


def read_moved(path):
    moved = {}
    if not os.path.isfile(path):
        return moved
    with open(path, encoding="utf-8", errors="surrogateescape") as f:
        for line in f:
            cols = line.rstrip("\n").split("\t")
            if len(cols) >= 3:
                moved[cols[0]] = cols[2]
    return moved


def norm(text):
    text = unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode().lower()
    return re.sub(r"[^a-z0-9]+", " ", text).strip()


BRAZILIAN = {norm(a) for a in BRAZILIAN_ARTISTS.split(";") if a.strip()}
ARTIST_SPLIT = re.compile(r"\s+(?:feat\.?|ft\.?|featuring|with|e|x|and)\s+|[,&(+]", re.I)


def read_ini(path):
    raw = open(path, "rb").read()
    for enc in ("utf-8-sig", "utf-16"):
        try:
            text = raw.decode(enc)
            break
        except UnicodeDecodeError:
            pass
    else:
        text = raw.decode("latin-1")
    d = {}
    for line in text.splitlines():
        if "=" in line:
            k, v = line.split("=", 1)
            d.setdefault(k.strip().lower(), v.strip())
    return d


def is_brazilian(ini):
    artist = ini.get("artist", "")
    if norm(artist) in BRAZILIAN or norm(ARTIST_SPLIT.split(artist)[0]) in BRAZILIAN:
        return True
    return bool(BRAZILIAN_GENRE.match(ini.get("genre", "").strip()))


def has_video(files, ini):
    video = ini.get("video", "").lower()
    if video and video in files and VIDEO_FILE.match("video." + video.rsplit(".", 1)[-1]):
        return True
    return any(VIDEO_FILE.match(f) for f in files)


def library_playlists(roots):
    """Songs with a video, and Brazilian songs, across the whole library, by artist and title."""
    videos, brazil = [], []
    for root in roots:
        for dp, dirs, files in os.walk(root):
            dirs.sort()
            low = {f.lower(): f for f in files}
            if "song.ini" not in low:
                continue
            chart = next((os.path.join(dp, low[c]) for c in CHARTS if c in low), None)
            if not chart:
                continue
            try:
                ini = read_ini(os.path.join(dp, low["song.ini"]))
            except OSError:
                continue
            key = (norm(ini.get("artist", "")), norm(ini.get("name", "")), dp)
            if has_video(low, ini):
                videos.append((key, chart))
            if is_brazilian(ini):
                brazil.append((key, chart))
    out = []
    for name, songs in ((VIDEO_PLAYLIST, videos), (BRAZIL_PLAYLIST, brazil)):
        hashes, missing = [], 0
        for _key, chart in sorted(songs):
            try:
                digest = sha1_hex(chart)
            except OSError:
                missing += 1
                continue
            if digest not in hashes:
                hashes.append(digest)
        if hashes:
            out.append((name, hashes, missing))
    return out


def default_dests():
    dests = []
    for pattern in PREFIX_DIRS:
        for channel in sorted(glob.glob(os.path.expanduser(pattern))):
            if os.path.isfile(os.path.join(channel, "settings.json")):
                dests.append(os.path.join(channel, "playlists"))
    return dests


def build(songs, moved):
    # A DLC pack ("Rock Band 3 DLC") joins its game's playlist, after the game's own songs.
    folders, franchise_of = {}, {}
    for franchise, name, folder in playlist_folders(songs):
        game = re.sub(r" DLC$", "", name)
        folders.setdefault(game, []).append((name.endswith(" DLC"), folder))
        franchise_of[game] = franchise
    playlists = []
    for name in sorted(folders):
        hashes, missing = [], 0
        for song in (s for _dlc, f in sorted(folders[name], key=lambda p: p[0]) for s in song_dirs(f, moved)):
            chart = chart_of(song)
            if not chart:
                missing += 1
                continue
            try:
                digest = sha1_hex(chart)
            except OSError:
                missing += 1
                continue
            if digest not in hashes:
                hashes.append(digest)
        if hashes:
            playlists.append((name, hashes, missing))
    # "Guitar Hero (All)" / "Rock Band (All)": every game of the franchise, game by game.
    for franchise in FRANCHISES:
        everything = []
        for name, hashes, _missing in playlists:
            if franchise_of.get(name) == franchise:
                everything += [h for h in hashes if h not in everything]
        if everything:
            playlists.append((display_name(franchise) + " (All)", everything, 0))
    return playlists


def file_name(name):
    safe = re.sub(r'[<>:"/\\|?*]', "", name)
    return f"omarchy - {safe}.json"


def write(dest, playlists):
    os.makedirs(dest, exist_ok=True)
    for path in glob.glob(os.path.join(dest, "*.json")):
        try:
            with open(path, encoding="utf-8-sig") as f:
                if json.load(f).get("Author") == AUTHOR:
                    os.remove(path)
        except (OSError, ValueError, AttributeError):
            pass
    for name, hashes, _missing in playlists:
        data = {
            "Name": name,
            "Author": AUTHOR,
            "Id": str(uuid.uuid5(NAMESPACE, name)),
            "SongHashes": hashes,
            "Ephemeral": False,
            "Count": len(hashes),
        }
        with open(os.path.join(dest, file_name(name)), "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
            f.write("\n")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--songs", default=SONGS)
    ap.add_argument("--moved", default=MOVED)
    ap.add_argument("--library", action="append", help="song folder to scan for video/Brazilian songs (default: YARG's)")
    ap.add_argument("--dest", action="append", help="YARG playlists folder (default: every YARG install found)")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    playlists = build(args.songs, read_moved(args.moved)) + library_playlists(args.library or LIBRARY)
    for name, hashes, missing in playlists:
        note = f" ({missing} without a chart)" if missing else ""
        print(f"{len(hashes):5d}  {name}{note}")
    print(f"{len(playlists)} playlists, {sum(len(h) for _n, h, _m in playlists)} songs")
    dests = args.dest or default_dests()
    if not dests:
        print("no YARG settings folder found; pass --dest", file=sys.stderr)
        return 1
    for dest in dests:
        if args.dry_run:
            print(f"would write {dest}")
        else:
            write(dest, playlists)
            print(f"wrote {dest}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
