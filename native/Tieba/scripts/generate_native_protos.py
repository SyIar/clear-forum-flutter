"""Generate native Swift protocols with the same pinned SwiftProtobuf runtime."""
import re
import shutil
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parent.parent
output = root / 'Core/Generated'
output.mkdir(parents=True, exist_ok=True)
checkout = root / '.build/checkouts/swift-protobuf'
subprocess.run(['swift', 'package', '--package-path', str(root), 'resolve'], check=True)
shutil.copy2(checkout / 'LICENSE.txt', root / 'Resources/SwiftProtobuf-LICENSE.txt')
subprocess.run(['swift', 'build', '--package-path', str(checkout), '-c', 'release', '--product', 'protoc-gen-swift'], check=True)
plugin = checkout / '.build/release/protoc-gen-swift'
schema = root / '.build/native-schema'
files = []
scalar = re.compile(r'^(\s*)((?:u?int|sint|fixed|sfixed)(?:32|64)|bool|string|bytes|double|float)(\s+\w+\s*=)')
for source in sorted((root / 'proto').rglob('*.proto')):
    # Dart retains explicitly assigned zero values. Preserve request field
    # presence in Swift without changing field numbers or wire types.
    lines = []
    depth = 0
    messages = []
    for line in source.read_text().splitlines():
        declaration = re.match(r'\s*message\s+(\w+)\s*\{', line)
        if declaration:
            messages.append((depth, declaration.group(1)))
        if any('Request' in name for _, name in messages):
            line = scalar.sub(r'\1optional \2\3', line)
        lines.append(line)
        depth += line.count('{') - line.count('}')
        while messages and depth <= messages[-1][0]:
            messages.pop()
    target = schema / source.relative_to(root / 'proto')
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text('\n'.join(lines) + '\n')
    files.append(target)
subprocess.run(['protoc', f'--plugin=protoc-gen-swift={plugin}', '-I', str(schema),
                f'--swift_out={output}', '--swift_opt=FileNaming=PathToUnderscores', '--swift_opt=UseAccessLevelOnImports=false',
                *map(str, files)], check=True)

# Read the generated declarations instead of assuming package-name casing.
types = {}
for path in output.glob('*.swift'):
    for match in re.finditer(r'\bstruct\s+(\w+)\s*[:{]', path.read_text()):
        types[match.group(1).split('_')[-1]] = match.group(1)
codecs = ['FrsPage', 'PbPage', 'PbFloor', 'Personalized', 'UserLike', 'HotThreadList', 'TopicList',
          'SearchSug', 'Profile', 'UserPost', 'GetForumDetail', 'ForumRuleDetail', 'AddPost']
lines = ['import Foundation', 'import SwiftProtobuf', '', 'enum ProtoCodec {',
         '  static func encode(_ name: String, json: Data) throws -> Data {', '    switch name {']
for codec in codecs:
    lines.append(f'    case "{codec}": return try {types[codec + "Request"]}(jsonUTF8Data: json).serializedData()')
lines += ['    default: throw APIError(message: "Unknown protocol request.")', '    }', '  }',
          '  static func decode(_ name: String, bytes: Data) throws -> JSON {', '    let data: Data', '    switch name {']
for codec in codecs:
    lines.append(f'    case "{codec}": data = try {types[codec + "Response"]}(serializedBytes: bytes).jsonUTF8Data()')
lines += ['    default: throw APIError(message: "Unknown protocol response.")', '    }',
          '    return (try JSONSerialization.jsonObject(with: data)) as? JSON ?? [:]', '  }', '}', '']
(root / 'Core/ProtoCodec.swift').write_text('\n'.join(lines))
print(f'Generated {len(files)} protocol files and {len(codecs)} request/response codecs')
