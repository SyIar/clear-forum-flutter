import subprocess
import tempfile
from pathlib import Path

source = Path('ios/Runner/AppDelegate.swift').read_text()
media_source = Path('ios/Runner/MediaSupport.swift').read_text()
media_policy = 'enum MediaPolicy {' + media_source.split('enum MediaPolicy {', 1)[1].split('// Only controlled labels', 1)[0]
media_policy += '\nstruct MediaFailure: Error { let reason: String }\n'
policy = source.split('private enum SitePolicy {', 1)[1].split('private final class ForumSessionBridge', 1)[0]
checks = r'''
let allowed = ["https://simpcity.cr/", "https://simpcity.cr/forums/news.6/", "https://simpcity.cr/threads/topic.123/page-2", "https://simpcity.cr/threads/%E6%B5%8B%E8%AF%95.123/"]
for address in allowed { precondition(SitePolicy.readable(URL(string: address)!), "Should allow: \(address)") }
let denied = ["http://simpcity.cr/", "https://simpcity.cr.example/", "https://user:secret@simpcity.cr/", "https://simpcity.cr:8443/", "https://simpcity.cr/logout/", "https://simpcity.cr/threads/topic.123/watch", "https://simpcity.cr/?_xfToken=secret", "https://simpcity.cr/?page=1&page=2", "https://simpcity.cr/threads/a%2Fb.1/"]
for address in denied { precondition(!SitePolicy.readable(URL(string: address)!), "Should deny: \(address)") }
let cookie = HTTPCookie(properties: [.name: "session", .value: "synthetic", .domain: ".simpcity.cr", .path: "/forums", .secure: "TRUE"])!
precondition(SitePolicy.matches(cookie, url: URL(string: "https://simpcity.cr/forums/news.6/")!))
precondition(!SitePolicy.matches(cookie, url: URL(string: "https://simpcity.cr/forums-other/")!))
precondition(!SitePolicy.matches(cookie, url: URL(string: "https://outside.example/forums/")!))
print("Native URL and cookie policy checks passed")
precondition(MediaPolicy.allowed(URL(string: "https://media.example/sample.m3u8?token=synthetic")!))
for address in ["file:///private/file", "http://media.example/a.mp4", "https://user:secret@media.example/a.mp4", "https://media.example:9443/a.mp4"] { precondition(!MediaPolicy.allowed(URL(string: address)!)) }
precondition(!MediaPolicy.sameOrigin(URL(string: "https://ads.example/embed/")!, URL(string: "https://player.example/embed/")!))
let mediaCookie = HTTPCookie(properties: [.name: "media", .value: "synthetic", .domain: ".media.example", .path: "/assets", .secure: "TRUE"])!
precondition(MediaPolicy.cookieMatches(mediaCookie, URL(string: "https://cdn.media.example/assets/a.mp4")!))
precondition(!MediaPolicy.cookieMatches(mediaCookie, URL(string: "https://media.example/assets-other/a.mp4")!))
precondition(!MediaPolicy.cookieMatches(cookie, URL(string: "https://media.example/assets/a.mp4")!))
print("Native media URL and cookie isolation checks passed")
'''
with tempfile.TemporaryDirectory(prefix='clear-forum-policy-') as directory:
    script = Path(directory) / 'policy.swift'
    script.write_text('import Foundation\nprivate enum SitePolicy {' + policy + media_policy + checks)
    subprocess.run(['swift', str(script)], check=True)
