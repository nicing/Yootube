# Third-party notices

Yootube bundles unmodified runtime components from these projects:

- Invidious, commit `049d591d294e2a43cb32b97a0bb018c2093e5beb`, AGPL-3.0-only: https://github.com/iv-org/invidious
- Invidious Companion, `release-master`, AGPL-3.0: https://github.com/iv-org/invidious-companion
- PostgreSQL 18.6, PostgreSQL License: https://www.postgresql.org/
- PostgreSQL macOS binaries from `theseus-rs/postgresql-binaries`: https://github.com/theseus-rs/postgresql-binaries
- OpenSSL 3.6.3, Apache License 2.0: https://www.openssl.org/
- Crystal 1.21.0 is used only while building Invidious: https://crystal-lang.org/
- Sparkle 2.10.0 powers app updates, MIT License: https://github.com/sparkle-project/Sparkle

The corresponding license texts are copied into `Yootube.app/Contents/Resources/Runtime/licenses` during packaging. The complete source for the bundled Invidious revision is available from its repository at the commit above.
Sparkle's license is copied to `Yootube.app/Contents/Resources/Sparkle-LICENSE.txt`.
# Interface design and icons

The native interface adapts semantic colors and component dimensions from
[Cloudflare Kumo](https://github.com/cloudflare/kumo), MIT License, copyright
2026 Cloudflare, Inc. It uses native SwiftUI components rather than the React
package. Icons are from [Phosphor Icons](https://github.com/phosphor-icons/core),
MIT License. Both license texts ship in the app resource bundle's `Icons` folder.
