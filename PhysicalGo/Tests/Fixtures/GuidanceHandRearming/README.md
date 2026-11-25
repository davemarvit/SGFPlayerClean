# Hand-stop rearming status contract

These three receipts were exported by the real Python BridgeRuntime with an offline fake hardware backend in host test commit a4aa48f. They cover a healthy held session, a hand stop while a point worker is still quiescing, and a later clear request starting a fresh cold admission after the host confirmed full OFF internally. The native observer need not sample that intermediate OFF.

The Swift regression rebinds only identity and clock origin to its isolated controller. It retains the actual status shape, motor/light declarations and thermal fields. These are offline protocol fixtures, not physical validation.
