"""Compatibility entry point: resize the approved master instead of redrawing it."""
import runpy
from pathlib import Path

runpy.run_path(str(Path(__file__).with_name('generate_icons.py')), run_name='__main__')
print('Resized the approved Forum Lite icon at every catalog size.')
