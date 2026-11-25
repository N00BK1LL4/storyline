"""Copy the mod from a live server's resources folder into this repository.
   STORYLINE_LIVE is that gm_events folder. Never copies data/ (presets and notes)."""
import os, shutil
here = os.path.dirname(os.path.abspath(__file__))
live = os.environ["STORYLINE_LIVE"]
assert os.path.exists(os.path.join(live, "open77.lua")), "not a gm_events folder: " + live
target = os.path.join(here, "gm_events")
shutil.rmtree(target)
shutil.copytree(live, target, ignore=shutil.ignore_patterns("data"))
print("copied from", live)
