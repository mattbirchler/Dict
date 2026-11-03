# dmgbuild settings for Dict's disk image. Run through scripts/dmg.sh,
# which sets APP_PATH.
import os

application = os.environ["APP_PATH"]
appname = os.path.basename(application)

format = "UDZO"
size = None
files = [application]
symlinks = {"Applications": "/Applications"}
icon_locations = {appname: (150, 185), "Applications": (450, 185)}
background = "scripts/dmg/background.png"
window_rect = ((200, 120), (600, 380))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
sidebar_width = 0
icon_size = 112
text_size = 13
arrange_by = None
show_icon_preview = False
include_icon_view_settings = "auto"
include_list_view_settings = "auto"
