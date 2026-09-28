import subprocess
import tempfile
from pathlib import Path

source = Path('ios/Runner/AppDelegate.swift').read_text()
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
'''
with tempfile.TemporaryDirectory(prefix='clear-forum-policy-') as directory:
    script = Path(directory) / 'policy.swift'
    script.write_text('import Foundation\nprivate enum SitePolicy {' + policy + checks)
    subprocess.run(['swift', str(script)], check=True)
