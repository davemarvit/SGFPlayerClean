# Integrated physical-test candidate 0.258

**Historical package receipt.** This 0.258 candidate was subsequently installed
and later superseded by installed 0.260/build 261. Preserve its hashes/results;
they do not attest the newer build. See [the current checklist](IntegrationChecklist.md)
for exact 0.260 paired acceptance, installation, rollback and physical limits.

Version0.258/build259 was built and signed from `87fc4a9` on the isolated
`codex/integrated-physical-test-candidate` branch. Packaging did not install or
launch it. Installation and physical acceptance remain separate actions owned
by the coordinating agent and recorded in the IntegrationChecklist.

The package combines ambiguity recognition, fast-test idle worker reuse,
recovery/progress UI, optional native timing logs, named stone-set metadata,
screen-only illegal-move feedback and four practice starts. Named stone-set
profiles do not yet perform optical correction; illegal feedback does not drive
a laser marker.

The durable candidate and exact verification receipts are at:

`/Users/dave/Documents/SGF PLayer/work/ai-laser-integration/stone-session-20261123/app-0258-candidate`

All23 selected suites have passing results. Twenty initially passed runtime
`9b51d45`; five focused suites passed final runtime `87fc4a9` after fixture fixes
and an optional ExperimentModel AI/online injection seam isolated PlayModeTests
from the user's saved game. Nil defaults preserve production construction. The
real-engine/HumanSL profiles passed before that constructor-only change and
were not rerun. Combined receipts explicitly distinguish these source versions;
the original failure logs remain available.

Fresh mandatory native→host→native acceptance passed against host
`42e50221262cd79fdf99dba922c0422ece9945b7` in
`/Users/dave/DYNAMIXEL-Go-Pointer-worktrees/workflow-review-integration`:
229 native-export checks,16 host tests,241 status checks and495 recovery checks
(with225/133 native controls). This uses actual encoders/parsers/publishers and
native consumers with fake hardware. It does not establish physical optics,
recognition, thermal behavior or live latency. The app does not automatically
install or start this host checkout.

The optimized build verified167 ordered source inputs and7 build inputs before
publication. The package includes snapshots,170 resource-origin hashes and173
bundle-file hashes. The copied Developer-ID signature passed strict/deep
verification. Exact identities:

- Ordered source: `2d42527461207fc9661c5dc694bb870b2a09e837693586cfc5a6d87d7f7fca3e`
- Signed binary: `b0bb342eb71d055d5345d55d2de1fef93e06ffb10802d66ffa8638639d932500`
- Canonical bundle manifest: `31c9fd1dde179a9d98d7ca9b6d6d0f167f052ef2f015e9f26b7c22af572913dc`

Capture metadata remains `/Users/Dave/SGFPlayerClean/PhysicalGo/Captures`.
Installed0.253 and retained0.256/0.257 binary/plist hashes were unchanged after
packaging. Build input identity does not imply immutable runtime recordings,
fixtures or installed operating-system dependencies.

Before installation, take a fresh `before-0258-install` bundle/data backup.
Practice mode adds optional saved snapshot context and immutable original-game
backups. Return to the saved real game before downgrading when possible;
otherwise close the app and restore the fresh pre-install data snapshot with
the prior bundle. Preserve practice backups and later real-game progress.
An executable-only downgrade with a current practice game is insufficient.
The named stone-set library is separate and ignored by older apps.
