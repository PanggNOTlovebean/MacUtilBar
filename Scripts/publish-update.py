#!/usr/bin/env python3
"""Publish a verified PKG as a public development release, then prepare its feed."""
import argparse, hashlib, json, os, plistlib, re, ssl, subprocess, urllib.error, urllib.parse, urllib.request
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


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


class GitHub:
    def __init__(self):
        self._token = credential()  # Kept in memory; never included in output or files.
        certificate = "/etc/ssl/cert.pem"
        context = ssl.create_default_context(cafile=certificate if Path(certificate).is_file() else None)
        self._opener = urllib.request.build_opener(NoRedirect(), urllib.request.HTTPSHandler(context=context))

    def request(self, path, method="GET", body=None, raw=None, download_limit=None, content_type="application/json"):
        url = path if path.startswith("https://") else "https://api.github.com" + path
        parsed = urllib.parse.urlparse(url)
        require(parsed.scheme == "https" and parsed.hostname in {"api.github.com", "uploads.github.com"}
                and parsed.username is None and parsed.password is None, "Unexpected authenticated endpoint")
        require(method in {"GET", "POST", "PATCH"}, "Unsupported HTTP method")
        headers = {"Authorization": "Bearer " + self._token, "User-Agent": "MacUtil-family-release",
                   "Accept": "application/octet-stream" if download_limit is not None else "application/vnd.github+json",
                   "X-GitHub-Api-Version": "2022-11-28"}
        payload = raw if raw is not None else (json.dumps(body).encode() if body is not None else None)
        if payload is not None:
            headers["Content-Type"] = content_type
        limit = download_limit if download_limit is not None else 8 * 1024 * 1024
        for redirect in range(4):
            request = urllib.request.Request(url, headers=headers, data=payload, method=method)
            try:
                with self._opener.open(request, timeout=120) as response:
                    data = response.read(limit + 1)
                require(len(data) <= limit, "GitHub response exceeds the expected size")
                return data if download_limit is not None else json.loads(data)
            except urllib.error.HTTPError as error:
                if method == "GET" and download_limit is not None and error.code in {301, 302, 303, 307, 308}:
                    location = error.headers.get("Location", "")
                    destination = urllib.parse.urlparse(location)
                    require(destination.scheme == "https" and destination.hostname is not None
                            and destination.hostname.endswith(".githubusercontent.com")
                            and destination.username is None and destination.password is None,
                            "Unexpected asset redirect")
                    # Never send the token to a signed asset URL, including later redirects.
                    url, headers = location, {"User-Agent": "MacUtil-family-release"}
                    continue
                raise RuntimeError("GitHub HTTP " + str(error.code)) from None
            except urllib.error.URLError:
                raise RuntimeError("GitHub transport failed; inspect remote state before retrying mutations") from None
        raise RuntimeError("Too many asset redirects")


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('bundle',type=Path)
    parser.add_argument('package',type=Path)
    parser.add_argument('feed_directory',type=Path)
    parser.add_argument('--source-commit',required=True)
    args=parser.parse_args()
    require(bool(re.fullmatch('[0-9a-f]{40}',args.source_commit)),'Expected source commit SHA')
    info=plistlib.loads((args.bundle/'Contents/Info.plist').read_bytes())
    product=info['CFBundleExecutable']; version=info['CFBundleShortVersionString']; build=int(info['CFBundleVersion'])
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
    require(not matching,'Release already exists: inspect it before resuming; never overwrite published assets')
    notes=f'''Adds Settings → Software Update → Check for Updates. Checks public version metadata only when clicked, then opens this repository to download a PKG for manual installation.

Version: {version} / build {build}
Source commit: {args.source_commit}
Package: {args.package.name}

Development candidate: ad-hoc signed application, unsigned PKG, not notarized. No automatic installation or background checks. The first updater-enabled version must be installed manually. Existing configuration and app identities are retained.

Validation: full Swift tests, release build, strict app/extension code-signature verification, extracted PKG payload comparison. Physical UI clicking and installation have not been validated for this release.
'''
    release=api.request(prefix+'/releases',method='POST',body={'tag_name':tag,'target_commitish':'main','name':product+' '+version,'body':notes,'draft':True,'prerelease':True})
    for file in [args.package,checksum]:
        raw=file.read_bytes()
        upload=release['upload_url'].split('{')[0]+'?'+urllib.parse.urlencode({'name':file.name})
        asset=api.request(upload,method='POST',raw=raw,content_type='application/octet-stream')
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
