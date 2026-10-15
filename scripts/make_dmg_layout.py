"""Write the Finder layout directly, without opening or automating Finder."""
from pathlib import Path
import sys

from ds_store import DSStore
from mac_alias import Alias

mount = Path(sys.argv[1])
app = sys.argv[2]
with DSStore.open(str(mount / '.DS_Store'), 'w+') as store:
    store['.']['vstl'] = ('type', b'icnv')
    store['.']['bwsp'] = {
        'WindowBounds': '{{200, 120}, {600, 340}}', 'ShowToolbar': False,
        'ShowStatusBar': False, 'ShowSidebar': False, 'ShowPathbar': False,
        'ShowTabView': False, 'ContainerShowSidebar': False, 'SidebarWidth': 0,
    }
    store['.']['icvp'] = {
        'viewOptionsVersion': 1, 'backgroundType': 2,
        'backgroundImageAlias': Alias.for_file(str(mount / '.background/background.tiff')).to_bytes(),
        'iconSize': 112.0, 'textSize': 12.0, 'gridSpacing': 100.0,
        'gridOffsetX': 0.0, 'gridOffsetY': 0.0, 'labelOnBottom': True,
        'showIconPreview': True, 'showItemInfo': False, 'arrangeBy': 'none',
    }
    store[app]['Iloc'] = (150, 155)
    store['Applications']['Iloc'] = (450, 155)
