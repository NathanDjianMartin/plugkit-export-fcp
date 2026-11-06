# PlugKit Export for Final Cut Pro

Share destination (File > Share > PlugKit) + Workflow Extension panel + host app that uploads to PlugKit and schedules the post.
Modelled on how Frame.io's Mac app integrates with Final Cut (inspected from `/Applications/Frame.io.app`):

1. The host app ships a `.fcpxdest` (Export Media destination) whose job action is "Open with Application".
   Asking Final Cut to open that file installs the destination in File > Share.
2. Final Cut exports the movie, then opens it with the host app, which uploads it.
3. A Workflow Extension (Window > Extensions) holds the per-export settings; here: accounts, caption, date.

Build: `./build.sh` (Command Line Tools only). Install: `./install.sh` (copies to ~/Applications and launches; first launch
registers the extension and installs the destination). `tools/make_destination.py` rebuilds `Resources/PlugKit.fcpxdest`.
Host and panel exchange `~/Library/Application Support/PlugKit Export/{accounts,job,history}.json`; the API key stays in the host app.
