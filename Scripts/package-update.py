#!/usr/bin/env python3
"""Package a verified local app as an unsigned, nonrelocatable development PKG."""
import argparse
import hashlib
import plistlib
import shutil
import subprocess
import tempfile
from pathlib import Path

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('bundle', type=Path)
p.add_argument('output', type=Path)
a = p.parse_args()
bundle = a.bundle.resolve()
info = plistlib.loads((bundle / 'Contents/Info.plist').read_bytes())
product = info['CFBundleExecutable']
identities = {'MacUtilRight': 'local.macutilright.app', 'MacUtilPaste': 'local.macutilpaste.app',
              'MacUtilBar': 'local.macutilbar.app', 'MacUtils': 'local.macutils2.app'}
assert identities.get(product) == info['CFBundleIdentifier']
assert bundle.name == ('MacUtils 截图.app' if product == 'MacUtils' else product + '.app')
version = info['CFBundleShortVersionString']
assert len(version.split('.')) == 3 and all(x.isdigit() for x in version.split('.'))
def run(*args): subprocess.run([str(x) for x in args], check=True)
run('codesign', '--verify', '--deep', '--strict', bundle)
assert 'Signature=adhoc' in subprocess.run(['codesign','-dvv',str(bundle)], capture_output=True, text=True, check=True).stderr
archs = subprocess.check_output(['lipo','-archs',str(bundle/'Contents/MacOS'/product)], text=True).split()
assert set(archs) in [{'arm64'}, {'x86_64'}, {'arm64','x86_64'}]
architecture = 'universal' if len(archs) == 2 else archs[0]
for ext in bundle.glob('Contents/PlugIns/*.appex'):
 run('codesign','--verify','--deep','--strict',ext)
 metadata=plistlib.loads((ext/'Contents/Info.plist').read_bytes())
 assert metadata['CFBundleShortVersionString']==version and metadata['CFBundleVersion']==info['CFBundleVersion']
a.output.mkdir(parents=True, exist_ok=True)
pkg = a.output.resolve()/f'{product}-{version}-macos-{architecture}.pkg'
assert not pkg.exists(), 'Refusing to replace an existing PKG'
with tempfile.TemporaryDirectory(prefix='.pkg-', dir=a.output) as temp:
 stage=Path(temp); root=stage/'root'; root.mkdir()
 run('ditto',bundle,root/bundle.name)
 components=stage/'components.plist'
 run('pkgbuild','--analyze','--root',root,components)
 entries=plistlib.loads(components.read_bytes())
 for entry in entries:
  entry.update(BundleIsRelocatable=False,BundleIsVersionChecked=True,BundleHasStrictIdentifier=True,BundleOverwriteAction='upgrade')
 components.write_bytes(plistlib.dumps(entries))
 run('pkgbuild','--root',root,'--component-plist',components,'--install-location','/Applications',
     '--identifier',identities[product]+'.pkg','--version',version,'--ownership','recommended',stage/'component.pkg')
 distribution=stage/'distribution.xml'
 distribution.write_text(f'''<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2"><title>{product} {version}</title>
<options customize="never" require-scripts="false" hostArchitectures="{','.join(archs)}"/>
<domains enable_anywhere="false" enable_currentUserHome="false" enable_localSystem="true"/>
<volume-check><allowed-os-versions><os-version min="14.0"/></allowed-os-versions></volume-check>
<choices-outline><line choice="default"/></choices-outline>
<choice id="default" visible="false"><pkg-ref id="{identities[product]}.pkg"/></choice>
<pkg-ref id="{identities[product]}.pkg" version="{version}" onConclusion="none">component.pkg</pkg-ref>
</installer-gui-script>''')
 run('productbuild','--distribution',distribution,'--package-path',stage,stage/'product.pkg')
 run('pkgutil','--expand-full',stage/'product.pkg',stage/'expanded')
 extracted=stage/'expanded/component.pkg/Payload'/bundle.name
 run('codesign','--verify','--deep','--strict',extracted)
 run('diff','-qr',bundle,extracted)
 shutil.move(stage/'product.pkg',pkg)
sums=pkg.with_suffix('.sha256')
sums.write_text(hashlib.sha256(pkg.read_bytes()).hexdigest()+'  '+pkg.name+'\n')
print(pkg)
