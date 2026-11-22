#!/usr/bin/env python3
"""Publish a verified PKG as a public development release, then prepare its feed."""
import argparse, hashlib, json, os, plistlib, re, subprocess, sys, tempfile, urllib.parse
from pathlib import Path

def require(condition, message):
    if not condition: raise RuntimeError(message)

def credential():
    result = subprocess.run(["git", "credential", "fill"],
                            input="protocol=https\nhost=github.com\n\n", text=True, capture_output=True,
                            env={**os.environ, "GIT_TERMINAL_PROMPT": "0"}, timeout=15)
    require(result.returncode == 0, "GitHub git credential unavailable")
    fields = dict(line.split("=", 1) for line in result.stdout.splitlines() if "=" in line)
    require(bool(fields.get("password")), "GitHub git credential unavailable")
    return fields["password"]


class GitHub:
 def __init__(self): self.token=credential()
 def request(self,path,method='GET',body=None,raw=None,download_limit=None,content_type='application/json'):
  url=path if path.startswith('https://') else 'https://api.github.com'+path
  parsed=urllib.parse.urlparse(url)
  require(parsed.hostname in {'api.github.com','uploads.github.com'} and parsed.scheme=='https','Unexpected API host')
  require(method in {'GET','POST','PATCH'},'Unexpected method')
  headers={'Authorization':'Bearer '+self.token,'User-Agent':'MacUtil-family-release','Accept':'application/octet-stream' if download_limit is not None else 'application/vnd.github+json','X-GitHub-Api-Version':'2022-11-28'}
  data=raw if raw is not None else json.dumps(body).encode() if body is not None else None
  if data is not None: headers['Content-Type']=content_type
  def quote(value):
   require('\n' not in value and '\r' not in value,'Invalid header')
   return '"'+value.replace('\\','\\\\').replace('"','\\"')+'"'
  for _ in range(4):
   config='url = '+quote(url)+'\n'+''.join('header = '+quote(k+': '+v)+'\n' for k,v in headers.items())
   with tempfile.TemporaryFile() as f:
    args=['curl','--silent','--show-error','--include','--suppress-connect-headers','--connect-timeout','20','--max-time','120','--noproxy','*','--request',method,'--config','-']
    if data is not None: f.write(data);f.flush();f.seek(0);args+=['--data-binary','@/dev/fd/'+str(f.fileno())]
    p=subprocess.run(args,input=config.encode(),capture_output=True,pass_fds=(f.fileno(),))
   if p.returncode != 0 and method == 'GET':
    print('Read transport retry, curl code',p.returncode,file=sys.stderr);continue
   require(p.returncode==0,'curl transport failed (code '+str(p.returncode)+'); inspect remote state before retrying mutations')
   response=p.stdout
   while True:
    head,sep,payload=response.partition(b'\r\n\r\n')
    if not sep: head,sep,payload=response.partition(b'\n\n')
    require(bool(sep),'Invalid HTTP response')
    lines=head.decode('iso-8859-1').splitlines();status=int(lines[0].split()[1])
    if status==100: response=payload;continue
    break
   if method=='GET' and download_limit is not None and status in {301,302,303,307,308}:
    h=dict(line.split(':',1) for line in lines[1:] if ':' in line)
    location=next((v.strip() for k,v in h.items() if k.lower()=='location'),'');target=urllib.parse.urlparse(location)
    require(target.scheme=='https' and target.hostname and target.hostname.endswith('.githubusercontent.com'),'Invalid redirect')
    url=location;headers={'User-Agent':'MacUtil-family-release'};continue
   if status in {502,503,504} and method == 'GET': continue
   require(200<=status<300,'GitHub HTTP '+str(status))
   require(len(payload)<=(download_limit if download_limit is not None else 8*1024*1024),'Response too large')
   return payload if download_limit is not None else json.loads(payload)
  raise RuntimeError('Too many redirects')

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('bundle',type=Path)
    parser.add_argument('package',type=Path)
    parser.add_argument('feed_directory',type=Path)
    parser.add_argument('--source-commit',required=True)
    parser.add_argument('--resume-draft',action='store_true')
    parser.add_argument('--notes-file',type=Path,help='Markdown summary of this release, placed before the provenance lines')
    args=parser.parse_args()
    require(bool(re.fullmatch('[0-9a-f]{40}',args.source_commit)),'Expected source commit SHA')
    info=plistlib.loads((args.bundle/'Contents/Info.plist').read_bytes())
    product=info['CFBundleExecutable']; version=info['CFBundleShortVersionString']; build=int(info['CFBundleVersion'])
    source_root=Path(__file__).resolve().parents[1]
    committed=plistlib.loads(subprocess.check_output(['git','show',args.source_commit+':Resources/Info.plist'],cwd=source_root))
    require(all(committed.get(key)==info.get(key) for key in ['CFBundleExecutable','CFBundleIdentifier','CFBundleShortVersionString','CFBundleVersion']), 'Source commit and packaged version differ')
    local_tag=subprocess.check_output(['git','rev-parse','v'+version+'^{commit}'],cwd=source_root,text=True).strip()
    require(local_tag==args.source_commit,'Local release tag points to a different source commit')
    remote=subprocess.check_output(['git','ls-remote','origin','refs/tags/v'+version+'^{}'],cwd=source_root,text=True).split()
    require(bool(remote) and remote[0]==args.source_commit,'Push the matching annotated source tag before publishing')
    require(product in ['MacUtilRight','MacUtilPaste','MacUtilBar','MacUtils'],'Unknown product')
    require(bool(re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+',version)) and build>0,'Invalid version')
    require(args.package.name.startswith(product+'-'+version+'-macos-') and args.package.suffix=='.pkg','Wrong package')
    checksum=args.package.with_suffix('.sha256')
    package=args.package.read_bytes()
    require(checksum.read_text()==hashlib.sha256(package).hexdigest()+'  '+args.package.name+'\n','Checksum mismatch')
    api=GitHub(); prefix='/repos/PanggNOTlovebean/MacUtils-Releases'
    repo=api.request(prefix)
    require(repo['full_name']=='PanggNOTlovebean/MacUtils-Releases' and repo['private']==False,'Public release repository mismatch')
    tag=product+'-v'+version
    releases=api.request(prefix+'/releases?per_page=100')
    matching=[r for r in releases if r['tag_name']==tag]
    require(not matching or (args.resume_draft and len(matching)==1 and matching[0]['draft'] and args.source_commit in matching[0]['body']), 'Release exists; only explicitly resume a matching draft')
    summary=args.notes_file.read_text().strip() if args.notes_file else None
    require(summary is None or (0 < len(summary) <= 4000),'Release notes must be 1-4000 characters')
    notes=f'''{summary}

Version: {version} / build {build}
Source commit: {args.source_commit}
Package: {args.package.name}

Development candidate: ad-hoc signed application, unsigned PKG, not notarized. Install manually; existing configuration and app identities are retained.
''' if summary else f'''Adds Settings → Software Update → Check for Updates. Checks public version metadata only when clicked, then opens this repository to download a PKG for manual installation.

Version: {version} / build {build}
Source commit: {args.source_commit}
Package: {args.package.name}

Development candidate: ad-hoc signed application, unsigned PKG, not notarized. No automatic installation or background checks. The first updater-enabled version must be installed manually. Existing configuration and app identities are retained.

Validation: full Swift tests, release build, strict app/extension code-signature verification, extracted PKG payload comparison. Physical UI clicking and installation have not been validated for this release.
'''
    release=matching[0] if matching else api.request(prefix+'/releases',method='POST',body={'tag_name':tag,'target_commitish':'main','name':product+' '+version,'body':notes,'draft':True,'prerelease':True})
    for file in [args.package,checksum]:
        raw=file.read_bytes()
        upload=release['upload_url'].split('{')[0]+'?'+urllib.parse.urlencode({'name':file.name})
        existing=[item for item in release['assets'] if item['name']==file.name]
        require(len(existing)<=1,'Duplicate release asset')
        asset=existing[0] if existing else api.request(upload,method='POST',raw=raw,content_type='application/octet-stream')
        require(asset['state']=='uploaded' and asset['size']==len(raw),'Incomplete draft asset; inspect before continuing')
        downloaded=api.request(asset['url'],download_limit=len(raw))
        require(downloaded==raw,'Uploaded asset did not round-trip: '+file.name)
    release=api.request(prefix+'/releases/'+str(release['id']),method='PATCH',body={'draft':False,'prerelease':True,'make_latest':'false'})
    require(not release['draft'],'Release not published')
    expected='https://github.com/PanggNOTlovebean/MacUtils-Releases/releases/tag/'+tag
    require(release['html_url']==expected,'Release URL mismatch')
    feed={'schemaVersion':1,'product':product,'bundleIdentifier':info['CFBundleIdentifier'],'version':version,
          'build':build,'minimumSystemVersion':'14.0.0','releaseURL':expected}
    args.feed_directory.mkdir(parents=True,exist_ok=True)
    destination=args.feed_directory/(product+'.json')
    if destination.exists():
        require(json.loads(destination.read_text())['build']<build,'Refusing non-increasing feed')
    destination.write_text(json.dumps(feed,indent=2)+'\n')
    print(expected)

if __name__=='__main__': main()
