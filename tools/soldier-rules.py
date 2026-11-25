import json,re,os
from collections import Counter
s=open(os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),"gm_events/web/models.js"),encoding="utf-8").read()
d=json.loads(s[s.index("{"):s.rindex("}")+1]); rows=[l.split("|") for l in d["rows"].split("\n")]
role=re.compile(r"_(f|h)?(melee|ranged|shotgun|gunner|sniper|grenadier|netrunner|officer|fmelee|android)\d?(rare)?_(?:[a-z0-9]+_)*?(m|w)[abmh]{1,2}(_rare|_elite)?$",re.I)
quest=re.compile(r"^(q\d|sq\d|mq\d|sts_|sa_|hil_07|ma_|we_|lcm|cct_|test|tutorial|e3|demo)|_q\d{3}|2020|(^|_)(base|quest|boss|copy|photomode|puppet)(_|$)",re.I)
std=[r[0] for r in rows if d["risks"][int(r[2])]=="unsafe_quest_or_scene" and role.search(r[0]) and not quest.search(r[0])]
print(len(std)); print(Counter(re.split("_",x)[0] for x in std).most_common(60))
for f in("arasaka","militech","kangtao","security","afterlife","maxtac","trauma"): print(f,[x for x in std if x.lower().startswith(f)])
print([r[0] for r in rows if re.match("arasaka|militech",r[0]) and d["risks"][int(r[2])]=="unsafe_quest_or_scene" and r[0] not in std])
print(Counter(m for x in std for m in re.findall("arasaka|militech|kangtao|barghest|brg|kurt|security|afterlife|maxtac|trauma|biotech|netwatch|voodoo|ncpd|zeta|reclaim|scaveng|raffen|aldecald|adelcaldo|mox|cybord",x.lower())))
