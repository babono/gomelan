# Splits the designer's nawa sanga mark (logo-baru.svg) into the onboarding's
# layers: onboarding-mark (every petal unlit) and onboarding-mark-lit-0…7 (one
# petal each, in its lit colours, north-east first and on round anticlockwise).
#
#   python3 scripts/split-onboarding-mark.py logo-baru.svg Kotek/Resources/Assets.xcassets

import re, sys, os, math, json
src, out = sys.argv[1], sys.argv[2]
s = open(src).read()
paths = re.findall(r'<path[^>]*/>', s)
assert len(paths) == 25, len(paths)
head = '<svg width="219" height="219" viewBox="0 0 219 219" fill="none" xmlns="http://www.w3.org/2000/svg">\n'
def recolor(p, c): return re.sub(r'fill="#[0-9A-Fa-f]{6}"', f'fill="{c}"', p)
NORMAL = ["#E7B142", "#DE6D2F", "#2F2F2F"]   # rim, face, glyph
LIT    = ["#FDF9F0", "#E7B142", "#FFFFFE"]
petals = [paths[1+3*i:4+3*i] for i in range(8)]
def angle(p):
    d = re.search(r'd="([^"]*)"', p[1]).group(1)
    n = list(map(float, re.findall(r'-?\d+\.?\d*', d)))
    xs, ys = n[0::2], n[1::2]
    cx, cy = (min(xs)+max(xs))/2 - 109.5, (min(ys)+max(ys))/2 - 109.5
    return math.degrees(math.atan2(-cy, cx)) % 360   # counter-clockwise from east
# The designer's frames light NE first, then on round anticlockwise.
order = sorted(range(8), key=lambda i: (angle(petals[i]) - 45 + 360 + 1) % 360)
def write(name, body):
    d = os.path.join(out, name + ".imageset"); os.makedirs(d, exist_ok=True)
    open(os.path.join(d, name + ".svg"), "w").write(head + body + "</svg>\n")
    json.dump({"images":[{"filename":name+".svg","idiom":"universal"}],"info":{"author":"xcode","version":1},
               "properties":{"preserves-vector-representation":True}}, open(os.path.join(d,"Contents.json"),"w"), indent=2)
write("onboarding-mark", paths[0] + "\n" + "\n".join(recolor(p, c) for pt in petals for p, c in zip(pt, NORMAL)) + "\n")
for k, i in enumerate(order):
    print(k, round(angle(petals[i])))
    write(f"onboarding-mark-lit-{k}", "\n".join(recolor(p, c) for p, c in zip(petals[i], LIT)) + "\n")
