"""Reproducible Pillow-only cutouts; preserve enclosed white bones/fur.
Run with Pillow installed: python tools/extract_new_units.py
"""
from pathlib import Path
import json
from PIL import Image, ImageDraw, ImageFilter, ImageChops

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'assets/source/role_sheets'
OUT = ROOT / 'assets/units'
POSES = {
    'berserker': {
        'idle': (24, 195, 275, 478),
        'walk': [(35,580,275,870),(285,580,530,870),(530,580,780,870),(775,580,980,870),(1000,580,1220,870),(1230,580,1502,870)],
        'attack': [(367,125,590,478),(636,120,1047,478),(1016,200,1334,478)],
    },
    'warlock': {
        'idle': (52,228,278,501),
        'walk': [(65,591,259,863),(308,591,502,863),(545,591,749,863),(778,591,981,863),(1000,591,1208,863),(1258,591,1480,863)],
        'attack': [(352,154,544,501),(640,153,998,501),(1030,240,1310,501)],
    },
    'skeleton': {
        'idle': (28,225,253,498),
        'walk': [(68,604,242,859),(305,604,465,859),(530,604,700,859),(750,604,925,859),(990,604,1170,859),(1230,604,1440,859)],
        'attack': [(380,145,555,498),(654,127,1010,498),(1006,233,1315,498)],
    },
    'necromancer': {
        'idle': (26,181,249,477),
        # The fifth lower pose is an attack; do not mix it into walking.
        'walk': [(25,573,226,839),(251,573,454,839),(472,573,681,839),(700,573,918,839),(1323,573,1508,839),(25,573,226,839)],
        'attack': [(316,116,519,477),(932,614,1298,838),(26,181,249,477)],
        'summon': [(316,116,519,477),(550,167,887,477),(26,181,249,477)],
    },
    # These sheets arrive already transparent (see TRANSPARENT_SOURCES).
    'zombie': {
        'idle': (49,65,200,299),
        'walk': [(49,65,200,299),(214,66,380,296),(396,62,556,296),(578,62,734,296),(761,62,915,299),(937,65,1102,296),(1123,65,1274,299),(1309,64,1465,299)],
        'attack': [(86,338,259,544),(357,344,582,543),(614,346,879,543),(931,343,1161,544),(1220,340,1404,544)],
        'death': [(104,579,286,770),(333,598,537,770),(591,639,800,765),(856,669,1049,768),(1120,691,1360,768)],
        'revive': [(63,911,272,991),(342,865,523,991),(585,854,762,991),(832,835,996,989),(1081,801,1245,990),(1310,772,1469,991)],
    },
    'paladin': {
        'idle': (31,56,191,251),
        'walk': [(24,304,180,501),(218,306,372,500),(408,307,559,501),(596,307,748,501),(785,306,938,500),(972,307,1124,501),(1163,307,1312,501),(1352,307,1504,501)],
        'attack': [(25,547,320,742),(354,532,527,749),(576,562,852,747),(853,556,1158,746),(1191,550,1372,746)],
        'skill': [(38,751,219,992),(253,803,431,992),(464,818,641,992),(668,827,907,992),(916,830,1103,992),(1141,803,1330,992),(1354,803,1513,992)],
    },
    'sniper': {
        'idle': (19,327,176,514),
        'walk': [(31,76,210,249),(210,71,388,249),(388,63,566,249),(566,63,747,249),(747,60,936,249),(937,62,1125,249),(1125,62,1316,249),(1319,62,1507,249)],
        'attack': [(699,340,890,513),(102,583,345,746),(290,580,540,746),(591,578,792,749)],
    },
}

TRANSPARENT_SOURCES = {'zombie', 'paladin', 'sniper'}
# Holy pillar frames on the paladin effect sheet are not on a grid; crop around each pillar centre.
EFFECTS = {'holy_pillar': ('paladin_effects_sheet.png', [(x-62,150,x+62,335) for x in (65,160,264,378,483,610,756,892,1032)])}
# The demon lord sheets are transparent, but capes, sword tips and roar rings cross
# into the neighbouring pose, so fixed boxes would cut one pose into the next.
# Each row is an even grid of `count` poses; every pixel island goes to the cell
# under its centre of mass, and islands crossing an explicit cut are split there.
# (row band, count, cuts)
COMPONENT_POSES = {
    'demon_lord': {
        'idle': ((0,260), 8, ()),
        'walk': ((260,480), 8, ()),
        'attack': ((480,760), 5, ()),
        'skill': ((760,1024), 7, (900,)),
    },
}
COMPONENT_EFFECTS = {
    'demon_roar': ('demon_lord_effects_sheet.png', (0,225), 8, ()),
    'demon_soul': ('demon_lord_effects_sheet.png', (440,585), 6, ()),
    'demon_absorb': ('demon_lord_effects_sheet.png', (585,815), 6, ()),
    'demon_aura': ('demon_lord_effects_sheet.png', (815,1000), 6, ()),
}

def component_cells(sheet, band, count, cuts=()):
    """Splits one row of a transparent sheet into `count` full-height cell images."""
    y0, y1 = band
    row = sheet.crop((0, y0, sheet.width, y1))
    # Near-invisible matte pixels only carry the generator's background colour.
    row.putalpha(row.getchannel('A').point(lambda value: 0 if value < 8 else value))
    w, h = row.size; cell = w / count
    alpha = row.getchannel('A'); a = alpha.load()
    owner = [[-1]*w for _ in range(h)]
    def cell_of(x): return min(count-1, int(x // cell))
    seen = bytearray(w*h)
    for start_y in range(h):
        for start_x in range(w):
            if seen[start_y*w+start_x] or a[start_x,start_y] <= 40: continue
            stack = [(start_x,start_y)]; seen[start_y*w+start_x] = 1; members = []
            while stack:
                x, y = stack.pop(); members.append((x,y))
                for nx, ny in ((x+1,y),(x-1,y),(x,y+1),(x,y-1)):
                    if 0 <= nx < w and 0 <= ny < h and not seen[ny*w+nx] and a[nx,ny] > 40:
                        seen[ny*w+nx] = 1; stack.append((nx,ny))
            pieces = {}
            for x, y in members:
                pieces.setdefault(sum(1 for cut in cuts if x >= cut), []).append((x,y))
            for piece in pieces.values():
                centre = cell_of(sum(x for x,_ in piece)/len(piece))
                for x, y in piece:
                    owner[y][x] = centre
    cells = []
    for index in range(count):
        image = Image.new('RGBA', (w, h), (0,0,0,0)); out = image.load(); src = row.load()
        for y in range(h):
            for x in range(w):
                if a[x,y] == 0: continue
                mine = owner[y][x] == index if owner[y][x] >= 0 else cell_of(x) == index
                if mine: out[x,y] = src[x,y]
        cells.append(image)
    return cells

def cutout(path):
    im = Image.open(path).convert('RGBA')
    # Only the connected outside matte is cleared, not enclosed light details.
    ImageDraw.floodfill(im, (0, 0), (0, 0, 0, 0), thresh=38)
    alpha = im.getchannel('A')
    near_edge = alpha.filter(ImageFilter.MinFilter(3))
    pixels = im.load(); a = alpha.load(); edge = near_edge.load()
    assert pixels is not None and a is not None and edge is not None
    for y in range(im.height):
        for x in range(im.width):
            if a[x,y] and not edge[x,y]:
                r,g,b,_ = pixels[x,y]
                distance = 765-r-g-b
                if distance < 85:
                    opacity = max(0, min(255, (distance-12)*4))
                    if opacity:
                        fraction = opacity/255
                        r,g,b = [max(0, min(255, round((c-255*(1-fraction))/fraction))) for c in (r,g,b)]
                    pixels[x,y] = (r,g,b,opacity)
    return im

def body_anchor(image):
    """Anchor the stable torso, not the swinging boot or trailing weapon."""
    alpha = image.getchannel('A')
    box = alpha.getbbox()
    assert box
    height = box[3] - box[1]
    band = alpha.crop((box[0], box[1] + round(height * .35), box[2], box[1] + round(height * .65)))
    weights = [sum(value * count for value, count in enumerate(band.crop((x, 0, x+1, band.height)).histogram())) for x in range(band.width)]
    runs = []; start = None
    for x, weight in enumerate(weights + [0]):
        if weight >= band.height * 255 * .4 and start is None: start = x
        elif weight < band.height * 255 * .4 and start is not None:
            runs.append((start, x)); start = None
    start, end = max(runs, key=lambda bounds: sum(weights[bounds[0]:bounds[1]])) if runs else (0, len(weights))
    total = sum(weights[start:end]); cumulative = 0
    for x in range(start, end):
        cumulative += weights[x]
        if cumulative >= total / 2: return box[0] + x
    return (box[0] + box[2]) // 2

def drop_fragments(image, keep=0.05):
    """Clears detached pixel islands (a neighbour's rifle tip) smaller than `keep` of the largest."""
    alpha = image.getchannel('A'); w, h = image.size; px = alpha.load(); seen = bytearray(w*h); islands = []
    for start in range(w*h):
        if seen[start] or px[start % w, start // w] <= 40: continue
        stack = [start]; seen[start] = 1; members = []
        while stack:
            i = stack.pop(); members.append(i); x, y = i % w, i // w
            for nx, ny in ((x+1,y),(x-1,y),(x,y+1),(x,y-1)):
                j = ny*w+nx
                if 0 <= nx < w and 0 <= ny < h and not seen[j] and px[nx,ny] > 40:
                    seen[j] = 1; stack.append(j)
        islands.append(members)
    if not islands: return image
    largest = max(len(m) for m in islands)
    for members in islands:
        if len(members) < largest*keep:
            for i in members: px[i % w, i // w] = 0
    image.putalpha(alpha); return image

def extract(sheet, bounds, role, group, index):
    crop = bounds if isinstance(bounds, Image.Image) else sheet.crop(bounds)
    if role in TRANSPARENT_SOURCES and role == 'sniper':
        crop = drop_fragments(crop, keep=0.5)
    # Neighboring large attack effects cross a nominal sprite-cell boundary.
    if role == 'berserker' and group == 'attack':
        draw = ImageDraw.Draw(crop)
        if index == 1: draw.rectangle((1020-bounds[0],365-bounds[1],crop.width,crop.height), fill=(0,0,0,0))
        if index == 2: draw.rectangle((0,0,1047-bounds[0],355-bounds[1]), fill=(0,0,0,0))
    if role == 'necromancer' and group == 'summon' and index == 1:
        ImageDraw.Draw(crop).rectangle((778-bounds[0],320-bounds[1],crop.width,crop.height), fill=(0,0,0,0))
    bbox = crop.getchannel('A').getbbox()
    assert bbox, (role,group,index)
    crop = crop.crop(bbox)
    if group == 'walk': return crop, body_anchor(crop)
    # Boots, not weapon/effect extent, define a consistent world-space anchor.
    strip = crop.getchannel('A').crop((0,max(0,crop.height-12),crop.width,crop.height))
    weights = [sum(strip.getpixel((x,y)) for y in range(strip.height)) for x in range(strip.width)]
    total = sum(weights); cumulative = 0; anchor = crop.width//2
    for x,weight in enumerate(weights):
        cumulative += weight
        if cumulative >= total/2: anchor=x; break
    return crop, anchor

def main():
    OUT.mkdir(parents=True,exist_ok=True)
    metadata = {}
    previous_path = SOURCE/'new_units_frames.json'
    previous = json.loads(previous_path.read_text(encoding='utf-8')) if previous_path.exists() else {}
    regenerated = set()
    poses_by_role = dict(POSES)
    for role, rows in COMPONENT_POSES.items():
        sheet = Image.open(SOURCE/(role+'_sheet.png')).convert('RGBA')
        poses_by_role[role] = {group: component_cells(sheet, band, count, cuts) for group,(band,count,cuts) in rows.items()}
        poses_by_role[role]['idle'] = poses_by_role[role]['idle'][0]
        TRANSPARENT_SOURCES.add(role)
    for row,(role,poses) in enumerate(poses_by_role.items()):
        folder = OUT/'animations'/role
        expected = [folder/(group+'_'+str(i)+'.png') for group,rects in poses.items() if group!='idle' for i in range(len(rects))]
        if (OUT/(role+'.png')).exists() and all(path.exists() for path in expected):
            print('reuse completed cutout',role,flush=True)
            continue
        sheet = Image.open(SOURCE/(role+'_sheet.png')).convert('RGBA') if role in TRANSPARENT_SOURCES else cutout(SOURCE/(role+'_sheet.png'))
        idle,_ = extract(sheet,poses['idle'],role,'idle',0)
        portrait = Image.new('RGBA',(idle.width+16,idle.height+16),(0,0,0,0))
        portrait.alpha_composite(idle,(8,8)); portrait.save(OUT/(role+'.png'))
        groups = {group:[extract(sheet,bounds,role,group,i) for i,bounds in enumerate(rects)] for group,rects in poses.items() if group!='idle'}
        frames = [frame for group in groups.values() for frame in group]
        half_width = max(max(anchor,image.width-anchor) for image,anchor in frames)+8
        height = max(image.height for image,_ in frames)+16
        folder = OUT/'animations'/role; folder.mkdir(parents=True,exist_ok=True)
        for group,images in groups.items():
            for index,(image,anchor) in enumerate(images):
                canvas=Image.new('RGBA',(half_width*2,height),(0,0,0,0))
                canvas.alpha_composite(image,(half_width-anchor,height-8-image.height))
                canvas.save(folder/(group+'_'+str(index)+'.png'))
        print('extracted',role,flush=True)
        regenerated.add(role)
    preview = Image.new('RGBA',(240*len(poses_by_role),350),(10,13,22,255))
    for row,(role,poses) in enumerate(poses_by_role.items()):
        if role not in TRANSPARENT_SOURCES and (role in regenerated or previous.get(role,{}).get('cutout_version') != 2):
            for path in [OUT/(role+'.png'), *(OUT/'animations'/role).glob('*.png')]:
                image=Image.open(path).convert('RGBA')
                r,g,b,alpha=image.split()
                minimum=ImageChops.darker(ImageChops.darker(r,g),b)
                maximum=ImageChops.lighter(ImageChops.lighter(r,g),b)
                bright=minimum.point([255 if value>=180 else 0 for value in range(256)])
                neutral=ImageChops.subtract(maximum,minimum).point([255 if value<=28 else 0 for value in range(256)])
                for _ in range(2):
                    edge=ImageChops.subtract(alpha,alpha.filter(ImageFilter.MinFilter(3))).point([255 if value else 0 for value in range(256)])
                    matte=ImageChops.multiply(ImageChops.multiply(edge,bright),neutral)
                    alpha=ImageChops.subtract(alpha,matte)
                image.putalpha(alpha); image.save(path)
        portrait=Image.open(OUT/(role+'.png')).convert('RGBA')
        if role in regenerated or previous.get(role,{}).get('walk_anchor_version') != 1:
            before=[]; after=[]
            for path in sorted((OUT/'animations'/role).glob('walk_*.png')):
                frame=Image.open(path).convert('RGBA')
                anchor=body_anchor(frame); before.append(anchor)
                shift=frame.width//2-anchor
                aligned=Image.new('RGBA',frame.size,(0,0,0,0))
                aligned.alpha_composite(frame,(shift,0))
                assert sum(frame.getchannel('A').histogram()[1:]) == sum(aligned.getchannel('A').histogram()[1:]), ('clipped animation',path)
                aligned.save(path); after.append(body_anchor(aligned))
            print('torso alignment',role,'before span',max(before)-min(before),'after span',max(after)-min(after),flush=True)
        canvas=Image.open(OUT/'animations'/role/'walk_0.png')
        metadata[role]={'cutout_version':2,'walk_anchor_version':1,'portrait':portrait.size,'animation_canvas':canvas.size,'frames':{group:len(rects) for group,rects in poses.items() if group!='idle'}}
        view=portrait.copy(); view.thumbnail((210,280),Image.Resampling.NEAREST)
        preview.alpha_composite(view,(row*240+(240-view.width)//2,315-view.height))
        ImageDraw.Draw(preview).text((row*240+25,325),role,fill=(220,225,235,255))
    for effect,(source,boxes) in EFFECTS.items():
        sheet=Image.open(SOURCE/source).convert('RGBA'); folder=OUT/'effects'; folder.mkdir(parents=True,exist_ok=True)
        for index,box in enumerate(boxes):
            sheet.crop(box).save(folder/(effect+'_'+str(index)+'.png'))
        print('effect',effect,len(boxes),flush=True)
    for effect,(source,band,count,cuts) in COMPONENT_EFFECTS.items():
        sheet=Image.open(SOURCE/source).convert('RGBA'); folder=OUT/'effects'; folder.mkdir(parents=True,exist_ok=True)
        cells=component_cells(sheet,band,count,cuts); width=sheet.width/count
        # One shared box per effect keeps the frames registered to each other.
        boxes=[(box[0]-round(i*width),box[1],box[2]-round(i*width),box[3]) for i,box in enumerate(cell.getchannel('A').getbbox() for cell in cells)]
        union=(min(b[0] for b in boxes),min(b[1] for b in boxes),max(b[2] for b in boxes),max(b[3] for b in boxes))
        for index,cell in enumerate(cells):
            left=round(index*width)
            cell.crop((left+union[0],union[1],left+union[2],union[3])).save(folder/(effect+'_'+str(index)+'.png'))
        print('effect',effect,count,flush=True)
    preview.save(OUT/'new_units_preview.png')
    (SOURCE/'new_units_frames.json').write_text(json.dumps(metadata,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(metadata,indent=2))

if __name__=='__main__': main()
