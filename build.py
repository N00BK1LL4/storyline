"""Build the public package. Never includes data/ (your presets and notes).
   python build.py            refuses while the author's handle is missing
   python build.py --draft    builds anyway, named -draft"""
import os, re, sys, zipfile
here = os.path.dirname(os.path.abspath(__file__))
draft = "--draft" in sys.argv
args = [a for a in sys.argv[1:] if not a.startswith("--")]
main = args[0] if args else os.path.join(here, "gm_events")
version = re.search(r'^version "([^"]+)"', open(os.path.join(main, "open77.lua"), encoding="utf-8").read(), re.M)[1]
config = re.search(r'version = "([^"]+)"', open(os.path.join(main, "server", "config.lua"), encoding="utf-8").read())[1]
assert version == config, f"open77.lua says {version}, config.lua says {config}"
keep = {".lua", ".js", ".css", ".html", ".rml", ".rcss", ".md", ".jsonc"}
def pack(out, roots):
    names = []
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for name, src in roots:
            for base, dirs, files in os.walk(src):
                dirs[:] = sorted(d for d in dirs if d != "data" and not d.startswith("."))
                for f in sorted(files):
                    p = os.path.join(base, f)
                    rel = os.path.relpath(p, src).replace("\\", "/")
                    if os.path.splitext(f)[1] not in keep and f != "LICENSE":
                        print("skipped", rel); continue
                    text = open(p, encoding="utf-8").read()
                    bad = re.search(r"op77_live_|[A-Za-z]:\\Users|C:/Users|@gmail", text, re.I)
                    assert not bad or f == "models.js", f"private text in {rel}: {bad[0]}"
                    if "[YOUR OPEN77 HANDLE]" in text and not draft:
                        raise SystemExit(f"fill in your handle in {name}/{rel} first (or use --draft)")
                    z.write(p, name + "/" + rel); names.append(name + "/" + rel)
    print(out, len(names), "files")
tail = "-draft" if draft else ""
chimera = os.path.join(here, "gm_chimera")
pack(os.path.join(here, f"storyline-{version}{tail}.zip"), [("gm_events", main), ("gm_chimera", chimera)])
pack(os.path.join(here, f"gm_events-{version}{tail}.zip"), [("gm_events", main)])
pack(os.path.join(here, f"gm_chimera-{version}{tail}.zip"), [("gm_chimera", chimera)])
