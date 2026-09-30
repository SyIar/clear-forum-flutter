from pathlib import Path
from tree_sitter import Language, Parser
import tree_sitter_swift

root = Path(__file__).resolve().parents[1]
parser = Parser(Language(tree_sitter_swift.language()))
failures = []
files = list((root / 'native').rglob('*.swift')) + list((root / 'scripts').glob('*.swift')) + [root / 'ios/Runner/MediaSupport.swift', root / 'ios/Runner/MediaPlayerController.swift']
for path in files:
    # These imported, previously compiled files use syntax not supported by this
    # tree-sitter grammar. CI runs Apple's parser and compiles the whole module.
    if path.relative_to(root).as_posix() in {
        'native/Tieba/Core/Models.swift',
        'native/Tieba/App/ReplyEditor.swift',
        'native/Tieba/App/SettingsView.swift',
    }:
        continue
    tree = parser.parse(path.read_bytes())
    if tree.root_node.has_error:
        stack = [tree.root_node]
        while stack:
            node = stack.pop()
            if node.type == 'ERROR' or node.is_missing:
                failures.append(f'{path.relative_to(root)}:{node.start_point.row + 1}: {node.type}')
            stack.extend(reversed(node.children))
if failures:
    raise SystemExit('\n'.join(failures))
print('Swift syntax checked; 3 imported Tieba files require the Apple parser in CI. This is not compilation or type checking.')
