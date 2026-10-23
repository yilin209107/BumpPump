#!/usr/bin/env python3
"""Package only public source and the fresh standalone BumpPump application."""
from pathlib import Path
import hashlib,json,plistlib,re,stat,subprocess,zipfile

ROOT=Path(__file__).resolve().parent.parent
OUT=ROOT/'outputs'
FORBIDDEN={'.db','.sqlite','.sqlite3','.enc','.key','.pem','.p12','.pyc'}

def write_zip(path,entries):
    with zipfile.ZipFile(path,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
        for file,name in entries:
            data=file.read_bytes()
            if file.suffix in FORBIDDEN:raise RuntimeError('Private file type in release')
            if file.suffix in {'.md','.swift','.sh','.py','.json','.yml','.toml'}:
                if re.search(rb'sk-[A-Za-z0-9]{24,}',data):raise RuntimeError('Possible credential in source')
                if b'/' + b'Users/' in data:raise RuntimeError('Machine-specific path in source')
            info=zipfile.ZipInfo(str(name));info.create_system=3;info.compress_type=zipfile.ZIP_DEFLATED
            info.external_attr=(file.stat().st_mode&0xffff)<<16
            z.writestr(info,data)
    with zipfile.ZipFile(path) as z:
        if z.testzip():raise RuntimeError('ZIP verification failed')
        for file,name in entries:
            if z.read(str(name)) != file.read_bytes():raise RuntimeError('ZIP content mismatch')

def main():
    app=ROOT/'dist/BumpPump.app'
    subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
    version=plistlib.loads((app/'Contents/Info.plist').read_bytes())['CFBundleShortVersionString']
    OUT.mkdir(exist_ok=True)
    source=[]
    for raw in ['Package.swift','README.md','LICENSE','THIRD_PARTY_NOTICES.md','AGENTS.md','.gitignore','.github','Sources','Resources','Tests','script','docs']:
        p=ROOT/raw
        for f in ([p] if p.is_file() else p.rglob('*')):
            if f.is_file() and '__pycache__' not in f.parts and f.name!='.DS_Store':source.append((f,Path('BumpPump')/f.relative_to(ROOT)))
    source_zip=OUT/f'BumpPump-Source-v{version}.zip'
    app_zip=OUT/f'BumpPump-macOS-arm64-v{version}.zip'
    write_zip(source_zip,source)
    entries=[(f,Path('BumpPump.app')/f.relative_to(app)) for f in sorted(app.rglob('*')) if f.is_file()]
    entries.append((ROOT/'docs/INSTALL.md',Path('安装说明.md')))
    write_zip(app_zip,entries)
    manifest={'name':'BumpPump','chineseName':'泵碰','version':version,'bundleIdentifier':'app.bumppump.mac','platform':'Apple Silicon, macOS 14+; Liquid Glass on macOS 26+','signing':'ad-hoc; not notarized','personalDataIncluded':False,'apiKeysIncluded':False,'startsWithFirstRunSetup':True,'artifacts':[]}
    for f in [app_zip,source_zip]:manifest['artifacts'].append({'filename':f.name,'bytes':f.stat().st_size,'sha256':hashlib.sha256(f.read_bytes()).hexdigest()})
    (OUT/'release-manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
    (OUT/'SHA256SUMS').write_text(''.join(f['sha256']+'  '+f['filename']+'\n' for f in manifest['artifacts']))
    print(json.dumps(manifest,ensure_ascii=False,indent=2))

if __name__=='__main__':main()
