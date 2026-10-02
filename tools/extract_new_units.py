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
}

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

def extract(sheet, bounds, role, group, index):
    crop = sheet.crop(bounds)
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
    preview = Image.new('RGBA',(960,350),(10,13,22,255))
    metadata = {}
    previous_path = SOURCE/'new_units_frames.json'
    previous = json.loads(previous_path.read_text(encoding='utf-8')) if previous_path.exists() else {}
    regenerated = set()
    for row,(role,poses) in enumerate(POSES.items()):
        folder = OUT/'animations'/role
        expected = [folder/(group+'_'+str(i)+'.png') for group,rects in poses.items() if group!='idle' for i in range(len(rects))]
        if (OUT/(role+'.png')).exists() and all(path.exists() for path in expected):
            print('reuse completed cutout',role,flush=True)
            continue
        sheet = cutout(SOURCE/(role+'_sheet.png'))
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
    for row,(role,poses) in enumerate(POSES.items()):
        if role in regenerated or previous.get(role,{}).get('cutout_version') != 2:
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
        canvas=Image.open(OUT/'animations'/role/'walk_0.png')
        metadata[role]={'cutout_version':2,'portrait':portrait.size,'animation_canvas':canvas.size,'frames':{group:len(rects) for group,rects in poses.items() if group!='idle'}}
        view=portrait.copy(); view.thumbnail((210,280),Image.Resampling.NEAREST)
        preview.alpha_composite(view,(row*240+(240-view.width)//2,315-view.height))
        ImageDraw.Draw(preview).text((row*240+25,325),role,fill=(220,225,235,255))
    preview.save(OUT/'new_units_preview.png')
    (SOURCE/'new_units_frames.json').write_text(json.dumps(metadata,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(metadata,indent=2))

if __name__=='__main__': main()
