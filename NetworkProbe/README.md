# SA-MP transport portability experiment

This isolated experiment checks compilation and linkage for iOS, not Arizona protocol compatibility. It is not integrated into the app.

Upstream: https://github.com/mishpro-programm/sampraknet

Pinned commit: `e891acf76dc4b95ad4fe95b353df2879394a445c`.

CI fetches the fixed revision and builds the transport plus a tiny consumer for iPhone ARM64 and Simulator x86_64. The executable is never run. No game server connections, account login or APK execution occur. Only logs are uploaded, not third-party source or linked binaries.

RakNet headers offer GPL-2.0-or-later; SA-MP additions and other bundled code have provenance/licensing questions documented by OpenSAMP. Successful compilation is not a licensing determination.

Not checked: runtime, handshake, reliability, payload ABI, Arizona RPC extensions, client validation, entities or gameplay.
