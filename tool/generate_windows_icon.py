"""Package the approved transparent Flutter vector-mark export for app platforms.

To refresh the master after changing BrandLogo, run the logo export test and
copy outputs/app-redesign/logo-launcher.png to assets/branding/content-maker-launcher.png.
The in-app and OAuth master retains its dark M.
"""
from pathlib import Path
from base64 import b64encode
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
MASTER = ROOT / 'assets/branding/content-maker-launcher.png'
image = Image.open(MASTER).convert('RGBA')
assert image.getpixel((0, 0))[3] == 0, 'The approved logo must be transparent.'
resources = ROOT / 'windows/runner/resources'
image.save(resources / 'app_icon.png')
image.save(resources / 'app_icon.ico', format='ICO', sizes=[(16,16),(24,24),(32,32),(48,48),(64,64),(128,128),(256,256)])
Image.open(ROOT / 'assets/branding/content-maker-logo.png').save(ROOT / 'assets/branding/content-maker-oauth-logo.png')
for density, size in {'mdpi':48,'hdpi':72,'xhdpi':96,'xxhdpi':144,'xxxhdpi':192}.items():
    image.resize((size,size), Image.Resampling.LANCZOS).save(ROOT / f'android/app/src/main/res/mipmap-{density}/ic_launcher.png')
public = ROOT / 'website/website/public'
image.save(public / 'content-maker-icon.png')
image.save(public / 'content-maker-icon-white-m.png')
# Embedding the master keeps favicon identity exact without requiring a web font.
encoded = b64encode(MASTER.read_bytes()).decode('ascii')
(public / 'favicon.svg').write_text(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512"><image width="512" height="512" href="data:image/png;base64,{encoded}"/></svg>\n', encoding='utf-8')
print('Packaged transparent Windows, Android, OAuth and local website logo assets.')
