# Board.app docs

The map. Each doc describes what is built; "Not built" lines say what is not.

- [Architecture](docs/architecture.md): the Swift package, the two apps, the scripts.
- [Security](docs/security.md): keys, allowed signers, what pairing grants.
- [Signing](docs/signing.md): what is signed, who owns the bytes, the firewall and the vectors.
- [Sync](docs/sync.md): how the phone and the Mac meet in iCloud.
- [Devices](docs/devices.md): pairing, revoking and a lost device.
- [TestFlight](docs/testflight.md): sending the iPhone app through TestFlight, and what the owner sets up first.
- [Bundle](docs/bundle.md): the Board release the Mac app carries, and how it installs.
- [Launcher](docs/launcher.md): the search panel on the Mac, its keys and its safety rules.
  - [Contract](docs/launcher-contract.md): what a provider prints, with a full example.
  - [Providers](docs/launcher-providers.md): the config file, writing a provider, and the example.
  - [Safety](docs/launcher-safety.md): what the launcher runs, opens and reads, and what it refuses.
